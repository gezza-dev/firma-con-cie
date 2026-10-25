#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Flatpak packaging boundaries; synthetic bytes, no native library loading."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import package_linux_flatpak as flatpak
from test_linux_packaging import PackageBoundaries


class FlatpakBoundaries(unittest.TestCase):
    def setUp(self):
        self.fixture = PackageBoundaries()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.pcsc = self.root / 'pcsclite.so.1'
        self.pcsc.write_text('synthetic client, never executed')
        self.notice = self.root / 'copyright'
        self.notice.write_text('BSD-3-clause synthetic fixture')

    def test_profile_refuses_broad_host_permissions(self):
        for permission in ['--filesystem=home', '--filesystem=host', '--device=all', '--talk-name=org.freedesktop.Flatpak']:
            with self.subTest(permission=permission):
                value = flatpak.profile()
                value['finish-args'].append(permission)
                p = self.root / 'profile.json'
                p.write_text(json.dumps(value))
                with patch.object(flatpak, 'PROFILE', p), self.assertRaisesRegex(ValueError, 'permissions'):
                    flatpak.profile()

    def test_test_identity_and_branch_cannot_replace_native_launcher(self):
        for key, value in [('id', 'it.giancarloezza.prototype.cie_flutter_prototype'), ('branch', 'stable')]:
            data = flatpak.profile()
            data[key] = value
            p = self.root / 'profile.json'
            p.write_text(json.dumps(data))
            with patch.object(flatpak, 'PROFILE', p), self.assertRaisesRegex(ValueError, 'test identity'):
                flatpak.profile()

    def test_stage_excludes_test_keys_and_exports_distinct_limited_icons(self):
        f = self.fixture
        result = flatpak.stage(f.bundle, self.root / 'stage', f.manifest, self.pcsc, self.notice, '0.1.0-test1')
        payload = result / 'files'
        app = payload / 'lib/firma-con-cie'
        native = json.loads((app / 'cie_native/backend-manifest.json').read_text())
        self.assertNotIn('tests/synthetic-test', native['files'])
        self.assertFalse((app / 'cie_native/tests').exists())
        self.assertFalse((payload / 'share/doc/cie-id-desktop/tools').exists())
        self.assertTrue((payload / 'share/doc/cie-id-desktop/LINUX_FLATPAK.md').exists())
        desktop = (payload / 'share/applications' / (flatpak.APP_ID + '.desktop')).read_text()
        self.assertIn('Exec=firma-con-cie\n', desktop)
        self.assertIn('StartupWMClass=' + flatpak.APP_ID + '\n', desktop)
        self.assertIn('Name=Firma con CIE (Flatpak test)\n', desktop)
        icons = list((payload / 'share/icons').rglob('*.png'))
        self.assertEqual(len(icons), 8)
        for p in icons:
            self.assertEqual(p.stem, flatpak.APP_ID)
            self.assertLessEqual(max(struct.unpack('>II', p.read_bytes()[16:24])), 512)
        self.assertEqual((payload / 'lib/libpcsclite.so.1').read_bytes(), self.pcsc.read_bytes())
        self.assertTrue((payload / 'share/licenses' / flatpak.APP_ID / 'pcsc-lite-copyright').exists())
        self.assertFalse((payload / 'opt').exists())
        self.assertTrue((f.native / 'tests/synthetic-test').exists())

    def test_missing_pcsc_notice_refused_before_payload_staging(self):
        self.notice.unlink()
        with self.assertRaisesRegex(ValueError, 'copyright'):
            flatpak.stage(self.fixture.bundle, self.root / 'stage', self.fixture.manifest, self.pcsc, self.notice, '0.1.0-test1')
        self.assertFalse((self.root / 'stage').exists())

    def test_non_test_version_and_existing_output_refused(self):
        for version in ['1.0.0', '0.1-test/../../escape']:
            with self.assertRaisesRegex(ValueError, 'test version'):
                flatpak.package(self.fixture.bundle, self.root / 'output', self.pcsc, self.notice, version)
        with self.assertRaisesRegex(ValueError, 'new output'):
            flatpak.package(self.fixture.bundle, self.root, self.pcsc, self.notice, '0.1-test1')


if __name__ == '__main__':
    unittest.main(verbosity=2)
