#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Synthetic public DER and isolated test cache, never production pairing data."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
BINARY=Path(sys.argv.pop(1)).resolve()
class PublicStore(unittest.TestCase):
    def setUp(self):
        previous=os.umask(0o077);self.addCleanup(os.umask,previous)
        self.temp=tempfile.TemporaryDirectory(prefix='cie-public-companion-'); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name); self.cache=self.root/'cache'
        self.cache.mkdir(mode=0o700)
        self.env=dict(os.environ,CIE_PAIRING_TEST_CACHE=str(self.cache),HOME=str(self.root))
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-subj','/CN=Synthetic companion test',
            '-keyout',str(self.root/'temporary.key'),'-outform','DER','-out',str(self.root/'cert.der'),'-days','1'],
            check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        self.der=(self.root/'cert.der').read_bytes()
    def call(self,op,der=None,identity='SYNTHETIC'):
        return subprocess.run([str(BINARY),op,identity],input=self.der if der is None else der,
            env=self.env,capture_output=True).returncode
    def snapshot(self):
        return {str(p.relative_to(self.cache)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in self.cache.rglob('*') if p.is_file()}
    def test_validate_and_inspect_do_not_create_cache(self):
        self.assertEqual(self.call('validate'),0)
        self.assertEqual(self.call('check-web'),3)
        self.assertEqual(self.call('check-snap'),3)
        self.assertEqual(list(self.cache.iterdir()),[])
    def test_public_web_roundtrip_preserves_private_namespace(self):
        self.assertEqual(self.call('publish-web'),0)
        marker=self.cache/'cache-v3'; marker=marker/'synthetic.card';marker.write_bytes(b'synthetic secret, never transferred')
        before=self.snapshot()
        self.assertEqual(self.call('publish-web'),0)
        self.assertEqual(self.call('check-web'),0)
        self.assertEqual(before['cache-v3/synthetic.card'],self.snapshot()['cache-v3/synthetic.card'])
        self.assertEqual(self.call('check-snap'),3)
        self.assertFalse(any(p.name.endswith('.tmp') for p in self.cache.rglob('*')))
    def test_snap_public_data_is_separate_and_does_not_create_firefox_installation(self):
        self.assertNotEqual(self.call('publish-snap'),0)
        self.assertEqual(list(self.cache.iterdir()),[])
        common=self.cache/'snap/firefox/common';common.mkdir(parents=True)
        self.assertEqual(self.call('publish-snap'),0)
        self.assertEqual(self.call('check-snap'),0)
        self.assertEqual(self.call('check-web'),3)
        certs=list(common.rglob('*.der'));self.assertEqual(len(certs),1)
        self.assertEqual(certs[0].read_bytes(),self.der)
        self.assertEqual(certs[0].stat().st_mode & 0o777,0o600)
    def test_invalid_der_trailing_bytes_oversize_id_and_operation_leave_no_files(self):
        for data in [b'',b'not a certificate',self.der+b'extra',b'x'*8193]:
            self.assertEqual(self.call('publish-web',data),2)
        self.assertEqual(self.call('publish-web',identity='../unsafe'),4)
        self.assertEqual(self.call('shell'),2)
        self.assertEqual(list(self.cache.iterdir()),[])
if __name__=='__main__':unittest.main(verbosity=2)
