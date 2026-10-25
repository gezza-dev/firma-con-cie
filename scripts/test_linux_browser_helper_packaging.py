#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Companion payload boundaries, synthetic non-executable inputs only."""
import json
from pathlib import Path
import tempfile
import unittest
import package_linux_browser_helper as package
from linux_package_common import ROOT,files,sha
class Boundaries(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.runtime=self.root/'runtime';self.runtime.mkdir()
        (self.runtime/'browser_setup').mkdir();(self.runtime/'licenses').mkdir()
        (self.runtime/'licenses/NOTICE').write_text('Synthetic license notice')
        for name in package.LIBRARIES:(self.runtime/name).write_bytes(b'synthetic library')
        for name in ['firefox_setup.py','chrome_setup.py']:
            (self.runtime/'browser_setup'/name).write_bytes((ROOT/'native/platform/linux/browser_setup'/name).read_bytes())
        (self.runtime/'browser_setup/libcie_browser_setup_guard.so').write_bytes(b'synthetic guard')
        manifest=dict(system='linux',linux_web_full_pin_only=True,linux_firefox_pkcs11=True,
            linux_firefox_snap_core24_abi_verified=True,files={p.relative_to(self.runtime).as_posix():sha(p) for p in files(self.runtime)})
        (self.runtime/'backend-manifest.json').write_text(json.dumps(manifest))
        # Neither source tests nor arbitrary extra files can enter the payload.
        (self.runtime/'tests').mkdir();(self.runtime/'tests/private.key').write_text('synthetic excluded marker')
        self.publisher=self.root/'publisher';self.publisher.write_bytes(b'\x7fELF synthetic production utility')
    def test_separate_prefix_activation_no_autostart_hooks_or_user_files(self):
        dest=self.root/'stage';manifest=package.stage(self.runtime,self.publisher,dest)
        app=dest/package.PREFIX
        self.assertNotEqual(package.PREFIX,Path('opt/firma-con-cie'))
        self.assertFalse((dest/'opt/firma-con-cie').exists())
        self.assertFalse((app/'tests').exists());self.assertFalse(any(p.suffix=='.key' for p in files(dest)))
        self.assertFalse((dest/'usr/share/applications').exists());self.assertFalse((dest/'etc').exists())
        self.assertFalse(any(p.name in ['postinst','postrm','preinst','prerm','.INSTALL'] for p in files(dest)))
        services=list((dest/'usr/share/dbus-1/services').iterdir());self.assertEqual(len(services),1)
        service=services[0].read_text();self.assertIn('Exec=/usr/bin/python3 -I /opt/firma-con-cie-browser-helper/',service)
        self.assertIn('Name='+package.BUS,service)
        for name,digest in manifest['files'].items():self.assertEqual(sha(app/name),digest)
        for name in ['firefox_setup.py','chrome_setup.py']:
            self.assertEqual((app/'browser_setup'/name).read_bytes(),(self.runtime/'browser_setup'/name).read_bytes())
    def test_test_publisher_and_modified_native_scripts_are_rejected(self):
        self.publisher.write_bytes(b'\x7fELF CIE_PAIRING_TEST_CACHE')
        with self.assertRaisesRegex(ValueError,'Test-only'):package.stage(self.runtime,self.publisher,self.root/'stage')
        self.publisher.write_bytes(b'\x7fELF synthetic production utility')
        (self.runtime/'browser_setup/firefox_setup.py').write_bytes(b'altered')
        with self.assertRaisesRegex(ValueError,'checksum'):package.stage(self.runtime,self.publisher,self.root/'stage2')
    def test_versions_and_existing_output_rejected(self):
        for version in ['1.0.0','0.1~test/escape']:
            with self.assertRaisesRegex(ValueError,'testYYYY'):package.package(self.runtime,self.publisher,self.root/'out','deb',version)
        with self.assertRaisesRegex(ValueError,'New output'):package.package(self.runtime,self.publisher,self.root,'deb','0.1~test20261024.1')
if __name__=='__main__':unittest.main(verbosity=2)
