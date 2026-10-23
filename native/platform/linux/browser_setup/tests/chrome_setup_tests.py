#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Chrome wizard tests: all databases and HOME paths are temporary fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import chrome_setup as chrome
import setup_tests as fixtures


class Fixture(fixtures.Fixture):
    def setUp(self):
        super().setUp()
        (self.runtime / 'browser_setup/chrome_setup.py').write_bytes(Path(chrome.__file__).read_bytes())
        self.refresh_manifest()
        self.service = chrome.ChromeSetup(self.home, self.runtime, proc=self.proc,
                                         chrome_paths=(), run=self.run_fake)
        self.service.modutil = str(self.runtime / 'fake-modutil')
        self.db = self.service.database
        self.db.mkdir(parents=True, mode=0o700)
        for name, data in [('cert9.db', b'preserve certificates'), ('key4.db', b'preserve keys'),
                           ('pkcs11.txt', b'library=\nname=NSS Internal PKCS #11 Module\nNSS=Flags=internal,critical\n\n'
                            b'# keep comment\nlibrary=/other/module.so\nname=Other provider\nNSS=trustOrder=73\n\n')]:
            (self.db / name).write_bytes(data)

    def apply(self, plan=None):
        plan = plan or self.service.plan()
        return self.service.apply('chrome-desktop', plan['fingerprint'])


