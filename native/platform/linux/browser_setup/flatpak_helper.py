#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Host-side policy for the Flatpak browser companion. No arbitrary paths/PINs.

Native FirefoxSetup/ChromeSetup are imported unchanged. Public DER publication
uses a guarded standalone tool; it never reads or writes the 'card' namespace.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

from firefox_setup import FirefoxSetup, SetupError, LIBRARIES, NAME, records, read_private, checked
from chrome_setup import ChromeSetup

PROTOCOL = 1
MAX_REQUEST = 5 * 1024 * 1024
NATIVE_RUNTIME = Path('/opt/firma-con-cie/cie_native')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


class CompanionMixin:
    """Keep an already verified native module/generation at its tested path."""
    native_runtime = NATIVE_RUNTIME

    def plan(self, identity='chrome-desktop'):
        plan = super().plan(identity)
        profile = next(p for p in self.profiles() if p['id'] == identity)
        matching = [m for m in records(read_private(profile['path'] / 'pkcs11.txt'))
                    if m['name'] == NAME or Path(m['library']).name == LIBRARIES[0]]
        if len(matching) == 1:
            existing = Path(matching[0]['library'])
            preserved = False
            if existing.parent == self.native_runtime:
                manifest = json.loads((existing.parent / 'backend-manifest.json').read_text())
                preserved = bool(manifest.get('linux_web_full_pin_only') and
                    all(not (existing.parent / n).is_symlink() and
                        hashlib.sha256((existing.parent / n).read_bytes()).hexdigest() == manifest['files'].get(n)
                        for n in LIBRARIES))
            elif profile['target'] == 'snap' and existing.parent.is_relative_to(
                    self.home / 'snap/firefox/common/firma-con-cie-module-v1'):
                marker = json.loads(read_private(existing.parent / 'cie-module.json'))
                self.verify_generation(existing.parent, marker['files'])
                preserved = True
            if preserved:
                plan['library'] = str(existing)
                plan['alreadyConfigured'] = True
                plan['fingerprint'] = digest([plan['fingerprint'], str(existing),
                    {n: hashlib.sha256((existing.parent / n).read_bytes()).hexdigest() for n in LIBRARIES}])
        return plan

    def apply(self, identity, fingerprint):
        if os.geteuid() == 0:
            raise SetupError('run_as_user')
        if self.processes_running():
            raise SetupError('browser_running')
        profile = next((p for p in self.profiles() if p['id'] == identity), None)
        if profile is None:
            raise SetupError('profile_missing')
        # An existing native registration needs public-data synchronisation only;
        # do not create backups, recopy modules or rewrite its NSS record.
        with self.profile_lock(profile['path']):
            plan = self.plan(identity)
            if plan['fingerprint'] != fingerprint:
                raise SetupError('plan_changed')
            if plan['alreadyConfigured']:
                return dict(ok=True, configured=True, library=plan['library'],
                            target=plan['target'], browserLoginTested=False)
        return super().apply(identity, fingerprint)


class CompanionFirefox(CompanionMixin, FirefoxSetup):
    pass


class CompanionChrome(CompanionMixin, ChromeSetup):
    pass


class PublicCertificates:
    def __init__(self, runtime, run=subprocess.run):
        self.runtime, self.run = Path(runtime), run

    def verify(self):
        manifest = json.loads((self.runtime / 'backend-manifest.json').read_text())
        for name in ['cie_browser_public_certificate', 'browser_setup/libcie_browser_setup_guard.so']:
            p = self.runtime / name
            if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest() != manifest['files'].get(name):
                raise SetupError('runtime_invalid')

    def call(self, operation, identity, der):
        self.verify()
        fd = os.open(self.runtime / 'browser_setup/libcie_browser_setup_guard.so', os.O_RDONLY | os.O_NOFOLLOW)
        try:
            # Never inherit a caller's preload, HOME override, SNAP variables or
            # command path. The helper service runs in the host user's session.
            env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8',
                   'LD_PRELOAD': '/proc/self/fd/' + str(fd)}
            result = self.run([str(self.runtime / 'cie_browser_public_certificate'), operation, identity],
                input=bytes.fromhex(der), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                env=env, pass_fds=(fd,), timeout=4)
            if result.returncode not in {0, 3}:
                raise SetupError('public_certificate_unavailable')
            return result.returncode == 0
        finally:
            os.close(fd)

    def validate(self, certificates):
        for identity, der in certificates.items():
            if not self.call('validate', identity, der):
                raise SetupError('public_certificate_unavailable')

    def ready(self, target, certificates):
        return all(self.call('check-' + ('snap' if target == 'snap' else 'web'), identity, der)
                   for identity, der in certificates.items())

    def publish(self, target, certificates):
        self.validate(certificates)  # Reject an invalid batch before any write.
        for identity, der in certificates.items():
            if not self.call('publish-' + ('snap' if target == 'snap' else 'web'), identity, der):
                raise SetupError('public_certificate_unavailable')


