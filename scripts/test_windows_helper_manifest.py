#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Manifest regressions for both Windows CPUs; no Windows execution required."""
from pathlib import Path
import struct
import tempfile
import unittest

from windows_helper_manifest import check_helper_manifest


def helper_pe(path, architecture='arm64', manifest=None):
    """A minimal PE32+ resource fixture, never executable."""
    if manifest is None:
        manifest = (Path(__file__).resolve().parents[1] /
                    'native/platform/windows/web/setup.manifest').read_bytes()
    data = bytearray(1024 + len(manifest))
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 64)
    data[64:68] = b'PE\0\0'
    struct.pack_into('<HH', data, 68, {'x64': 0x8664, 'arm64': 0xAA64}[architecture], 1)
    struct.pack_into('<H', data, 84, 240)
    struct.pack_into('<H', data, 88, 0x20b)
    struct.pack_into('<I', data, 196, 16)
    struct.pack_into('<II', data, 216, 0x1000, len(data) - 512)
    # One .rsrc section, three directories and one data entry.
    data[328:336] = b'.rsrc\0\0\0'
    struct.pack_into('<IIII', data, 336, len(data) - 512, 0x1000, len(data) - 512, 512)
    for offset, identifier, target in ((0, 24, 24), (24, 1, 48), (48, 1033, 72)):
        struct.pack_into('<H', data, 512 + offset + 14, 1)
        struct.pack_into('<II', data, 512 + offset + 16, identifier,
                         target | (0x80000000 if offset != 48 else 0))
    struct.pack_into('<IIII', data, 584, 0x1200, len(manifest), 65001, 0)
    data[1024:] = manifest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


class HelperManifest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'CIE-Web-Setup.exe'

    def test_both_cpus_embed_as_invoker(self):
        for architecture in ('arm64', 'x64'):
            with self.subTest(architecture=architecture):
                helper_pe(self.path, architecture)
                self.assertEqual(check_helper_manifest(self.path),
                                 {'executionLevel': 'asInvoker', 'uiAccess': False, 'languages': 1})

    def test_elevation_and_ui_access_are_rejected(self):
        for level, ui in (('requireAdministrator', 'false'), ('highestAvailable', 'false'),
                          ('asInvoker', 'true'), ('asInvoker', '')):
            xml = (Path(__file__).resolve().parents[1] /
                   'native/platform/windows/web/setup.manifest').read_bytes()
            xml = xml.replace(b'level="asInvoker"', f'level="{level}"'.encode())
            xml = xml.replace(b'uiAccess="false"', f'uiAccess="{ui}"'.encode())
            helper_pe(self.path, manifest=xml)
            with self.assertRaisesRegex(ValueError, 'asInvoker'):
                check_helper_manifest(self.path)

    def test_missing_manifest_or_wrong_resource_id_is_rejected(self):
        for offset, value in ((216, 0), (528, 23), (552, 2)):
            helper_pe(self.path)
            data = bytearray(self.path.read_bytes())
            struct.pack_into('<I', data, offset, value)
            self.path.write_bytes(data)
            with self.assertRaises(ValueError):
                check_helper_manifest(self.path)

    def test_truncated_or_unmapped_resource_is_rejected(self):
        helper_pe(self.path)
        original = self.path.read_bytes()
        for size in (0, 63, 90, 340, 583, len(original) - 1):
            self.path.write_bytes(original[:size])
            with self.assertRaises(ValueError):
                check_helper_manifest(self.path)
        data = bytearray(original)
        struct.pack_into('<I', data, 584, 0x90000000)
        self.path.write_bytes(data)
        with self.assertRaises(ValueError):
            check_helper_manifest(self.path)

    def test_invalid_xml_or_missing_execution_level_is_rejected(self):
        for xml in (b'<assembly', b'<assembly/>', b'<requestedExecutionLevel level="asInvoker"/>',
                    b'<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><requestedExecutionLevel xmlns="urn:schemas-microsoft-com:asm.v3" level="asInvoker" uiAccess="false"/></assembly>'):
            helper_pe(self.path, manifest=xml)
            with self.assertRaises(ValueError):
                check_helper_manifest(self.path)


if __name__ == '__main__':
    unittest.main()
