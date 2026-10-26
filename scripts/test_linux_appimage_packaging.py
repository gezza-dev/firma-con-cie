#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Packaging ABI/PCSC boundaries; synthetic fixtures, no CIE operations."""
from pathlib import Path
from types import SimpleNamespace
import tempfile
import struct
import json
import ctypes
import shutil
import subprocess
import unittest
from unittest.mock import patch
import package_linux_appimage as image
class Boundaries(unittest.TestCase):
    def browser_fixture(self, tree):
        runtime=tree/'usr/lib/firma-con-cie/cie_native'
        runtime.mkdir(parents=True)
        def compile(name,source,*options):
            subprocess.run(['cc','-shared','-fPIC','-x','c','-','-o',str(runtime/name),*options],
                           input=source,text=True,check=True,capture_output=True)
        compile('libcie-pkcs11.so','int fixture_backend(void) { return 42; }')
        compile('libcie_web.so','extern int fixture_backend(void); int fixture_web(void) { return fixture_backend(); }',
                '-L'+str(runtime),'-l:libcie-pkcs11.so','-Wl,-rpath,$ORIGIN:$ORIGIN/backend')
        compile('libcie_linux_pkcs11.so','extern int fixture_web(void); int fixture_provider(void) { return fixture_web(); }',
                '-L'+str(runtime),'-l:libcie_web.so','-Wl,-rpath,$ORIGIN')
        compile('libunrelated.so','int fixture_other(void) { return 1; }','-Wl,-rpath,/old/build/path')
        return runtime

    @unittest.skipUnless(shutil.which('cc') and shutil.which('patchelf'), 'ELF compiler and patchelf required')
    def test_browser_bytes_survive_relocation_and_load_outside_appimage(self):
        with tempfile.TemporaryDirectory() as temp:
            tree=Path(temp)/'AppDir';runtime=self.browser_fixture(tree)
            original={name:(runtime/name).read_bytes() for name in image.BROWSER_LIBRARIES}
            image.relocate_libraries(tree)
            self.assertEqual(original,{name:(runtime/name).read_bytes() for name in image.BROWSER_LIBRARIES})
            paths=image.run('patchelf','--print-rpath',runtime/'libunrelated.so').stdout.strip().split(':')
            self.assertIn('$ORIGIN',paths);self.assertNotIn('/old/build/path',paths)
            moved=Path(temp)/'persistent-module';moved.mkdir()
            for name in image.BROWSER_LIBRARIES:shutil.copy2(runtime/name,moved/name)
            shutil.rmtree(tree)
            # Only synthetic C functions, with no smart-card API or PC/SC link.
            provider=ctypes.CDLL(str(moved/'libcie_linux_pkcs11.so'))
            self.assertEqual(provider.fixture_provider(),42)

    @unittest.skipUnless(shutil.which('cc') and shutil.which('patchelf'), 'ELF compiler and patchelf required')
    def test_nonportable_browser_paths_fail_before_any_relocation(self):
        with tempfile.TemporaryDirectory() as temp:
            tree=Path(temp);runtime=self.browser_fixture(tree)
            for path in ['/outside/build/path','']:
                with self.subTest(path=path):
                    image.run('patchelf','--set-rpath',path,runtime/'libcie_web.so')
                    before={p:p.read_bytes() for p in runtime.iterdir()}
                    with self.assertRaisesRegex(ValueError,'nonportable RPATH|cannot locate'):
                        image.relocate_libraries(tree)
                    self.assertEqual(before,{p:p.read_bytes() for p in runtime.iterdir()})

    def test_host_libraries_are_always_external(self):
        for name in ['libpcsclite.so.1','libc.so.6','ld-linux-x86-64.so.2','ld-linux-aarch64.so.1','libm.so.6','libstdc++.so.6','libgcc_s.so.1','libGL.so.1','libEGL.so.1','libdrm.so.2','libgbm.so.1','libudev.so.1','libwayland-client.so.0','libwayland-server.so.0','libwayland-cursor.so.0','libwayland-egl.so.1']:
            self.assertTrue(image.EXTERNAL.fullmatch(name),name)
        for name in ['libgtk-3.so.0','libglib-2.0.so.0','libnss3.so','libcie_linux_pkcs11.so','libcrypto.so.3']:
            self.assertFalse(image.EXTERNAL.fullmatch(name),name)
    def test_architecture_selection_is_explicit_and_rejects_unsupported_targets(self):
        for name,target in [('amd64','x86_64'),('x86_64','x86_64'),('arm64','aarch64'),('aarch64','aarch64')]:
            self.assertEqual(image.architecture(name),target)
        for name in ['armv7l','i686','riscv64']:
            with self.assertRaisesRegex(ValueError,'Unsupported AppImage architecture'):image.architecture(name)

    def test_mixed_payloads_and_wrong_runtime_architecture_are_rejected(self):
        def elf(path,machine):
            ident=b'\x7fELF'+bytes([2,1,1])+bytes(9)
            path.write_bytes(ident+struct.pack('<HHIQQQIHHHHHH',3,machine,1,0,0,0,0,64,0,0,0,0,0))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);arm=root/'arm.so';elf(arm,183)
            self.assertIn('arm.so',image.check_abi(root,'aarch64'))
            with self.assertRaisesRegex(ValueError,'Expected x86_64 ELF'):image.check_abi(root,'x86_64')
            x64=root/'x64.so';elf(x64,62)
            with self.assertRaisesRegex(ValueError,'Expected arm64 ELF'):image.check_abi(root,'aarch64')
            for arch,runtime in [('x86_64',x64),('aarch64',arm)]:
                lock=json.loads(image.ARCHITECTURES[arch]['lock'].read_text())
                self.assertEqual(len(lock['sha256']),64)
                with patch.object(image,'sha',return_value=lock['sha256']):
                    self.assertEqual(image.validate_runtime(runtime,arch),lock)
                    with self.assertRaisesRegex(ValueError,'architecture differs'):
                        image.validate_runtime(arm if runtime==x64 else x64,arch)
                with patch.object(image,'sha',return_value='0'*64):
                    with self.assertRaisesRegex(ValueError,'checksum mismatch'):image.validate_runtime(runtime,arch)

    def test_mime_database_is_compiled_from_the_bundled_definitions(self):
        with tempfile.TemporaryDirectory() as temp:
            tree=Path(temp);packages=tree/'usr/share/mime/packages';packages.mkdir(parents=True)
            (packages/'fixture.xml').write_text('<?xml version="1.0"?><mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info"><mime-type type="application/x-cie-fixture"><glob pattern="*.cie-fixture"/></mime-type></mime-info>')
            image.compile_mime_database(tree)
            self.assertGreater((packages.parent/'mime.cache').stat().st_size,0)
            self.assertIn('application/x-cie-fixture',(packages.parent/'types').read_text())

    def test_numerical_abi_comparison_and_unsupported_floor(self):
        with patch.object(image,'run',return_value=SimpleNamespace(stdout='Name: GLIBC_2.9\nName: GLIBC_2.35\nName: GLIBCXX_3.4.29')):
            self.assertEqual(image.maximum_versions(Path('synthetic')),dict(GLIBC='2.35',GLIBCXX='3.4.29'))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);file=root/'synthetic.so';file.touch()
            with patch.object(image,'elf_files',return_value=[file]),patch.object(image,'maximum_versions',return_value=dict(GLIBC='2.38',GLIBCXX=None)):
                with self.assertRaisesRegex(ValueError,'newer than Ubuntu'):image.check_abi(root)
            file=root/'libpcsclite.so.1'
            with patch.object(image,'elf_files',return_value=[file]),patch.object(image,'maximum_versions',return_value=dict(GLIBC='2.17',GLIBCXX=None)):
                with self.assertRaisesRegex(ValueError,'must not be bundled'):image.check_abi(root)
    def test_non_numeric_new_glibc_feature_is_rejected(self):
        with patch.object(image,'run',return_value=SimpleNamespace(stdout='GLIBC_ABI_DT_RELR')):
            with self.assertRaisesRegex(ValueError,'newer glibc ABI'):image.maximum_versions(Path('synthetic'))
    def test_runtime_checksum_is_pinned_and_versions_require_release(self):
        import json
        lock=json.loads(image.LOCK.read_text());self.assertEqual(len(lock['sha256']),64)
        for version in ['1.0','01.0.0','1.0.0-test20261025.1','1.0.0/unsafe']:
            with self.assertRaisesRegex(ValueError,'release version'):image.package(Path('/nonexistent-bundle'),Path('/new-output'),Path('/nonexistent-runtime'),version)
if __name__=='__main__':unittest.main(verbosity=2)
