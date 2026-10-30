# SPDX-License-Identifier: BSD-3-Clause
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from check_windows_distribution import DistributionAudit
from windows_file_safety import is_link_or_junction


class FileSafety(unittest.TestCase):
    def test_posix_does_not_call_the_windows_junction_api(self):
        path = Mock()
        path.is_symlink.return_value = False
        path.is_junction.side_effect = AttributeError('unavailable on Python 3.9')
        with patch('windows_file_safety.os.name', 'posix'):
            self.assertFalse(is_link_or_junction(path))
        path.is_junction.assert_not_called()

    def test_old_windows_python_fails_instead_of_disabling_junction_checks(self):
        with patch('windows_file_safety.os.name', 'nt'), patch('windows_file_safety.sys.version_info', (3, 9)):
            with self.assertRaisesRegex(RuntimeError, 'Python 3.12'):
                is_link_or_junction(Mock())

    def test_supported_windows_checks_junctions(self):
        path = Mock()
        path.is_symlink.return_value = False
        path.is_junction.return_value = True
        with patch('windows_file_safety.os.name', 'nt'), patch('windows_file_safety.sys.version_info', (3, 12)):
            self.assertTrue(is_link_or_junction(path))
        path.is_junction.assert_called_once()

    @unittest.skipUnless(os.name == 'nt', 'Real junction requires Windows')
    def test_audit_rejects_real_junction_before_entering_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload, outside = root / 'payload', root / 'outside'
            payload.mkdir()
            outside.mkdir()
            data = b'/Users/private-profile/do-not-read'
            (outside / 'private.bin').write_bytes(data)
            junction = payload / 'junction'
            subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(junction), str(outside)], capture_output=True, check=True)
            try:
                audit = DistributionAudit(['/Users/private-profile'])
                audit.directory(payload)
                self.assertEqual(audit.files, 0)
                self.assertEqual(audit.findings, [])
                self.assertEqual(audit.errors, ['junction: unexpected link'])
                self.assertEqual((outside / 'private.bin').read_bytes(), data)
            finally:
                junction.rmdir()


if __name__ == '__main__':
    unittest.main()
