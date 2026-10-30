#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify path redaction in compiler output and serialized build metadata."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from build_privacy import compiler_path_flags, local_path_markers, check_public_paths


class BuildPrivacyTests(unittest.TestCase):
    def test_neutral_build_flags_do_not_add_an_unrelated_private_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            flags = compiler_path_flags(tmp)
            self.assertNotIn(str(Path.home()), ' '.join(flags))

    def test_generic_ci_account_is_not_treated_as_a_personal_identity(self):
        with patch('build_privacy.Path.home', return_value=Path('/home/runner')), \
                patch.dict('os.environ', {'GITHUB_ACTIONS': 'true'}):
            self.assertFalse(local_path_markers(b'/home/runner/work/upstream/library.cpp'))
            self.assertTrue(local_path_markers(b'/home/runner/source', ['/home/runner']))

    def test_encoded_uri_json_and_utf16_paths_are_detected_without_matching_identity(self):
        roots = ['/Users/example profile', 'C:\\Users\\example']
        for value in [b'file:///Users/example%20profile/source.dart',
                      b'{"path":"C:\\\\Users\\\\example\\\\build"}',
                      b'{"path":"C:\\\\\\\\Users\\\\\\\\example\\\\\\\\build"}',
                      'C:\\Users\\example\\build'.encode('utf-16-le')]:
            with self.subTest(value=value):
                self.assertTrue(local_path_markers(value, roots))
        self.assertFalse(local_path_markers(b'Author: Example Person; Developer ID: Example Person', roots))

    def test_compiled_file_macro_does_not_expose_source_directory_with_spaces(self):
        compiler = shutil.which('clang') or shutil.which('gcc')
        if compiler is None:
            self.skipTest('C compiler unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'private profile with spaces'
            source.mkdir()
            unit = source/'probe.c'
            unit.write_text('#include <stdio.h>\nint main(void) { puts(__FILE__); }\n')
            binary = Path(tmp)/'probe'
            subprocess.run([compiler, *compiler_path_flags(source), str(unit), '-o', str(binary)], check=True)
            result = subprocess.check_output([str(binary)], text=True).strip()
            self.assertEqual(result, '/src/firma-con-cie/probe.c')
            self.assertNotIn(str(source).encode(), binary.read_bytes())

    def test_release_gate_reads_file_contents_and_preserves_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            file = directory/'metadata.json'
            original = b'{"path":"/Users/example/build"}'
            file.write_bytes(original)
            with self.assertRaisesRegex(ValueError, 'metadata.json'):
                check_public_paths(directory, ['/Users/example'])
            self.assertEqual(file.read_bytes(), original)
            file.write_bytes(b'{"path":"/build/firma-con-cie"}')
            self.assertEqual(check_public_paths(directory, ['/Users/example'])['filesChecked'], 1)


if __name__ == '__main__':
    unittest.main()
