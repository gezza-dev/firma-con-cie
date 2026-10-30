#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile
import zlib

from check_windows_distribution import DistributionAudit


class DistributionPrivacy(unittest.TestCase):
    def test_nested_source_jar_exposes_encoded_path_without_changing_bytes(self):
        source = io.BytesIO()
        with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('Source.java', b'// file:///Users/private%20profile/build/Source.java')
        data = source.getvalue()
        before = hashlib.sha256(data).hexdigest()
        audit = DistributionAudit(['/Users/private profile'])
        audit.blob(data, 'source.jar')
        self.assertEqual(audit.findings, ['source.jar!Source.java'])
        self.assertEqual(hashlib.sha256(data).hexdigest(), before)

    def test_utf16_json_in_compressed_notices_is_detected(self):
        data = '{"source":"C:\\\\Users\\\\private-profile\\\\build"}'.encode('utf-16-le')
        audit = DistributionAudit(['C:/Users/private-profile'])
        audit.blob(zlib.compress(data), 'NOTICES.Z')
        self.assertEqual(audit.findings, ['NOTICES.Z!decompressed'])

    def test_author_identity_and_generic_ci_paths_are_preserved(self):
        audit = DistributionAudit(['/Users/private profile', 'C:/Users/private-profile'])
        audit.blob(b'Author: Example Person; Developer ID Application: Example Person; C:/a/repository; /home/runner/work/repo', 'NOTICE.txt')
        self.assertTrue(audit.result()['passed'])

    def test_broken_archive_fails_closed(self):
        audit = DistributionAudit(['/Users/private-profile'])
        audit.blob(b'PK\x03\x04broken', 'library.jar')
        self.assertFalse(audit.result()['passed'])
        self.assertTrue(audit.errors)

    def test_report_contains_only_relative_filenames(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'binary.dll').write_bytes(b'/Users/private-profile/source')
            audit = DistributionAudit(['/Users/private-profile'])
            audit.directory(directory)
            self.assertEqual(audit.result()['findings'], ['binary.dll'])
            self.assertNotIn(str(directory), str(audit.result()))


if __name__ == '__main__':
    unittest.main()
