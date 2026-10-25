#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""AppImage-only browser setup: immutable per-user module generations.

Reuses native profile discovery, locks, guarded NSS generation and Snap setup.
Inspect/plan never installs files. Existing valid /opt native registrations stay
at their current path. No PIN, card access or private pairing data is needed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from firefox_setup import FirefoxSetup, SetupError, LIBRARIES, NAME, checked, read_private, records
from chrome_setup import ChromeSetup


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


class PersistentModule:
    native_runtime = Path('/opt/firma-con-cie/cie_native')

    def module_base(self):
        # Stay inside HOME even when XDG_DATA_HOME is malformed or external.
        data = Path(os.environ.get('XDG_DATA_HOME') or self.home / '.local/share')
        if not data.is_absolute() or '..' in data.parts or not data.is_relative_to(self.home):
            data = self.home / '.local/share'
        # Do not put executable browser modules below shared/writable data
        # directories. A private HOME namespace also handles common umask 002.
        for ancestor in [data, *data.parents]:
            if not ancestor.is_relative_to(self.home): break
            if ancestor.exists() or ancestor.is_symlink():
                try: checked(ancestor, directory=True)
                except (SetupError, OSError): return self.home / '.firma-con-cie/pkcs11/v1'
        return data / 'firma-con-cie/pkcs11/v1'

    def generation(self):
        hashes = self.runtime_files()
        hashes = {n: hashes[n] for n in LIBRARIES}
        return self.module_base() / digest(hashes), hashes

    def verify_persistent(self, directory, hashes):
        checked(directory, directory=True)
        expected = {*LIBRARIES, 'backend-manifest.json'}
        if set(p.name for p in directory.iterdir()) != expected:
            raise SetupError('module_conflict')
        manifest = json.loads(read_private(directory / 'backend-manifest.json'))
        if (manifest.get('appimage_module_schema') != 1 or manifest.get('files') != hashes
                or not manifest.get('linux_web_full_pin_only') or not manifest.get('linux_firefox_pkcs11')):
            raise SetupError('module_conflict')
        for name, checksum in hashes.items():
            if hashlib.sha256(read_private(directory / name, maximum=64*1024*1024)).hexdigest() != checksum:
                raise SetupError('module_conflict')

    def plan(self, identity='chrome-desktop'):
        value = super().plan(identity)
        if value['target'] == 'snap':
            return value  # Original verified Snap generation remains unchanged.
        profile = next(p for p in self.profiles() if p['id'] == identity)
        candidates = [m for m in records(read_private(profile['path'] / 'pkcs11.txt'))
                      if m['name'] == NAME or Path(m['library']).name == LIBRARIES[0]]
        directory, hashes = self.generation()
        library = directory / LIBRARIES[0]
        already = False
        if directory.exists() or directory.is_symlink():
            self.verify_persistent(directory, hashes)
        if candidates:
            previous = Path(candidates[0]['library'])
            if previous.parent == self.native_runtime:
                manifest = json.loads((self.native_runtime / 'backend-manifest.json').read_text())
                if (manifest.get('linux_web_full_pin_only') and
                    all(not (self.native_runtime / n).is_symlink() and
                        hashlib.sha256((self.native_runtime / n).read_bytes()).hexdigest() == manifest['files'].get(n)
                        for n in LIBRARIES)):
                    library, already = previous, True
            elif previous == library:
                self.verify_persistent(directory, hashes)
                already = True
        value['fingerprint'] = digest([value['fingerprint'], str(library), hashes])
        value.update(library=str(library), alreadyConfigured=already)
        return value

    def install_generation(self):
        directory, hashes = self.generation()
        if directory.exists() or directory.is_symlink():
            self.verify_persistent(directory, hashes)
            return
        # mkdir with explicit modes; check every ancestor without symlinks.
        current = self.home
        checked(current, directory=True)
        for part in directory.parent.relative_to(self.home).parts:
            current /= part
            if not current.exists() and not current.is_symlink():
                current.mkdir(mode=0o700)
            checked(current, directory=True)
        temporary = Path(tempfile.mkdtemp(prefix='.cie-module-', dir=directory.parent))
        try:
            for name, checksum in hashes.items():
                data = (self.runtime / name).read_bytes()
                if hashlib.sha256(data).hexdigest() != checksum:
                    raise SetupError('runtime_invalid')
                file = temporary / name
                with file.open('xb') as out:
                    os.fchmod(out.fileno(), 0o600); out.write(data); out.flush(); os.fsync(out.fileno())
            manifest = dict(appimage_module_schema=1, system='linux', linux_web_full_pin_only=True,
                            linux_firefox_pkcs11=True, files=hashes)
            file = temporary / 'backend-manifest.json'
            with file.open('x') as out:
                os.fchmod(out.fileno(), 0o600);json.dump(manifest, out, sort_keys=True);out.flush();os.fsync(out.fileno())
            self.verify_persistent(temporary, hashes)
            try:
                temporary.rename(directory)
            except OSError:
                if not directory.exists(): raise
                self.verify_persistent(directory, hashes)
            parent_fd = os.open(directory.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try: os.fsync(parent_fd)
            finally: os.close(parent_fd)
        finally:
            if temporary.exists(): shutil.rmtree(temporary)

    def apply(self, identity, expected):
        if os.geteuid() == 0: raise SetupError('run_as_user')
        if self.processes_running(): raise SetupError('browser_running')
        profile = next((p for p in self.profiles() if p['id'] == identity), None)
        if profile is None: raise SetupError('profile_missing')
        with self.profile_lock(profile['path']):
            value = self.plan(identity)
            if value['fingerprint'] != expected: raise SetupError('plan_changed')
            if value['target'] != 'snap' and not value['alreadyConfigured']:
                self.install_generation()
        # Reacquire and revalidate before any NSS write, using the original
        # empty-database RawAdd workflow and rollback policy.
        return super().apply(identity, expected)


class AppImageFirefox(PersistentModule, FirefoxSetup): pass
class AppImageChrome(PersistentModule, ChromeSetup): pass


def main(browser):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action', choices=['inspect','plan','apply','connect-pcsc'], default='inspect')
    parser.add_argument('--profile', default='chrome-desktop' if browser == 'chrome' else '')
    parser.add_argument('--fingerprint', default='')
    args = parser.parse_args()
    runtime = Path(__file__).resolve().parent.parent
    cls = AppImageFirefox if browser == 'firefox' else AppImageChrome
    kwargs = dict(modutil=str(runtime.parent / 'tools/modutil'))
    if browser == 'chrome': kwargs['data_home'] = os.environ.get('XDG_DATA_HOME')
    service = cls(Path.home(), runtime, **kwargs)
    try:
        if args.action == 'inspect': result = service.inspect()
        elif args.action == 'plan': result = service.plan(args.profile)
        elif args.action == 'apply': result = service.apply(args.profile, args.fingerprint)
        elif browser == 'firefox': result = service.connect_pcsc()
        else: raise SetupError('unsupported')
    except SetupError as error: result = dict(ok=False, code=str(error))
    except (OSError, ValueError, KeyError): result = dict(ok=False, code='configuration_unavailable')
    print(json.dumps(result, ensure_ascii=False))
