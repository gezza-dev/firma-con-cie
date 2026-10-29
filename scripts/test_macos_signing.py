#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fail closed before signing when a Developer ID identity is unavailable."""
import unittest
from unittest.mock import patch
from macos_signing import MacCodeSigner


class IdentityValidation(unittest.TestCase):
    def test_development_or_ad_hoc_identity_cannot_claim_developer_id(self):
        digest = 'A' * 40
        available = f'  1) {digest} "Apple Development: Test (TEST123456)"\n'
        for identity in ['-', digest, 'Developer ID Application: Missing (TEST123456)']:
            with self.subTest(identity=identity), \
                    patch('macos_signing.subprocess.check_output', return_value=available), \
                    patch('macos_signing.subprocess.run') as run:
                with self.assertRaises(ValueError):
                    MacCodeSigner(identity, developer_id=True).sign('unused.app')
                run.assert_not_called()

    def test_ambiguous_certificate_name_is_rejected(self):
        name = 'Developer ID Application: Test (TEST123456)'
        available = f'  1) {"A" * 40} "{name}"\n  2) {"B" * 40} "{name}"\n'
        with patch('macos_signing.subprocess.check_output', return_value=available), \
                patch('macos_signing.subprocess.run') as run:
            with self.assertRaises(ValueError):
                MacCodeSigner(name, developer_id=True).sign('unused.app')
            run.assert_not_called()

    def test_development_signing_does_not_require_keychain_discovery(self):
        with patch('macos_signing.subprocess.check_output') as discover:
            MacCodeSigner('-')
            discover.assert_not_called()


if __name__ == '__main__':
    unittest.main()
