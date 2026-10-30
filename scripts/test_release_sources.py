#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from prepare_release_sources import checked_file, member_name, write_archive


class ReleaseSources(unittest.TestCase):
    def test_missing_or_modified_archive_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'source.tar.gz'
            with self.assertRaises(ValueError):
                checked_file(path, '0'*64)
            path.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                checked_file(path, hashlib.sha256(b'original').hexdigest())

    def test_member_names_cannot_escape_the_archive(self):
        for name in ['', '..', '../source', '/source', 'a/b', 'a\\b']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                member_name(name)

    def test_roundtrip_has_exact_hashes_and_no_local_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); path = root/'source.tar.gz'
            path.write_bytes(b'original source archive')
            entries = {'native/source.tar.gz': (path, 'https://example.org/source.tar.gz')}
            first = root/'one.zip'; second = root/'two.zip'
            one = write_archive(first, entries, {'README.txt': b'Rebuild instructions'})
            two = write_archive(second, entries, {'README.txt': b'Rebuild instructions'})
            self.assertEqual(one['sha256'], two['sha256'])
            with zipfile.ZipFile(first) as archive:
                prefix = 'firma-con-cie-dependency-sources/'
                manifest = json.loads(archive.read(prefix+'SOURCE-SHA256.json'))
                self.assertEqual(archive.read(prefix+'native/source.tar.gz'), path.read_bytes())
                self.assertEqual(manifest['native/source.tar.gz']['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertNotIn(temporary, json.dumps(manifest))

    def test_existing_release_material_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'existing.zip'; path.write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                write_archive(path, {}, {})
            self.assertEqual(path.read_bytes(), b'keep')


if __name__ == '__main__':
    unittest.main()
