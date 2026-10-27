#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check portable defaults and isolation of machine-specific build settings."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from build_paths import build_root, macos_paths


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

    def test_default_macos_layout_is_backward_compatible(self):
        root = build_root(self.project)
        self.assertEqual(macos_paths(self.project), dict(
            destination=root / 'firma-con-cie', workspace=root / 'workspace-macos',
            dmg=root / 'Firma con CIE.dmg'))

    def test_relative_macos_output_colocates_artifacts_without_moving_workspace(self):
        root = Path(self.temporary.name) / 'Private build root'
        self.configure({'build_root': str(root), 'macos_output': 'Mac output'})
        paths = macos_paths(self.project)
        self.assertEqual(paths['destination'], root / 'Mac output')
        self.assertEqual(paths['dmg'], paths['destination'] / 'Firma con CIE.dmg')
        self.assertEqual(paths['workspace'], root / 'workspace-macos')
        self.assertFalse(root.exists())

    def test_absolute_macos_output_and_invalid_values(self):
        output = Path(self.temporary.name) / 'Separate artifacts'
        self.configure({'build_root': '~/build-root', 'macos_output': str(output)})
        self.assertEqual(macos_paths(self.project)['destination'], output)
        self.assertEqual(macos_paths(self.project)['dmg'], output / 'Firma con CIE.dmg')
        for value in ['', None, 1, []]:
            self.configure({'build_root': '~/build-root', 'macos_output': value})
            with self.subTest(value=value), self.assertRaises(ValueError):
                macos_paths(self.project)


if __name__ == '__main__':
    unittest.main()
