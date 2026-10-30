#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check staged output and legacy cross-build paths without executing an app."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from package_windows_installer import prepare
from windows_build_privacy import msvc_path_options, neutral_directory


class WindowsPackagingPrivacy(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.release = self.root / 'input'
        for name in ('Firma con CIE.exe', 'flutter_windows.dll', 'pdfium.dll', 'data/app.so',
                     'web-component/CIE-Web-Setup.exe', 'cie_native/ltv/cie-ltv-worker.jar', 'cie_native/cie_card_observer.exe'):
            path = self.release / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'synthetic bytes')
        self.binary = self.release / 'Firma con CIE.exe'
        native = self.release / 'cie_native'
        sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
        (native / 'backend-manifest.json').write_text(json.dumps({'files': {p.relative_to(native).as_posix(): sha(p) for p in native.rglob('*') if p.is_file()}}))
        (self.release / 'web-component/payload-manifest.json').write_text(json.dumps({'files': {}, 'version': hashlib.sha256(b'{}').hexdigest()}))
        self.redist = self.root / 'fake-redist.exe'
        self.redist.write_bytes(b'not executed')

    def package(self, roots):
        return prepare(self.release, self.root / 'output', '1.0.0', self.redist, private_path_roots=roots)

    def test_legacy_mac_paths_in_a_windows_binary_are_rejected(self):
        self.binary.write_bytes(b'OpenSSL configuration /Users/private-profile/build/ssl')
        with self.assertRaisesRegex(ValueError, 'Firma con CIE.exe'):
            self.package([Path('/Users/private-profile')])

    def test_utf16_and_uri_json_paths_are_rejected(self):
        for value in ('C:\\Users\\private-profile\\source.cpp'.encode('utf-16-le'),
                      b'{"path":"file:///C:/Users/private-profile/source.dart"}'):
            self.binary.write_bytes(value)
            with self.assertRaisesRegex(ValueError, 'Firma con CIE.exe'):
                self.package([Path('C:/Users/private-profile')])
            # Each staging attempt has a fresh, independently scoped output.
            self.root = self.root / 'next'
            self.root.mkdir()

    def test_unused_build_asset_map_is_excluded_and_runtime_map_preserved(self):
        development = self.release / 'native_assets.json'
        development.write_bytes(b'{"path":"C:\\\\Users\\\\private-profile\\\\pdfium.dll"}')
        runtime = self.release / 'data/flutter_assets/NativeAssetsManifest.json'
        runtime.parent.mkdir(parents=True)
        runtime.write_bytes(b'{"format-version":[1,0,0],"native-assets":{"windows_x64":{"package:pdfium_dart/libpdfium":["absolute","pdfium.dll"]}}}')
        _, _, manifest = self.package([Path('C:/Users/private-profile')])
        staged = self.root / 'output/Release'
        self.assertFalse((staged / 'native_assets.json').exists())
        self.assertEqual((staged / 'data/flutter_assets/NativeAssetsManifest.json').read_bytes(), runtime.read_bytes())
        self.assertNotIn('private-profile', json.dumps(manifest))
        self.assertEqual(manifest['buildPrivacy']['additionalRootsChecked'], 1)

    def test_author_and_signer_names_are_not_profile_paths(self):
        self.binary.write_bytes(b'Author: Example Person; Developer ID Application: Example Person')
        self.package([Path('/Users/private-profile')])
        self.assertEqual((self.root / 'output/Release/Firma con CIE.exe').read_bytes(), self.binary.read_bytes())

    def test_msvc_options_require_deterministic_and_have_no_unrelated_home(self):
        options = msvc_path_options('/build/source', '/build/cache', '/build/flutter')
        self.assertEqual(options[0], '/experimental:deterministic')
        self.assertEqual(sum(o.startswith('/pathmap:') for o in options), 3)
        self.assertNotIn(str(Path.home()), ' '.join(options))

    def test_neutral_directory_rejects_actual_profile_and_accepts_outside(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            neutral_directory(Path.home())


if __name__ == '__main__':
    unittest.main()
