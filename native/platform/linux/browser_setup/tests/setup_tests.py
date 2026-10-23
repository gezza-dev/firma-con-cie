#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""All profiles, module databases and Snap directories are temporary fixtures."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'firefox_setup.py'
spec = importlib.util.spec_from_file_location('firefox_setup', SOURCE)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
parser = argparse.ArgumentParser()
parser.add_argument('--native', type=Path)
args, remaining = parser.parse_known_args()
NATIVE = args.native.resolve() if args.native else None


class Fixture(unittest.TestCase):
    def setUp(self):
        previous_mask = os.umask(0o077)
        self.addCleanup(os.umask, previous_mask)
        self.temp = tempfile.TemporaryDirectory(prefix='cie-firefox-setup-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.runtime = self.home / 'runtime with spaces'
        self.runtime.mkdir()
        (self.runtime / 'browser_setup').mkdir()
        for name in setup.LIBRARIES:
            (self.runtime / name).write_bytes(('synthetic library ' + name).encode())
        (self.runtime / 'browser_setup/firefox_setup.py').write_bytes(SOURCE.read_bytes())
        (self.runtime / 'browser_setup/libcie_browser_setup_guard.so').write_bytes(b'synthetic guard')
        self.refresh_manifest()
        self.proc = self.home / 'proc'
        self.proc.mkdir()
        self.connected = False
        self.commands = []
        self.service = setup.FirefoxSetup(self.home, self.runtime, proc=self.proc, run=self.run_fake)
        self.service.modutil = str(self.runtime / 'fake-modutil')
        Path(self.service.modutil).touch()

    def refresh_manifest(self):
        files = {str(p.relative_to(self.runtime)): setup.digest(p.read_bytes())
                 for p in self.runtime.rglob('*') if p.is_file() and p.name != 'backend-manifest.json'}
        (self.runtime / 'backend-manifest.json').write_text(json.dumps(
            dict(system='linux', linux_web_full_pin_only=True, linux_firefox_pkcs11=True,
                 linux_firefox_snap_core24_abi_verified=True, files=files)))

    def profile(self, target='firefox', label='test profile', suffix='p1', *, root=None):
        root = root or (self.home / '.mozilla/firefox' if target == 'firefox'
                        else self.home / 'snap/firefox/common/.mozilla/firefox')
        path = root / suffix
        path.mkdir(parents=True, mode=0o700)
        (root / 'profiles.ini').write_text(f'[Profile0]\nName={label}\nIsRelative=1\nPath={suffix}\n')
        (path / 'cert9.db').write_bytes(b'foreign certificates, preserve byte for byte')
        (path / 'key4.db').write_bytes(b'foreign encrypted keys, preserve byte for byte')
        (path / 'pkcs11.txt').write_text('library=\nname=NSS Internal PKCS #11 Module\nNSS=Flags=internal,critical\n\n'
                                        'library=/unrelated/module.so\nname=Other provider\nNSS=trustOrder=73\n\n')
        return path

    def identity(self, target='firefox'):
        return next(p['id'] for p in self.service.profiles() if p['target'] == target)

    def snapshot(self, directory):
        return {str(p.relative_to(directory)): setup.digest(p.read_bytes()) for p in directory.rglob('*') if p.is_file()}

    def run_fake(self, command, **kwargs):
        self.commands.append(command)
        if command[:2] == ['/usr/bin/snap', 'connections']:
            slot = ':pcscd' if self.connected else '-'
            return subprocess.CompletedProcess(command, 0, f'Interface Plug Slot Notes\npcscd firefox:pcscd {slot} manual\n', '')
        if command[:3] == ['/usr/bin/pkexec', '/usr/bin/snap', 'connect']:
            self.assertEqual(command[3:], ['firefox:pcscd'])
            self.connected = True
            return subprocess.CompletedProcess(command, 0, '', '')
        self.assertEqual(command[0], self.service.modutil)
        self.assertIn('-nocertdb', command)
        self.assertIn('-rawadd', command)
        self.assertTrue(kwargs['env']['LD_PRELOAD'].startswith('/proc/self/fd/'))
        self.assertEqual(len(kwargs['pass_fds']), 1)
        specification = dict(part.split('=', 1) for part in shlex.split(command[command.index('-rawadd') + 1]))
        database = Path(kwargs['cwd']) / 'pkcs11.txt'
        entries = [entry for entry in setup.records(database.read_bytes() if database.exists() else b'') if entry['name'] != specification['name']]
        entries.append(specification)
        database.write_text(''.join(''.join(f'{key}={value}\n' for key, value in item.items()) + '\n' for item in entries))
        return subprocess.CompletedProcess(command, 0, '', '')


class PolicyTests(Fixture):
    def test_uninitialized_profiles_are_omitted_without_initializing_databases(self):
        profile = self.profile()
        for missing in ['cert9.db', 'key4.db', 'pkcs11.txt']:
            file = profile / missing; data = file.read_bytes(); file.unlink()
            before = self.snapshot(self.home)
            with self.subTest(missing=missing):
                self.assertEqual(self.service.inspect()['profiles'], [])
                with self.assertRaisesRegex(setup.SetupError, 'profile_uninitialized'):
                    self.service.plan(self.identity())
                self.assertEqual(before, self.snapshot(self.home))
            file.write_bytes(data)
        self.assertFalse(self.commands)

    def test_initialized_profiles_remain_when_an_unused_profile_exists(self):
        profile = self.profile()
        unused = profile.parent / 'unused'; unused.mkdir()
        with (profile.parent / 'profiles.ini').open('a') as file:
            file.write('[Profile1]\nName=Unused\nIsRelative=1\nPath=unused\n')
        self.profile('snap')
        inspected = self.service.inspect()
        self.assertEqual(len(inspected['profiles']), 2)
        self.assertEqual({p['target'] for p in inspected['profiles']}, {'firefox', 'snap'})
        self.assertFalse(any(unused.iterdir()))

    def test_malformed_initialized_profiles_are_reported_not_hidden(self):
        profile = self.profile()
        (profile / 'pkcs11.txt').write_text('invalid NSS configuration')
        inspected = self.service.inspect()
        self.assertEqual(len(inspected['profiles']), 1)
        self.assertEqual(inspected['profiles'][0]['state'], 'profile_invalid')

    def test_xdg_and_snap_ubuntu_indexes_are_discovered_without_writes(self):
        desktop = self.profile(root=self.home / '.config/mozilla/firefox')
        snap = self.profile('snap')
        for profile in [desktop, snap]:
            profile.parent.chmod(0o775)
            (profile.parent / 'profiles.ini').chmod(0o664)
        before = self.snapshot(self.home)
        inspected = self.service.inspect()
        self.assertEqual({p['target'] for p in inspected['profiles']}, {'firefox', 'snap'})
        self.assertEqual(len(inspected['profiles']), 2)
        self.assertTrue(all(p['state'] == 'needs_setup' for p in inspected['profiles']))
        self.assertEqual(before, self.snapshot(self.home))
        self.assertTrue(all(c[0] == '/usr/bin/snap' for c in self.commands))

    def test_custom_xdg_and_legacy_duplicate_profile_are_listed_once(self):
        config = self.home / 'custom config'
        profile = self.profile(root=config / 'mozilla/firefox')
        legacy = self.home / '.mozilla/firefox'; legacy.mkdir(parents=True)
        (legacy / 'profiles.ini').write_text(f'[Profile0]\nName=Same profile\nIsRelative=0\nPath={profile}\n')
        with patch.dict(os.environ, XDG_CONFIG_HOME=str(config)):
            self.assertEqual(len(self.service.profiles()), 1)
            self.assertTrue(self.service.plan(self.identity())['ok'])

    def test_invalid_or_external_xdg_does_not_escape_home(self):
        self.profile(root=self.home / '.config/mozilla/firefox')
        for value in ['relative/config', '/tmp/external-config', str(self.home / '../outside')]:
            with self.subTest(value=value), patch.dict(os.environ, XDG_CONFIG_HOME=value):
                self.assertEqual(len(self.service.profiles()), 1)

    def test_snap_xdg_profile_stays_a_snap_target(self):
        self.profile('snap', root=self.home / 'snap/firefox/common/.config/mozilla/firefox')
        plan = self.service.plan(self.identity('snap'))
        self.assertEqual(plan['target'], 'snap')
        self.assertTrue(Path(plan['library']).is_relative_to(self.home / 'snap/firefox/common/firma-con-cie-module-v1'))

    def test_readable_index_does_not_relax_selected_profile_permissions(self):
        profile = self.profile()
        (profile.parent / 'profiles.ini').chmod(0o664)
        for name in ['pkcs11.txt', 'cert9.db', 'key4.db']:
            file = profile / name; file.chmod(0o660)
            with self.subTest(name=name), self.assertRaisesRegex(setup.SetupError, 'unsafe_path'):
                self.service.plan(self.identity())
            file.chmod(0o600)
        profile.chmod(0o770)
        with self.assertRaisesRegex(setup.SetupError, 'unsafe_path'):
            self.service.profiles()

    def test_world_writable_or_symlinked_index_is_refused(self):
        profile = self.profile()
        index = profile.parent / 'profiles.ini'; index.chmod(0o666)
        with self.assertRaisesRegex(setup.SetupError, 'unsafe_path'):
            self.service.profiles()
        data = index.read_bytes(); index.unlink()
        other = self.home / 'index'; other.write_bytes(data)
        index.symlink_to(other)
        with self.assertRaisesRegex(setup.SetupError, 'unsafe_path'):
            self.service.profiles()

    def test_closed_firefox_lock_file_respects_original_umask(self):
        profile = self.profile()
        lock = profile / '.parentlock';lock.touch();lock.chmod(0o664)
        plan = self.service.plan(self.identity())
        self.assertTrue(self.service.apply(plan['id'], plan['fingerprint'])['ok'])

    def test_snap_inspection_does_not_copy_or_authorize(self):
        self.profile('snap')
        before = self.snapshot(self.home)
        self.service.inspect()
        self.assertEqual(before, self.snapshot(self.home))
        self.assertFalse(self.connected)
        self.assertFalse(any(c[0] != '/usr/bin/snap' for c in self.commands))

    def test_snap_update_keeps_previous_generation_and_uses_new_hash(self):
        self.profile('snap')
        plan = self.service.plan(self.identity('snap'))
        self.service.apply(plan['id'], plan['fingerprint'])
        old = Path(plan['library']).parent
        before = self.snapshot(old)
        (self.runtime / setup.LIBRARIES[0]).write_bytes(b'new synthetic module version')
        self.refresh_manifest()
        plan = self.service.plan(self.identity('snap'))
        self.assertNotEqual(Path(plan['library']).parent, old)
        self.service.apply(plan['id'], plan['fingerprint'])
        self.assertEqual(before, self.snapshot(old))

    def test_system_proxy_is_not_initialized_or_duplicated(self):
        profile = self.profile()
        with (profile / 'pkcs11.txt').open('a') as file:
            file.write('library=/usr/lib/p11-kit-proxy.so\nname=System proxy\n\n')
        with self.assertRaisesRegex(setup.SetupError, 'module_conflict'):
            self.service.plan(self.identity())
        self.assertFalse(self.commands)

    def test_inspection_and_plan_are_read_only_and_load_no_modules(self):
        profile = self.profile()
        before = self.snapshot(self.home)
        state = self.service.inspect()
        self.assertEqual(len(state['profiles']), 1)
        self.assertEqual(state['profiles'][0]['label'], 'test profile')
        self.service.plan(self.identity())
        self.assertEqual(before, self.snapshot(self.home))
        self.assertEqual(self.commands, [])

    def test_only_selected_profile_changes_and_cert_keys_are_preserved(self):
        selected = self.profile()
        other = self.profile('snap')
        before_other = self.snapshot(other)
        before_keys = {n: (selected / n).read_bytes() for n in ['cert9.db', 'key4.db']}
        plan = self.service.plan(self.identity())
        result = self.service.apply(plan['id'], plan['fingerprint'])
        self.assertTrue(result['configured'])
        self.assertFalse(result['browserLoginTested'])
        self.assertEqual(before_other, self.snapshot(other))
        self.assertEqual(before_keys, {n: (selected / n).read_bytes() for n in before_keys})
        self.assertIn(b'Other provider', (selected / 'pkcs11.txt').read_bytes())
        plan = self.service.plan(self.identity())
        count = len(self.commands)
        self.service.apply(plan['id'], plan['fingerprint'])
        self.assertEqual(len(self.commands), count)

    def test_changed_plan_does_not_write_configuration(self):
        profile = self.profile()
        plan = self.service.plan(self.identity())
        with (profile / 'pkcs11.txt').open('a') as file:
            file.write('library=/new/provider.so\nname=New external module\n\n')
        before = (profile / 'pkcs11.txt').read_bytes()
        with self.assertRaisesRegex(setup.SetupError, 'plan_changed'):
            self.service.apply(plan['id'], plan['fingerprint'])
        self.assertEqual(before, (profile / 'pkcs11.txt').read_bytes())
        self.assertFalse(self.commands)

    def test_live_firefox_blocks_apply(self):
        self.profile()
        plan = self.service.plan(self.identity())
        process = self.proc / '123';process.mkdir();(process / 'comm').write_text('firefox\n')
        with self.assertRaisesRegex(setup.SetupError, 'browser_running'):
            self.service.apply(plan['id'], plan['fingerprint'])
        self.assertFalse(self.commands)

    def test_external_profile_lock_blocks_apply(self):
        profile = self.profile()
        plan = self.service.plan(self.identity())
        script = 'import fcntl,sys; f=open(sys.argv[1],"w"); fcntl.lockf(f,fcntl.LOCK_EX); print("ready",flush=True); sys.stdin.read()'
        child = subprocess.Popen([os.sys.executable, '-c', script, str(profile / '.parentlock')],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'ready')
            with self.assertRaisesRegex(setup.SetupError, 'browser_running'):
                self.service.apply(plan['id'], plan['fingerprint'])
        finally:
            child.communicate('', timeout=5)

    def test_conflicting_name_is_not_replaced(self):
        profile = self.profile()
        with (profile / 'pkcs11.txt').open('a') as file:
            file.write(f'library=/foreign/module.so\nname={setup.NAME}\n\n')
        before = self.snapshot(profile)
        with self.assertRaisesRegex(setup.SetupError, 'module_conflict'):
            self.service.plan(self.identity())
        self.assertEqual(before, self.snapshot(profile))

    def test_symlink_and_escaping_profiles_are_refused(self):
        profile = self.profile()
        data = (profile / 'pkcs11.txt').read_bytes()
        (profile / 'pkcs11.txt').unlink()
        outside = self.home / 'outside';outside.write_bytes(data)
        (profile / 'pkcs11.txt').symlink_to(outside)
        with self.assertRaisesRegex(setup.SetupError, 'unsafe_path'):
            self.service.plan(self.identity())

    def test_runtime_tampering_is_refused(self):
        self.profile()
        (self.runtime / setup.LIBRARIES[0]).write_bytes(b'tampered')
        with self.assertRaisesRegex(setup.SetupError, 'runtime_invalid'):
            self.service.plan(self.identity())

    def test_snap_copies_only_libraries_and_does_not_change_permission(self):
        self.profile('snap')
        plan = self.service.plan(self.identity('snap'))
        result = self.service.apply(plan['id'], plan['fingerprint'])
        directory = Path(plan['library']).parent
        self.assertEqual(set(p.name for p in directory.iterdir()), {*setup.LIBRARIES, 'cie-module.json'})
        for name in setup.LIBRARIES:
            self.assertEqual((directory / name).stat().st_mode & 0o777, 0o600)
            self.assertEqual((directory / name).read_bytes(), (self.runtime / name).read_bytes())
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertFalse(self.connected)
        self.assertEqual(result['snapPermission'], 'disconnected')
        self.assertFalse(any(c[0] == '/usr/bin/pkexec' for c in self.commands))

    def test_snap_copy_tampering_does_not_get_overwritten(self):
        profile = self.profile('snap')
        plan = self.service.plan(self.identity('snap'))
        self.service.apply(plan['id'], plan['fingerprint'])
        library = Path(plan['library']);library.write_bytes(b'tampered')
        before = (profile / 'pkcs11.txt').read_bytes()
        with self.assertRaises(setup.SetupError):
            self.service.plan(self.identity('snap'))
        self.assertEqual(library.read_bytes(), b'tampered')
        self.assertEqual(before, (profile / 'pkcs11.txt').read_bytes())

    def test_registration_failure_restores_original(self):
        profile = self.profile()
        plan = self.service.plan(self.identity())
        before = (profile / 'pkcs11.txt').read_bytes()
        def fail(*args, **kwargs):
            return subprocess.CompletedProcess(args, 1, '', '')
        self.service.run = fail
        with self.assertRaisesRegex(setup.SetupError, 'registration_failed_restored'):
            self.service.apply(plan['id'], plan['fingerprint'])
        self.assertEqual(before, (profile / 'pkcs11.txt').read_bytes())

    def test_permission_is_a_separate_fixed_command(self):
        self.profile('snap')
        self.assertTrue(self.service.connect_pcsc()['ok'])
        self.assertIn(['/usr/bin/pkexec', '/usr/bin/snap', 'connect', 'firefox:pcscd'], self.commands)
        count = len(self.commands)
        self.service.connect_pcsc()
        self.assertEqual(sum(c[0] == '/usr/bin/pkexec' for c in self.commands), 1)


@unittest.skipUnless(NATIVE and shutil.which('certutil') and shutil.which('modutil'), 'Native fixture/tools not supplied')
class RealNssTests(Fixture):
    def test_raw_module_database_preserves_foreign_modules_without_loading_them(self):
        profile = self.profile(suffix='profile with spaces')
        for name in setup.LIBRARIES:
            source = NATIVE / 'backend' / name if name == 'libcie-pkcs11.so' else NATIVE / name
            shutil.copy2(source, self.runtime / name)
        shutil.copy2(NATIVE / 'libcie_browser_setup_guard.so', self.runtime / 'browser_setup/libcie_browser_setup_guard.so')
        self.refresh_manifest()
        (profile / 'cert9.db').unlink();(profile / 'key4.db').unlink();(profile / 'pkcs11.txt').unlink()
        subprocess.run(['/usr/bin/certutil', '-N', '--empty-password', '-d', 'sql:' + str(profile)], check=True, capture_output=True)
        probe = NATIVE / 'libcie_setup_no_load_probe.so'
        marker = self.home / 'foreign-was-loaded'
        with (profile / 'pkcs11.txt').open('a') as file:
            file.write(f'\nlibrary={probe}\nname=Other provider\nNSS=trustOrder=73\n\n')
        before = {n: (profile / n).read_bytes() for n in ['cert9.db', 'key4.db']}
        self.service.modutil = '/usr/bin/modutil';self.service.run = subprocess.run
        plan = self.service.plan(self.identity())
        with patch.dict(os.environ, CIE_SETUP_PROBE_MARKER=str(marker)):
            self.assertTrue(self.service.apply(plan['id'], plan['fingerprint'])['ok'])
        self.assertFalse(marker.exists(), 'raw registration must not initialize foreign modules')
        self.assertEqual(before, {n: (profile / n).read_bytes() for n in before})
        self.assertTrue(self.service.plan(self.identity())['alreadyConfigured'])


if __name__ == '__main__':
    unittest.main(argv=[os.sys.argv[0], *remaining])
