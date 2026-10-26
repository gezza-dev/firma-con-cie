#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Persistent module, read-only discovery and source disappearance: fixtures only."""
import json
import os
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import appimage_setup as image
import setup_tests as fixtures
class Persistence(fixtures.Fixture):
    def setUp(self):
        super().setUp()
        self.service=image.AppImageFirefox(self.home,self.runtime,proc=self.proc,run=self.run_fake)
        self.service.modutil=str(self.runtime/'fake-modutil')
        self.profile()
    def apply(self,plan=None):
        plan=plan or self.service.plan(self.identity())
        with patch('os.geteuid',return_value=1000):return self.service.apply(self.identity(),plan['fingerprint'])
    def test_discovery_and_plan_do_not_install_anything(self):
        before=self.snapshot(self.home)
        self.assertEqual(self.service.inspect()['profiles'][0]['state'],'needs_setup')
        plan=self.service.plan(self.identity());self.assertFalse(plan['alreadyConfigured'])
        self.assertTrue(Path(plan['library']).is_relative_to(self.home/'.local/share/firma-con-cie/pkcs11/v1'))
        self.assertEqual(before,self.snapshot(self.home));self.assertFalse(self.commands)
    def test_apply_keeps_browser_module_after_source_appimage_is_removed(self):
        profile=self.service.profiles()[0]['path'];foreign=(profile/'pkcs11.txt').read_bytes()
        before={n:(profile/n).read_bytes() for n in ['cert9.db','key4.db']}
        plan=self.service.plan(self.identity());self.apply(plan)
        generation,hashes=self.service.generation();self.service.verify_persistent(generation,hashes)
        self.assertTrue(self.service.plan(self.identity())['alreadyConfigured'])
        self.assertIn(str(generation/image.LIBRARIES[0]),(profile/'pkcs11.txt').read_text())
        self.assertTrue((profile/'pkcs11.txt').read_bytes().startswith(foreign))
        self.assertEqual(before,{n:(profile/n).read_bytes() for n in before})
        shutil.rmtree(self.runtime)
        self.assertTrue((generation/image.LIBRARIES[0]).is_file())
        self.assertNotIn(str(self.runtime),(profile/'pkcs11.txt').read_text())
        self.assertFalse(any(generation.parent.glob('.cie-module-*')))
    def test_appimage_relocation_and_repeated_setup_keep_same_generation(self):
        self.apply();old=self.service.plan(self.identity())['library'];count=len(self.commands)
        moved=self.runtime.with_name('new AppImage mount');self.runtime.rename(moved)
        self.service.runtime=moved;self.service.modutil=str(moved/'fake-modutil')
        plan=self.service.plan(self.identity());self.assertTrue(plan['alreadyConfigured']);self.assertEqual(plan['library'],old)
        self.apply(plan);self.assertEqual(len(self.commands),count)
    def test_stale_plan_running_browser_and_symlink_refused_before_install(self):
        plan=self.service.plan(self.identity());profile=self.service.profiles()[0]['path']
        with (profile/'pkcs11.txt').open('a') as f:f.write('# changed\n')
        with self.assertRaisesRegex(image.SetupError,'plan_changed'):self.apply(plan)
        self.assertFalse(self.service.module_base().exists())
        process=self.proc/'42';process.mkdir();(process/'comm').write_text('firefox\n')
        with self.assertRaisesRegex(image.SetupError,'browser_running'):self.apply()
        shutil.rmtree(process)
        target=self.home/'outside';target.mkdir();base=self.home/'.local';base.symlink_to(target,target_is_directory=True)
        self.apply()
        self.assertFalse(list(target.iterdir()))
        self.assertTrue(self.service.module_base().is_relative_to(self.home/'.firma-con-cie'))
    def test_shared_data_directory_uses_private_home_fallback_without_chmod(self):
        data=self.home/'.local/share';data.mkdir(parents=True);data.chmod(0o775)
        self.apply();directory,_=self.service.generation()
        self.assertTrue(directory.is_relative_to(self.home/'.firma-con-cie/pkcs11/v1'))
        self.assertEqual(data.stat().st_mode & 0o777,0o775)
        self.assertFalse((data/'firma-con-cie').exists())
    def test_existing_native_registration_is_preserved_byte_for_byte(self):
        native=self.home/'opt/firma-con-cie/cie_native';shutil.copytree(self.runtime,native)
        self.service.native_runtime=native;profile=self.service.profiles()[0]['path']
        with (profile/'pkcs11.txt').open('a') as f:f.write(f'library={native/image.LIBRARIES[0]}\nname={image.NAME}\n\n')
        before=(profile/'pkcs11.txt').read_bytes();plan=self.service.plan(self.identity())
        self.assertTrue(plan['alreadyConfigured']);self.apply(plan)
        self.assertEqual(before,(profile/'pkcs11.txt').read_bytes());self.assertFalse(self.commands)
        self.assertFalse(self.service.module_base().exists())
    def test_updated_provider_uses_new_generation_and_retains_previous(self):
        self.apply();old=self.service.generation()[0]
        (self.runtime/image.LIBRARIES[0]).write_bytes(b'updated synthetic provider');self.refresh_manifest()
        plan=self.service.plan(self.identity());self.assertFalse(plan['alreadyConfigured']);self.apply(plan)
        new=self.service.generation()[0];self.assertNotEqual(old,new);self.assertTrue(old.is_dir());self.assertTrue(new.is_dir())
    def test_corrupt_generation_and_external_xdg_do_not_escape_policy(self):
        self.apply();directory,_=self.service.generation()
        (directory/image.LIBRARIES[1]).write_bytes(b'tampered')
        with self.assertRaisesRegex(image.SetupError,'module_conflict'):self.service.plan(self.identity())
        with patch.dict(os.environ,XDG_DATA_HOME='/tmp/other-user-data'):
            self.assertTrue(self.service.module_base().is_relative_to(self.home))
    def test_snap_uses_original_snap_generation(self):
        self.profile('snap');identity=self.identity('snap');plan=self.service.plan(identity)
        self.assertTrue(Path(plan['library']).is_relative_to(self.home/'snap/firefox/common/firma-con-cie-module-v1'))
        with patch('os.geteuid',return_value=1000):self.service.apply(identity,plan['fingerprint'])
        self.assertTrue(Path(plan['library']).is_file());self.assertFalse(self.service.module_base().exists())
    def test_chrome_uses_same_persistent_policy(self):
        from chrome_setup_tests import Fixture as ChromeFixture
        fixture=ChromeFixture('runTest');fixture.setUp();self.addCleanup(fixture.doCleanups)
        (fixture.runtime/'browser_setup/chrome_setup.py').write_bytes((Path(image.__file__).parent/'chrome_setup.py').read_bytes());fixture.refresh_manifest()
        fixture.service=image.AppImageChrome(fixture.home,fixture.runtime,proc=fixture.proc,run=fixture.run_fake,chrome_paths=())
        fixture.service.modutil=str(fixture.runtime/'fake-modutil');plan=fixture.service.plan()
        with patch('os.geteuid',return_value=1000):fixture.service.apply('chrome-desktop',plan['fingerprint'])
        self.assertTrue(fixture.service.plan()['alreadyConfigured'])
        self.assertTrue(Path(plan['library']).is_relative_to(fixture.home))
