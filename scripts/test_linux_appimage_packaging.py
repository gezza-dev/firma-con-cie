#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Packaging ABI/PCSC boundaries; synthetic fixtures, no CIE operations."""
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import package_linux_appimage as image
class Boundaries(unittest.TestCase):
    def test_host_libraries_are_always_external(self):
        for name in ['libpcsclite.so.1','libc.so.6','ld-linux-x86-64.so.2','libm.so.6','libstdc++.so.6','libgcc_s.so.1','libGL.so.1','libEGL.so.1','libdrm.so.2','libgbm.so.1','libudev.so.1','libwayland-client.so.0','libwayland-server.so.0','libwayland-cursor.so.0','libwayland-egl.so.1']:
            self.assertTrue(image.EXTERNAL.fullmatch(name),name)
        for name in ['libgtk-3.so.0','libglib-2.0.so.0','libnss3.so','libcie_linux_pkcs11.so','libcrypto.so.3']:
            self.assertFalse(image.EXTERNAL.fullmatch(name),name)
    def test_numerical_abi_comparison_and_unsupported_floor(self):
        with patch.object(image,'run',return_value=SimpleNamespace(stdout='Name: GLIBC_2.9\nName: GLIBC_2.35\nName: GLIBCXX_3.4.29')):
            self.assertEqual(image.maximum_versions(Path('synthetic')),dict(GLIBC='2.35',GLIBCXX='3.4.29'))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);file=root/'synthetic.so';file.touch()
            with patch.object(image,'elf_files',return_value=[file]),patch.object(image,'maximum_versions',return_value=dict(GLIBC='2.38',GLIBCXX=None)):
                with self.assertRaisesRegex(ValueError,'newer than Ubuntu'):image.check_abi(root)
            file=root/'libpcsclite.so.1'
            with patch.object(image,'elf_files',return_value=[file]),patch.object(image,'maximum_versions',return_value=dict(GLIBC='2.17',GLIBCXX=None)):
                with self.assertRaisesRegex(ValueError,'must not be bundled'):image.check_abi(root)
    def test_non_numeric_new_glibc_feature_is_rejected(self):
        with patch.object(image,'run',return_value=SimpleNamespace(stdout='GLIBC_ABI_DT_RELR')):
            with self.assertRaisesRegex(ValueError,'newer glibc ABI'):image.maximum_versions(Path('synthetic'))
    def test_runtime_checksum_is_pinned_and_versions_require_release(self):
        import json
        lock=json.loads(image.LOCK.read_text());self.assertEqual(len(lock['sha256']),64)
        for version in ['1.0','01.0.0','1.0.0-test20261025.1','1.0.0/unsafe']:
            with self.assertRaisesRegex(ValueError,'release version'):image.package(Path('/nonexistent-bundle'),Path('/new-output'),Path('/nonexistent-runtime'),version)
if __name__=='__main__':unittest.main(verbosity=2)