class PolicyTests(Fixture):
    def test_inspection_and_plan_are_read_only_without_loading_nss(self):
        before = self.snapshot(self.home)
        self.assertEqual(self.service.inspect()['state'], 'needs_setup')
        self.assertEqual(self.service.plan()['target'], 'chrome')
        self.assertEqual(before, self.snapshot(self.home))
        self.assertEqual(self.commands, [])

    def test_database_selection_matches_desktop_chrome(self):
        self.assertEqual(chrome.default_database(self.home, 'relative'), self.home / '.local/share/pki/nssdb')
        self.assertEqual(chrome.default_database(self.home, '/tmp/custom'), Path('/tmp/custom/pki/nssdb'))
        old = self.home / '.pki/nssdb';old.mkdir(parents=True)
        self.assertEqual(chrome.default_database(self.home, '/tmp/custom'), old)

    def test_missing_chrome_is_hidden_and_missing_database_is_not_created(self):
        shutil.rmtree(self.db)
        before = self.snapshot(self.home)
        self.assertEqual(self.service.inspect()['state'], 'not_installed')
        binary = self.home / 'chrome';binary.touch();self.service.chrome_paths = (binary,)
        self.assertEqual(self.service.inspect()['state'], 'database_uninitialized')
        self.assertFalse(self.db.exists())
        self.assertEqual(self.commands, [])

    def test_uninitialized_database_is_not_repaired(self):
        (self.db / 'key4.db').unlink()
        before = self.snapshot(self.home)
        self.assertEqual(self.service.inspect()['state'], 'database_uninitialized')
        self.assertEqual(before, self.snapshot(self.home))

    def test_apply_is_idempotent_and_preserves_certificates_keys_and_foreign_bytes(self):
        before = {n: (self.db / n).read_bytes() for n in ['cert9.db', 'key4.db']}
        foreign = (self.db / 'pkcs11.txt').read_bytes()
        result = self.apply()
        self.assertTrue(result['configured'])
        self.assertFalse(result['pinRequested'])
        self.assertFalse(result['browserLoginTested'])
        self.assertTrue((self.db / 'pkcs11.txt').read_bytes().startswith(foreign))
        self.assertEqual(before, {n: (self.db / n).read_bytes() for n in before})
        self.assertTrue((self.db / 'cie-chrome-setup-backup.json').exists())
        self.assertFalse((self.db / 'cie-firefox-setup-backup.json').exists())
        self.assertTrue(self.service.plan()['alreadyConfigured'])
        self.apply()
        self.assertEqual(len(self.commands), 1)

    def test_stale_plan_is_rejected_without_nss(self):
        plan = self.service.plan()
        with (self.db / 'pkcs11.txt').open('ab') as file:file.write(b'# another writer\n')
        with self.assertRaisesRegex(chrome.SetupError, 'plan_changed'):self.apply(plan)
        self.assertFalse(self.commands)

    def test_running_browser_blocks_apply(self):
        process = self.proc / '123';process.mkdir();(process / 'comm').write_text('chrome\n')
        with self.assertRaisesRegex(chrome.SetupError, 'browser_running'):self.apply()
        self.assertFalse(self.commands)

    def test_browser_start_during_registration_blocks_write(self):
        before = (self.db / 'pkcs11.txt').read_bytes()
        def start(command, **kwargs):
            result = self.run_fake(command, **kwargs)
            process = self.proc / '123';process.mkdir();(process / 'comm').write_text('chromium\n')
            return result
        self.service.run = start
        with self.assertRaisesRegex(chrome.SetupError, 'browser_running'):self.apply()
        self.assertEqual(before, (self.db / 'pkcs11.txt').read_bytes())

    def test_database_change_during_registration_is_not_overwritten(self):
        def change(command, **kwargs):
            result = self.run_fake(command, **kwargs)
            with (self.db / 'pkcs11.txt').open('ab') as file:file.write(b'# concurrent write\n')
            return result
        self.service.run = change
        with self.assertRaisesRegex(chrome.SetupError, 'plan_changed'):self.apply()
        self.assertTrue((self.db / 'pkcs11.txt').read_bytes().endswith(b'# concurrent write\n'))

    def test_symlinks_permissions_and_hardlinks_are_refused(self):
        original = self.db / 'pkcs11.txt';target = self.home / 'linked';original.rename(target);original.symlink_to(target)
        with self.assertRaisesRegex(chrome.SetupError, 'unsafe_path'):self.service.plan()
        original.unlink();target.rename(original);original.chmod(0o666)
        with self.assertRaisesRegex(chrome.SetupError, 'unsafe_path'):self.service.plan()
        original.chmod(0o600);os.link(original, target)
        with self.assertRaisesRegex(chrome.SetupError, 'unsafe_path'):self.service.plan()

    def test_conflicts_and_system_proxy_are_not_loaded_or_replaced(self):
        before = (self.db / 'pkcs11.txt').read_bytes()
        for record in [b'library=/usr/lib/p11-kit-proxy.so\nname=System proxy\n\n',
                       b'library=/foreign/libcie_linux_pkcs11.so\nname=Other CIE\n\n']:
            (self.db / 'pkcs11.txt').write_bytes(before + record)
            with self.assertRaisesRegex(chrome.SetupError, 'module_conflict'):self.service.plan()
        self.assertFalse(self.commands)

    def test_runtime_helper_hash_is_verified(self):
        (self.runtime / 'browser_setup/chrome_setup.py').write_bytes(b'changed')
        with self.assertRaisesRegex(chrome.SetupError, 'runtime_invalid'):self.service.plan()

    def test_concurrent_setup_lock_blocks_writes(self):
        lock = self.db / '.cie-chrome-setup.lock'
        code = 'import fcntl,sys; f=open(sys.argv[1],"w"); fcntl.lockf(f,fcntl.LOCK_EX); print("ready",flush=True); sys.stdin.read()'
        child = subprocess.Popen([sys.executable, '-c', code, str(lock)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            self.assertEqual(child.stdout.readline().strip(), b'ready')
            with self.assertRaisesRegex(chrome.SetupError, 'configuration_busy'):self.apply()
            self.assertFalse(self.commands)
        finally:
            child.stdin.close();child.wait(timeout=5);child.stdout.close()

    def test_snap_database_and_parent_traversal_are_refused(self):
        for path in [self.home / 'snap/chromium/common/pki/nssdb', self.home / 'data/../database']:
            path.mkdir(parents=True, exist_ok=True)
            self.service.database = path
            with self.assertRaises(chrome.SetupError):self.service.profiles()

    def test_root_cannot_apply(self):
        with patch.object(os, 'geteuid', return_value=0):
            with self.assertRaisesRegex(chrome.SetupError, 'run_as_user'):self.apply()
        self.assertFalse(self.commands)

    def test_registration_failure_preserves_original_without_retry(self):
        before = (self.db / 'pkcs11.txt').read_bytes();calls=[]
        def fail(*args, **kwargs):
            calls.append(args);raise subprocess.TimeoutExpired('modutil', 20)
        self.service.run = fail
        with self.assertRaisesRegex(chrome.SetupError, 'registration_failed_restored'):self.apply()
        self.assertEqual(before, (self.db / 'pkcs11.txt').read_bytes())
        self.assertEqual(len(calls), 1)

    def test_firefox_and_snap_are_untouched(self):
        self.profile();self.profile('snap')
        firefox = self.snapshot(self.home / '.mozilla')
        snap = self.snapshot(self.home / 'snap')
        self.apply()
        self.assertEqual(firefox, self.snapshot(self.home / '.mozilla'))
        self.assertEqual(snap, self.snapshot(self.home / 'snap'))
        self.assertFalse(any(c[0] in ['/usr/bin/snap', '/usr/bin/pkexec'] for c in self.commands))


@unittest.skipUnless(fixtures.NATIVE and shutil.which('certutil') and shutil.which('modutil'), 'Native tools not supplied')
class RealNssTests(Fixture):
    def test_real_guarded_registration_does_not_load_foreign_modules(self):
        native = fixtures.NATIVE
        for name in fixtures.setup.LIBRARIES:
            source = native / 'backend' / name if name == 'libcie-pkcs11.so' else native / name
            shutil.copy2(source, self.runtime / name)
        shutil.copy2(native / 'libcie_browser_setup_guard.so', self.runtime / 'browser_setup/libcie_browser_setup_guard.so')
        self.refresh_manifest()
        for name in ['cert9.db', 'key4.db', 'pkcs11.txt']:(self.db / name).unlink()
        subprocess.run(['/usr/bin/certutil', '-N', '--empty-password', '-d', 'sql:' + str(self.db)],check=True,capture_output=True)
        marker = self.home / 'foreign-loaded'
        with (self.db / 'pkcs11.txt').open('a') as file:
            file.write(f'\nlibrary={native / "libcie_setup_no_load_probe.so"}\nname=Other provider\nNSS=trustOrder=73\n\n')
        before = {n: (self.db / n).read_bytes() for n in ['cert9.db', 'key4.db']}
        foreign = (self.db / 'pkcs11.txt').read_bytes()
        self.service.modutil = '/usr/bin/modutil';self.service.run = subprocess.run
        with patch.dict(os.environ, CIE_SETUP_PROBE_MARKER=str(marker)):
            self.assertTrue(self.apply()['ok'])
        self.assertFalse(marker.exists())
        self.assertTrue((self.db / 'pkcs11.txt').read_bytes().startswith(foreign))
        self.assertEqual(before, {n: (self.db / n).read_bytes() for n in before})
        self.assertTrue(self.service.plan()['alreadyConfigured'])


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *fixtures.remaining])