class SnapInteroperability(fixtures.Fixture):
    def services(self):
        self.profile('snap')
        native=self.service
        mounted=self.home/'mounted AppImage'
        shutil.copytree(self.runtime,mounted)
        appimage=image.AppImageFirefox(self.home,mounted,proc=self.proc,run=self.run_fake)
        appimage.modutil=str(mounted/'fake-modutil')
        return native,appimage,self.identity('snap')

    def configure(self,service,identity):
        self.service=service
        plan=service.plan(identity)
        with patch('os.geteuid',return_value=1000):
            service.apply(identity,plan['fingerprint'])
        return plan

    def check_launch_order(self,appimage_first):
        native,appimage,identity=self.services()
        first,second=(appimage,native) if appimage_first else (native,appimage)
        configured=self.configure(first,identity)
        before=self.snapshot(self.home)
        registrations=sum('-rawadd' in command for command in self.commands)
        for service in [second,first,second]:
            plan=service.plan(identity)
            self.assertTrue(plan['alreadyConfigured'])
            self.assertEqual(plan['library'],configured['library'])
            self.assertEqual(service.inspect()['profiles'][0]['state'],'configured')
            self.configure(service,identity)
        self.assertEqual(before,self.snapshot(self.home))
        self.assertEqual(registrations,sum('-rawadd' in command for command in self.commands))
        self.assertFalse(self.connected)
        self.assertFalse(any(command[0]=='/usr/bin/pkexec' for command in self.commands))

    def test_native_then_appimage_reuses_the_snap_copy_without_nss_writes(self):
        self.check_launch_order(appimage_first=False)

    def test_appimage_then_native_reuses_the_snap_copy_without_nss_writes(self):
        self.check_launch_order(appimage_first=True)

    def test_actual_provider_update_and_corruption_are_still_detected(self):
        native,appimage,identity=self.services()
        old=self.configure(native,identity)
        path=appimage.runtime/image.LIBRARIES[1]
        path.write_bytes(b'new provider code, not a packaging change')
        self.runtime=appimage.runtime;self.refresh_manifest()
        newer=appimage.plan(identity)
        self.assertFalse(newer['alreadyConfigured'])
        self.assertNotEqual(old['library'],newer['library'])
        self.assertTrue(native.plan(identity)['alreadyConfigured'])
        Path(old['library']).write_bytes(b'tampered shared copy')
        for service in [native,appimage]:
            with self.assertRaises((image.SetupError,fixtures.setup.SetupError)):service.plan(identity)

if __name__=='__main__':unittest.main(verbosity=2)
