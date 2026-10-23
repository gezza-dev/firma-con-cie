#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Chrome setup policy and isolated SQL NSS lifecycle; never use a user's DB."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / 'scripts'))
import configure_chrome_linux as setup


class ChromeSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cie-chrome-setup-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)

    def test_new_database_uses_xdg(self):
        self.assertEqual(setup.default_database(self.home), self.home / '.local/share/pki/nssdb')
        self.assertEqual(setup.default_database(self.home, '/tmp/custom-data'), Path('/tmp/custom-data/pki/nssdb'))
        self.assertEqual(setup.default_database(self.home, 'relative'), self.home / '.local/share/pki/nssdb')

    def test_legacy_directory_has_priority(self):
        old = self.home / '.pki/nssdb'
        old.mkdir(parents=True)
        self.assertEqual(setup.default_database(self.home, '/tmp/custom-data'), old)

    def test_plan_does_not_create_or_load_anything(self):
        db = self.home / 'missing'
        with patch.object(setup.subprocess, 'run', side_effect=AssertionError('NSS must not run')):
            result = setup.configure(setup.DEFAULT_MODULE, db)
        self.assertFalse(db.exists())
        self.assertFalse(result['configurationChanged'])
        self.assertEqual(result['command'][-1], '-force')

    def test_parse_nss_paths_with_spaces_and_unrelated_module(self):
        self.assertEqual(setup.entries('library= name="NSS Internal PKCS #11 Module"\n\n'
                                      'library="/tmp/space dir/module.so" name="Other device" NSS="trustOrder=100"\n'),
                         [{'library': '', 'name': 'NSS Internal PKCS #11 Module'},
                          {'library': '/tmp/space dir/module.so', 'name': 'Other device'}])

    def test_apply_refuses_running_browser(self):
        with patch.object(setup, 'browser_running', return_value=True):
            with self.assertRaisesRegex(ValueError, 'Chiudere'):
                setup.configure(setup.DEFAULT_MODULE, self.home, action='apply')

    def test_no_database_initialization(self):
        with patch.object(setup, 'browser_running', return_value=False):
            with self.assertRaisesRegex(ValueError, 'assente'):
                setup.configure(setup.DEFAULT_MODULE, self.home / 'missing', action='apply')

    def test_symlink_refused(self):
        link = self.home / 'link'
        link.symlink_to(self.home, target_is_directory=True)
        with patch.object(setup, 'browser_running', return_value=False):
            with self.assertRaisesRegex(ValueError, 'simbolici'):
                setup.configure(setup.DEFAULT_MODULE, link, action='apply')

    def test_module_argument_is_not_a_shell_command(self):
        with self.assertRaises(ValueError):
            setup.configure('/tmp/wrong.so', self.home)


@unittest.skipUnless(os.environ.get('CIE_NSS_TEST_TOOLS') and os.environ.get('CIE_NSS_TEST_FAKE'),
                     'Optional isolated NSS tools/fake module not supplied')
class IsolatedNssTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cie-chrome-nss-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.tools = Path(os.environ['CIE_NSS_TEST_TOOLS'])
        self.db = self.home / 'nssdb'
        self.db.mkdir(mode=0o700)
        self.module = self.home / 'directory with spaces/libcie_linux_pkcs11.so'
        self.module.parent.mkdir()
        source = Path(os.environ['CIE_NSS_TEST_FAKE']).resolve()
        assert source.name == 'libcie_linux_pkcs11_fake.so'
        shutil.copy2(source, self.module)
        self.env = dict(os.environ, CIE_PAIRING_TEST_CACHE=str(self.home / 'fake-cache'), LC_ALL='C')
        self.run_tool('certutil', '-N', '--empty-password', '-d', 'sql:' + str(self.db))

    def run_tool(self, name, *args):
        return subprocess.run([str(self.tools / name), *args], env=self.env, check=True,
                              capture_output=True, text=True, timeout=20).stdout

    def change(self, action):
        with patch.object(setup, 'browser_running', return_value=False), patch.dict(os.environ, self.env):
            return setup.configure(self.module, self.db, action=action, tool=str(self.tools / 'modutil'))

    def test_add_idempotence_remove_and_foreign_data_preserved(self):
        self.run_tool('modutil', '-dbdir', 'sql:' + str(self.db), '-add', 'Unrelated Roots',
                      '-libfile', '/usr/lib/x86_64-linux-gnu/libnssckbi.so', '-force')
        digest = lambda name: hashlib.sha256((self.db / name).read_bytes()).hexdigest()
        before = {name: digest(name) for name in ['cert9.db', 'key4.db']}
        self.assertTrue(self.change('apply')['configurationChanged'])
        self.assertFalse(self.change('apply')['configurationChanged'])
        self.assertTrue(self.change('remove')['configurationChanged'])
        self.assertFalse(self.change('remove')['configurationChanged'])
        after = setup.entries(self.run_tool('modutil', '-dbdir', 'sql:' + str(self.db), '-rawlist'))
        self.assertTrue(any(item['name'] == 'Unrelated Roots' for item in after))
        self.assertEqual(before, {name: digest(name) for name in before})

    def test_conflicting_registration_is_not_replaced_or_deleted(self):
        self.run_tool('modutil', '-dbdir', 'sql:' + str(self.db), '-add', setup.NAME,
                      '-libfile', '/usr/lib/x86_64-linux-gnu/libnssckbi.so', '-force')
        before = (self.db / 'pkcs11.txt').read_bytes()
        for action in ['apply', 'remove']:
            with self.assertRaisesRegex(ValueError, 'preesistente'):
                self.change(action)
        self.assertEqual(before, (self.db / 'pkcs11.txt').read_bytes())


if __name__ == '__main__':
    unittest.main()
