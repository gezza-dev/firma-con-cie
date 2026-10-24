#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Regression: a Linux host must never select a macOS private JVM."""
import unittest
from ltv_runtime import runtime_architecture


class RuntimeArchitectureTests(unittest.TestCase):
    def test_linux_and_architecture_aliases(self):
        for machine in ('x86_64', 'AMD64', 'x64'):
            self.assertEqual(runtime_architecture('Linux', machine), 'linux-x86_64')
        for machine in ('aarch64', 'arm64'):
            self.assertEqual(runtime_architecture('Linux', machine), 'linux-arm64')

    def test_existing_platforms(self):
        self.assertEqual(runtime_architecture('Windows', 'AMD64'), 'windows-x86_64')
        self.assertEqual(runtime_architecture('Darwin', 'arm64'), 'macos-arm64')
        self.assertEqual(runtime_architecture('Darwin', 'x86_64'), 'macos-x86_64')

    def test_unsupported_architecture_has_no_foreign_fallback(self):
        for system, machine in [('Linux', 'armv7l'), ('Windows', 'arm64'), ('FreeBSD', 'x86_64')]:
            with self.assertRaises(ValueError):
                runtime_architecture(system, machine)


if __name__ == '__main__':
    unittest.main()
