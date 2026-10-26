#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check portable defaults and isolation of machine-specific build settings."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from build_paths import build_root


class BuildPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / 'project'
        self.project.mkdir()
        self.config = self.project / 'local-build.json'

    def configure(self, value):
        self.config.write_text(json.dumps(value), encoding='utf-8')

    def test_missing_configuration_uses_portable_default_without_writing(self):
        home = Path(self.temporary.name) / 'home'
        with patch.object(Path, 'home', return_value=home):
            self.assertEqual(build_root(self.project), home / 'Developer/Builds/firma-con-cie')
        self.assertFalse(home.exists())
        self.assertFalse(self.config.exists())

    def test_local_path_with_spaces_is_preserved_without_creating_output(self):
        root = Path(self.temporary.name) / 'Private build output'
        self.configure({'build_root': str(root)})
        self.assertEqual(build_root(self.project), root)
        self.assertFalse(root.exists())

    def test_tilde_is_expanded_for_the_current_machine(self):
        self.configure({'build_root': '~/private output'})
        self.assertEqual(build_root(self.project), Path.home() / 'private output')

    def test_configuration_belongs_to_the_specified_checkout(self):
        self.configure({'build_root': '~/first output'})
        other = Path(self.temporary.name) / 'other checkout'
        other.mkdir()
        self.assertEqual(build_root(self.project), Path.home() / 'first output')
        self.assertEqual(build_root(other), Path.home() / 'Developer/Builds/firma-con-cie')

    def test_invalid_or_unexpected_configuration_is_rejected(self):
        for value in [None, [], {}, {'build_root': ''}, {'build_root': 1},
                      {'build_root': 'relative/path'}, {'build_root': '$HOME/output'},
                      {'build_root': '~/output', 'unexpected': 'value'}]:
            with self.subTest(value=value):
                self.configure(value)
                with self.assertRaises(ValueError):
                    build_root(self.project)

    def test_invalid_json_is_not_silently_ignored(self):
        self.config.write_text('{', encoding='utf-8')
        with self.assertRaises(ValueError):
            build_root(self.project)


if __name__ == '__main__':
    unittest.main()
