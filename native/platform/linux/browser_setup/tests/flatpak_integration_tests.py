#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Real guarded NSS + public-cache tool; every profile/certificate is synthetic."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import flatpak_helper as helper
import flatpak_helper_tests as fixtures
NATIVE=Path(sys.argv.pop(1)).resolve();PUBLISHER=Path(sys.argv.pop(1)).resolve()
class Integration(unittest.TestCase):
    def setUp(self):
        self.fixture=fixtures.Policy('test_readonly_health_inspection_plan_no_subprocess_or_changes');self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
        f=self.fixture
        for name in helper.LIBRARIES:shutil.copy2(NATIVE/name,f.runtime/name)
        shutil.copy2(NATIVE/'browser_setup/libcie_browser_setup_guard.so',f.runtime/'browser_setup/libcie_browser_setup_guard.so')
        shutil.copy2(PUBLISHER,f.runtime/'cie_browser_public_certificate');f.refresh_manifest()
        f.service.run=subprocess.run;f.service.modutil='/usr/bin/modutil'
        f.companion.chrome.run=subprocess.run;f.companion.chrome.modutil='/usr/bin/modutil'
        self.cache=f.home
        self.der=f.home/'synthetic.der'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-subj','/CN=Software companion test',
            '-keyout',str(f.home/'synthetic.key'),'-outform','DER','-out',str(self.der),'-days','1'],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
        f.certificates={'SYNTHETIC':self.der.read_bytes().hex()}
        def guarded(command,**kwargs):
            self.assertEqual(set(kwargs['env']),{'PATH','LANG','LD_PRELOAD'})
            self.assertEqual(command[0],str(f.runtime/'cie_browser_public_certificate'))
            kwargs['env']['CIE_PAIRING_TEST_CACHE']=str(self.cache)
            return subprocess.run(command,**kwargs)
        f.companion.public=helper.PublicCertificates(f.runtime,run=guarded)
    def test_real_nss_publication_for_firefox_snap_and_chrome_without_card(self):
        f=self.fixture;f.profile('snap')
        db=f.companion.chrome.database;db.mkdir(parents=True,mode=0o700)
        firefox=f.service.profiles()[0]['path']
        for name in ['cert9.db','key4.db','pkcs11.txt']:shutil.copy2(firefox/name,db/name)
        # All Snap permission queries are synthetic, never the host snap command.
        f.service.permission=lambda:'disconnected'
        for target in ['firefox','snap','chrome']:
            kind='chrome' if target=='chrome' else 'firefox'
            identity='chrome-desktop' if target=='chrome' else f.identity(target)
            path=db if target=='chrome' else next(p['path'] for p in f.service.profiles() if p['target']==target)
            before={n:(path/n).read_bytes() for n in ['cert9.db','key4.db']}
            plan=f.request(kind+'.plan',profile=identity)
            result=f.request(kind+'.apply',profile=identity,fingerprint=plan['fingerprint'])
            self.assertTrue(result['ok']);self.assertTrue(result['publicDataPrepared'])
            self.assertEqual(before,{n:(path/n).read_bytes() for n in before})
            self.assertTrue(f.companion.public.ready(target,f.certificates))
            self.assertTrue(f.request(kind+'.plan',profile=identity)['alreadyConfigured'])
        self.assertFalse(list(self.cache.rglob('*.card')))
        snap,=(self.cache/'snap/firefox/common/cie-id-web-v1').glob('*.der')
        self.assertEqual(snap.read_bytes(),self.der.read_bytes())
if __name__=='__main__':unittest.main(verbosity=2)
