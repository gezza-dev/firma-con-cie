#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Cross-platform packaging names and checked-in branding; no installations."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import unittest

import linux_package_common as linux
from product_identity import (DISPLAY_NAME, PACKAGE_NAME, ARTIFACT_STEM,
                              windows_installer_name, macos_image_name)

ROOT = Path(__file__).resolve().parents[1]


class ProductIdentity(unittest.TestCase):
    def test_linux_manager_identity_matches_distributed_filename_stem(self):
        self.assertEqual(PACKAGE_NAME, 'firma-con-cie')
        self.assertEqual(linux.PACKAGE, ARTIFACT_STEM)
        self.assertEqual(linux.PACKAGE, PACKAGE_NAME)
        self.assertEqual(str(linux.PREFIX), 'opt/firma-con-cie')

    def test_windows_and_macos_default_artifact_names(self):
        self.assertEqual(windows_installer_name('1.0.0') + '.exe',
                         'firma-con-cie_1.0.0_windows_x64_setup.exe')
        self.assertEqual(macos_image_name('1.0.0'), 'firma-con-cie_1.0.0_universal.dmg')

    def test_bundle_version_cannot_inject_an_output_path(self):
        for value in ['../1.0.0', '1.0.0/unsafe', 'v1.0.0', '1.0.0\nother', '']:
            for function in [windows_installer_name, macos_image_name]:
                with self.subTest(value=value, function=function.__name__), self.assertRaises(ValueError):
                    function(value)

    def test_deprecated_desktop_brand_absent_from_current_sources(self):
        try:
            paths = subprocess.check_output(
                ['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=ROOT,
                stderr=subprocess.DEVNULL).decode().split('\0')
        except subprocess.CalledProcessError:
            # Source ZIPs and isolated build exports intentionally omit .git.
            paths = []
            ignored = {'.git', '.build', '.dart_tool', 'build', 'dist', 'reports',
                       'output', '__pycache__', '.pub-cache', 'ephemeral', 'Pods',
                       '.symlinks', '.plugin_symlinks', 'runtime'}
            for directory, dirs, files in os.walk(ROOT):
                dirs[:] = [name for name in dirs if name not in ignored]
                paths.extend((Path(directory)/name).relative_to(ROOT).as_posix() for name in files)
        pattern = re.compile(rb'cie[-_ ]id[-_ ]desktop', re.I)
        findings = [name for name in set(paths) if name and (ROOT/name).is_file()
                    and pattern.search((ROOT/name).read_bytes())]
        self.assertEqual(findings, [])

    def test_linux_and_windows_compile_targets_and_windows_metadata(self):
        for system in ['linux', 'windows']:
            source = (ROOT/system/'CMakeLists.txt').read_text()
            self.assertIn('set(BINARY_NAME "firma-con-cie")', source)
            self.assertIn('set(APP_EXECUTABLE_NAME "${BINARY_NAME}")', source)
        resource = (ROOT/'windows/runner/Runner.rc').read_text()
        for field, value in [('InternalName', PACKAGE_NAME), ('ProductName', DISPLAY_NAME),
                             ('OriginalFilename', DISPLAY_NAME + '.exe')]:
            self.assertRegex(resource, r'VALUE "'+field+r'", "'+re.escape(value)+r'"')

    def test_windows_installer_source_uses_current_product(self):
        source = (ROOT/'packaging/windows/firma-con-cie.iss').read_text()
        self.assertIn('AppName=' + DISPLAY_NAME, source)
        self.assertIn('CloseApplicationsFilter=' + DISPLAY_NAME + '.exe\n', source)
        packager = (ROOT/'scripts/package_windows_installer.py').read_text()
        self.assertIn('windows_installer_name(version)', packager)
        self.assertIn('packaging/windows/firma-con-cie.iss', packager)

    def test_macos_product_and_version_derived_dmg_name(self):
        source = (ROOT/'macos/Runner/Configs/AppInfo.xcconfig').read_text()
        self.assertIn('PRODUCT_NAME = ' + DISPLAY_NAME, source)
        source = (ROOT/'scripts/package_macos_dmg.py').read_text()
        self.assertIn("['CFBundleShortVersionString']", source)
        self.assertIn('macos_image_name(version)', source)

    def test_icon_paths_and_hashes_match_all_platform_assets(self):
        manifest = json.loads((ROOT/'assets/branding/manifest.json').read_text())
        self.assertIn('assets/branding/windows/firma-con-cie.ico', manifest)
        self.assertIn('assets/branding/macos/firma-con-cie.icns', manifest)
        for name, digest in manifest.items():
            with self.subTest(name=name):
                self.assertTrue((ROOT/name).is_file())
                self.assertEqual(hashlib.sha256((ROOT/name).read_bytes()).hexdigest(), digest)


if __name__ == '__main__':
    unittest.main(verbosity=2)
