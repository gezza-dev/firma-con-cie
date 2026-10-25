#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Companion policy: synthetic HOME, processes, libraries and certificates only."""
import json
import os
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import flatpak_helper as helper
import setup_tests as fixtures

class Public:
    def __init__(self): self.published = []; self.prepared = False
    def verify(self): pass
    def validate(self, certificates):
        if any(v == 'ff' for v in certificates.values()): raise helper.SetupError('public_certificate_unavailable')
    def ready(self, target, certificates): return not certificates or self.prepared
    def publish(self, target, certificates):
        self.validate(certificates); self.published.append((target, dict(certificates))); self.prepared = True

class Policy(fixtures.Fixture):
    def setUp(self):
        super().setUp()
        source = Path(helper.__file__).parent / 'chrome_setup.py'
        (self.runtime / 'browser_setup/chrome_setup.py').write_bytes(source.read_bytes())
        self.refresh_manifest()
        self.service = helper.CompanionFirefox(self.home, self.runtime, proc=self.proc, run=self.run_fake)
        self.service.modutil = str(self.runtime / 'fake-modutil')
        self.public = Public(); self.now = 0
        self.companion = helper.Companion(self.home, self.runtime, firefox=self.service,
            chrome=helper.CompanionChrome(self.home, self.runtime, proc=self.proc, chrome_paths=(), run=self.run_fake),
            public=self.public, clock=lambda: self.now)
        self.companion.chrome.modutil = self.service.modutil
        self.profile(); self.certificates = {'SYNTHETIC': '0102'}
    def request(self, op, sender=':1.2', **kwargs):
        return self.companion.request(sender, dict(protocol=1, op=op, certificates=self.certificates, **kwargs))
    def plan(self): return self.request('firefox.plan', profile=self.identity())
    def apply(self, plan):
        with patch('os.geteuid', return_value=1000):
            return self.request('firefox.apply', profile=self.identity(), fingerprint=plan['fingerprint'])
    def test_readonly_health_inspection_plan_no_subprocess_or_changes(self):
        before = self.snapshot(self.home)
        self.assertTrue(self.request('status')['fullPinRequired'])
        self.assertEqual(self.request('firefox.inspect')['profiles'][0]['state'], 'needs_setup')
        self.assertFalse(self.plan()['alreadyConfigured'])
        self.assertEqual(before, self.snapshot(self.home)); self.assertFalse(self.commands)
    def test_explicit_apply_and_repeat_token_rejection(self):
        p = self.plan(); result = self.apply(p)
        self.assertTrue(result['publicDataPrepared']); self.assertFalse(result['browserLoginTested'])
        self.assertEqual(self.public.published, [('firefox', self.certificates)])
        self.assertTrue(self.request('firefox.inspect')['profiles'][0]['state'] == 'configured')
        with self.assertRaisesRegex(helper.SetupError, 'plan_changed'): self.apply(p)
        self.assertEqual(len(self.commands), 1)
    def test_no_pin_paths_commands_or_bad_protocol(self):
        for field in ['pin', 'prefix', 'path', 'command', 'home', 'runtime', 'privateKey']:
            with self.subTest(field=field), self.assertRaisesRegex(helper.SetupError, 'invalid_request'):
                self.request('status', **{field: 'unexpected'})
        for request in [dict(protocol=2, op='status'), dict(protocol=1, op='shell'),
                dict(protocol=1, op='status', certificates={'../escape':'01'}),
                dict(protocol=1, op='status', certificates={'TEST':'0'*16386})]:
            with self.assertRaises(helper.SetupError): self.companion.request(':1.2', request)
        self.assertFalse(self.commands)
    def test_token_bound_to_sender_certificate_payload_and_lifetime(self):
        for kind in ['sender', 'certificates', 'expiry']:
            p = self.plan(); original = dict(self.certificates)
            if kind == 'certificates': self.certificates['OTHER'] = '01'
            if kind == 'expiry': self.now += 301
            with self.subTest(kind=kind), self.assertRaisesRegex(helper.SetupError, 'plan_changed'):
                self.request('firefox.apply', sender=':1.3' if kind == 'sender' else ':1.2',
                    profile=self.identity(), fingerprint=p['fingerprint'])
            self.certificates = original
        self.assertFalse(self.commands); self.assertFalse(self.public.published)
    def test_stale_profile_and_running_browser_block_before_write(self):
        p = self.plan(); profile = self.service.profiles()[0]['path']
        with (profile / 'pkcs11.txt').open('ab') as f: f.write(b'# changed\n')
        with self.assertRaisesRegex(helper.SetupError, 'plan_changed'): self.apply(p)
        p = self.plan(); proc = self.proc / '123'; proc.mkdir(); (proc / 'comm').write_text('firefox\n')
        with self.assertRaisesRegex(helper.SetupError, 'browser_running'): self.apply(p)
        self.assertFalse(self.commands); self.assertFalse(self.public.published)
    def test_invalid_public_batch_prevents_registration(self):
        self.certificates = {'SYNTHETIC':'ff'}; p = self.plan()
        before = self.snapshot(self.home)
        with self.assertRaisesRegex(helper.SetupError, 'public_certificate_unavailable'): self.apply(p)
        self.assertEqual(before, self.snapshot(self.home)); self.assertFalse(self.commands)
    def test_existing_native_registration_keeps_path_bytes_certificates_keys(self):
        native = self.home / 'opt/firma-con-cie/cie_native'; shutil.copytree(self.runtime, native)
        self.service.native_runtime = native
        profile = self.service.profiles()[0]['path']
        with (profile / 'pkcs11.txt').open('a') as f:
            f.write(f'library={native / helper.LIBRARIES[0]}\nname={helper.NAME}\n\n')
        before = {n: (profile/n).read_bytes() for n in ['pkcs11.txt','cert9.db','key4.db']}
        self.assertTrue(self.service.plan(self.identity())['alreadyConfigured'])
        self.assertEqual(self.request('firefox.inspect')['profiles'][0]['state'], 'needs_setup')
        p = self.plan(); self.assertFalse(p['alreadyConfigured']); self.apply(p)
        self.assertTrue(self.plan()['alreadyConfigured']); self.assertEqual(before,{n:(profile/n).read_bytes() for n in before})
        self.assertFalse(self.commands); self.assertFalse((profile / 'cie-firefox-setup-backup.json').exists())
    def test_snap_registration_and_permission_are_separate_explicit_actions(self):
        self.profile('snap'); identity=self.identity('snap')
        p=self.request('firefox.plan',profile=identity)
        self.assertFalse(any(c[0]=='/usr/bin/pkexec' for c in self.commands))
        with patch('os.geteuid', return_value=1000):
            self.request('firefox.apply',profile=identity,fingerprint=p['fingerprint'])
        self.assertEqual(self.public.published[0][0],'snap')
        self.assertFalse(self.connected)
        with patch('os.geteuid', return_value=1000): self.request('firefox.connect-pcsc')
        self.assertTrue(self.connected)
    def test_chrome_reuses_guard_and_does_not_touch_firefox(self):
        db=self.companion.chrome.database; db.mkdir(parents=True)
        profile=self.service.profiles()[0]['path']
        for name in ['cert9.db','key4.db','pkcs11.txt']: shutil.copy2(profile/name,db/name)
        before=self.snapshot(profile)
        self.assertEqual(self.request('chrome.inspect')['state'],'needs_setup')
        p=self.request('chrome.plan')
        with patch('os.geteuid',return_value=1000): self.request('chrome.apply',fingerprint=p['fingerprint'])
        self.assertEqual(self.snapshot(profile),before)
        self.assertEqual(self.public.published,[('chrome',self.certificates)])
    def test_missing_or_tampered_public_tool_is_rejected(self):
        self.companion.public=helper.PublicCertificates(self.runtime)
        with self.assertRaises((helper.SetupError, FileNotFoundError)): self.request('status')

if __name__ == '__main__': unittest.main(verbosity=2)