class Companion:
    def __init__(self, home, runtime, *, firefox=None, chrome=None, public=None, clock=time.monotonic):
        self.home, self.runtime = Path(home), Path(runtime)
        self.firefox = firefox or CompanionFirefox(home, runtime)
        self.chrome = chrome or CompanionChrome(home, runtime, data_home=os.environ.get('XDG_DATA_HOME'))
        self.public = public or PublicCertificates(runtime)
        self.clock, self.plans = clock, {}

    @staticmethod
    def validate(request):
        if not isinstance(request, dict) or set(request) - {'protocol', 'op', 'profile', 'fingerprint', 'certificates'}:
            raise SetupError('invalid_request')
        if request.get('protocol') != PROTOCOL:
            raise SetupError('helper_incompatible')
        op = request.get('op')
        if op not in {'status', 'firefox.inspect', 'firefox.plan', 'firefox.apply', 'firefox.connect-pcsc',
                      'chrome.inspect', 'chrome.plan', 'chrome.apply'}:
            raise SetupError('invalid_request')
        profile = request.get('profile', '')
        if not isinstance(profile, str) or (profile and not re.fullmatch(r'[0-9a-f]{64}|chrome-desktop', profile)):
            raise SetupError('invalid_request')
        fingerprint = request.get('fingerprint', '')
        if not isinstance(fingerprint, str) or (fingerprint and not re.fullmatch('[0-9a-f]{64}', fingerprint)):
            raise SetupError('invalid_request')
        certificates = request.get('certificates', {})
        if not isinstance(certificates, dict) or len(certificates) > 256:
            raise SetupError('invalid_request')
        for identity, der in certificates.items():
            if (not isinstance(identity, str) or not re.fullmatch('[A-Za-z0-9]{1,63}', identity) or
                not isinstance(der, str) or not re.fullmatch(r'(?:[0-9a-fA-F]{2}){1,8192}', der)):
                raise SetupError('invalid_request')
        return op, profile, certificates

    def request(self, sender, request):
        op, identity, certificates = self.validate(request)
        self.plans = {k: v for k, v in self.plans.items() if v['expires'] > self.clock()}
        if op == 'status':
            self.firefox.runtime_files()
            self.chrome.runtime_files()
            self.public.verify()
            return dict(ok=True, protocol=PROTOCOL, fullPinRequired=True)
        service = self.firefox if op.startswith('firefox.') else self.chrome
        action = op.split('.')[1]
        if action == 'inspect':
            result = service.inspect()
            if service is self.firefox:
                for profile in result.get('profiles', []):
                    if profile['state'] == 'configured' and not self.public.ready(profile['target'], certificates):
                        profile['state'] = 'needs_setup'
                        profile['publicDataRequired'] = True
            elif result.get('state') == 'configured' and not self.public.ready('chrome', certificates):
                result['state'] = 'needs_setup'
                result['publicDataRequired'] = True
            return result
        if action == 'connect-pcsc':
            return service.connect_pcsc()
        if service is self.chrome:
            identity = 'chrome-desktop'
        if action == 'plan':
            plan = service.plan(identity)
            result = dict(plan)
            result['alreadyConfigured'] = plan['alreadyConfigured'] and self.public.ready(plan['target'], certificates)
            if len(self.plans) >= 128:
                raise SetupError('configuration_busy')
            token = secrets.token_hex(32)
            self.plans[token] = dict(sender=sender, identity=identity, browser=op.split('.')[0],
                publicDigest=digest(certificates), plan=plan, expires=self.clock()+300)
            result['fingerprint'] = token
            return result
        token = request.get('fingerprint', '')
        prepared = self.plans.pop(token, None)  # One use, including failed operations.
        if (not prepared or prepared['sender'] != sender or prepared['identity'] != identity or
            prepared['browser'] != op.split('.')[0] or prepared['publicDigest'] != digest(certificates)):
            raise SetupError('plan_changed')
        self.public.validate(certificates)
        result = service.apply(identity, prepared['plan']['fingerprint'])
        if result.get('ok'):
            self.public.publish(prepared['plan']['target'], certificates)
            result['publicDataPrepared'] = True
        return result
