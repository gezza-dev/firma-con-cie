#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Reject inconsistent architecture bundles before creating or signing output."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("universal_builder", ROOT / "scripts/build-universal-app.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class BundleCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.apps = {arch: self.root / arch / "CIE ID.app" for arch in builder.ARCHITECTURES}
        for app in self.apps.values():
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            (resources / "message.txt").write_text("Shared resource")
        self.output = self.root / "merged.app"

    def assertRejected(self, message):
        before = {arch: builder.inventory(app) for arch, app in self.apps.items()}
        with self.assertRaisesRegex(RuntimeError, message):
            builder.merge(self.apps, self.output)
        self.assertFalse(self.output.exists())
        self.assertEqual(before, {arch: builder.inventory(app) for arch, app in self.apps.items()})

    def test_different_resource(self):
        (self.apps["x86_64"] / "Contents/Resources/message.txt").write_text("Different UI version")
        self.assertRejected("different resources")

    def test_missing_resource(self):
        (self.apps["x86_64"] / "Contents/Resources/message.txt").unlink()
        self.assertRejected("different resources")

    def test_different_symlink_target(self):
        for arch, app in self.apps.items():
            (app / "Contents/Resources/link").symlink_to(arch)
        self.assertRejected("different resources")

    def test_missing_executables(self):
        self.assertRejected("Missing application")

    def test_different_nib_without_matching_source_receipts(self):
        for arch, app in self.apps.items():
            path = app / "Contents/Resources/Base.lproj/Main.storyboardc/Example.nib"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"NIBArchive" + arch.encode())
        self.assertRejected("different resources")


if __name__ == "__main__":
    unittest.main()
