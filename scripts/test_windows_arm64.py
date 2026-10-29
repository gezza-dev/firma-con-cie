#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Architecture and packaging boundaries; synthetic files, no code execution."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from ltv_runtime import runtime_architecture
from product_identity import windows_installer_name
from windows_architecture import MACHINES, pe_machine, check_pe_tree, check_release_architecture
from package_windows_installer import prepare, sha
from ci_windows_arm64 import download
from check_openssl_arm64 import validate_configuration as validate_openssl_arm64
from prepare_cryptopp_arm64 import prepare_windows_arm64 as prepare_cryptopp_arm64
from prepare_podofo_arm64 import prepare_windows_arm64 as prepare_podofo_arm64

ROOT = Path(__file__).resolve().parents[1]


def pe(path, architecture='arm64'):
    path.parent.mkdir(parents=True,exist_ok=True)
    data = bytearray(128)
    data[:2] = b'MZ'
    struct.pack_into('<I',data,60,64)
    data[64:68] = b'PE\0\0'
    struct.pack_into('<H',data,68,MACHINES[architecture])
    path.write_bytes(data)


class WindowsArm64(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.release = self.root/'release'
        for name in ('Firma con CIE.exe','flutter_windows.dll','pdfium.dll','data/app.so',
                     'cie_native/cie_bridge.dll','cie_native/cie_card_observer.exe',
                     'cie_native/ltv/jre/windows-arm64/bin/java.exe',
                     'web-component/cie_prototype_minidriver.dll','web-component/CIE-Web-Setup.exe'):
            pe(self.release/name)
        (self.release/'cie_native/ltv/cie-ltv-worker.jar').write_bytes(b'synthetic JAR')
        manifest = {'system':'windows','architectures':['arm64'],
                    'ltv':{'architectures':['windows-arm64']}, 'source_files':{
                        n:sha(ROOT/n) for n in ('native/platform/windows/web/setup_policy.h',
                                               'native/platform/windows/web/card_catalog.h')}}
        self.manifest = self.release/'cie_native/backend-manifest.json'
        self.manifest.write_text(json.dumps(manifest))

    def test_arm64_native_dss_selection(self):
        for cpu in ('arm64','ARM64','aarch64'):
            self.assertEqual(runtime_architecture('Windows',cpu),'windows-arm64')
        self.assertEqual(runtime_architecture('Windows','AMD64'),'windows-x86_64')

    def test_cryptopp_windows_header_case_fix_preserves_other_bytes(self):
        original = (b'// Original upstream notice\r\n'
                    b'#if defined(_WIN32) && defined(_M_ARM64)\r\n'
                    b'# include <Windows.h>\r\n# include <processthreadsapi.h>\r\n'
                    b'#endif\r\n// UTF-8: \xc3\xa8\r\n')
        path = self.root/'cpu.cpp'
        path.write_bytes(original)
        prepare_cryptopp_arm64(self.root)
        self.assertEqual(path.read_bytes(), original.replace(b'<Windows.h>', b'<windows.h>'))

    def test_podofo_both_charconv_guards_exclude_libcpp_only(self):
        path = self.root/'src/podofo/private/charconv_compat.h'
        path.parent.mkdir(parents=True)
        guard = b'(defined(__MINGW32__) &&  __GNUC__ < 12)'
        original = b'// Original notice\r\n#if '+guard+b'\r\n#define WANT_FROM_CHARS\r\n#endif\r\n#if '+guard+b'\r\n#define WANT_TO_CHARS\r\n#endif\r\n'
        path.write_bytes(original)
        prepare_podofo_arm64(self.root)
        expected = original.replace(guard,b'(defined(__MINGW32__) && !defined(_LIBCPP_VERSION) && __GNUC__ < 12)')
        self.assertEqual(path.read_bytes(),expected)

    def test_podofo_missing_or_ambiguous_guard_fails_without_writing(self):
        path = self.root/'src/podofo/private/charconv_compat.h'
        path.parent.mkdir(parents=True)
        guard = b'(defined(__MINGW32__) &&  __GNUC__ < 12)'
        for count in (0,1,3):
            original = b'// Different upstream source\n'+guard*count
            path.write_bytes(original)
            with self.assertRaisesRegex(ValueError,'Unexpected PoDoFo'):
                prepare_podofo_arm64(self.root)
            self.assertEqual(path.read_bytes(),original)

    def test_cryptopp_missing_expected_include_fails_without_writing(self):
        path = self.root/'cpu.cpp'
        for original in (b'# include <windows.h>\n', b'// Different upstream source\n'):
            path.write_bytes(original)
            with self.assertRaisesRegex(ValueError,'Unexpected Crypto'):
                prepare_cryptopp_arm64(self.root)
            self.assertEqual(path.read_bytes(),original)

    def test_cryptopp_ambiguous_include_fails_without_writing(self):
        path = self.root/'cpu.cpp'
        original = b'# include <Windows.h>\n# include <Windows.h>\n'
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError,'Unexpected Crypto'):
            prepare_cryptopp_arm64(self.root)
        self.assertEqual(path.read_bytes(),original)

    def test_openssl_windows_initializer_is_in_generated_graph(self):
        (self.root/'configdata.pm').write_text("'apps/lib/win32_init.c'")
        (self.root/'Makefile').write_text('apps/libapps.a: apps/lib/libapps-lib-win32_init.obj\n'
                                          'apps/lib/libapps-lib-win32_init.obj: apps/lib/win32_init.c\n')
        validate_openssl_arm64(self.root)

    def test_openssl_graph_without_windows_initializer_is_rejected(self):
        (self.root/'configdata.pm').write_text("'apps/lib/apps.c'")
        (self.root/'Makefile').write_text('apps/libapps.a: apps/lib/libapps-lib-apps.obj\n')
        with self.assertRaisesRegex(ValueError,'win32_utf8argv'):
            validate_openssl_arm64(self.root)

    def test_openssl_makefile_without_initializer_object_is_rejected(self):
        (self.root/'configdata.pm').write_text("'apps/lib/win32_init.c'")
        for text in ('apps/libapps.a: apps/lib/libapps-lib-apps.obj\n',
                     '# apps/lib/win32_init.c\n'):
            (self.root/'Makefile').write_text(text)
            with self.assertRaisesRegex(ValueError,'win32_utf8argv'):
                validate_openssl_arm64(self.root)

    def test_installer_name_and_reject_architecture_injection(self):
        self.assertEqual(windows_installer_name('1.0.0','arm64'),'firma-con-cie_1.0.0_windows_arm64_setup')
        self.assertEqual(windows_installer_name('1.0.0'),'firma-con-cie_1.0.0_windows_x64_setup')
        with self.assertRaises(ValueError):
            windows_installer_name('1.0.0','../arm64')

    def test_complete_arm64_tree(self):
        self.assertEqual(len(check_release_architecture(self.release,'arm64')),9)

    def test_x64_flutter_or_pdfium_or_jvm_or_minidriver_rejected(self):
        for name in ('Firma con CIE.exe','pdfium.dll','data/app.so',
                     'cie_native/ltv/jre/windows-arm64/bin/java.exe',
                     'web-component/cie_prototype_minidriver.dll'):
            with self.subTest(name=name):
                pe(self.release/name,'x64')
                with self.assertRaisesRegex(ValueError,'Expected arm64 PE'):
                    check_release_architecture(self.release,'arm64')
                pe(self.release/name)

    def test_arm64_cannot_be_labeled_x64(self):
        with self.assertRaisesRegex(ValueError,'Expected x64 PE'):
            check_pe_tree(self.release,'x64')

    def test_damaged_or_truncated_pe_rejected(self):
        p = self.root/'bad.dll'
        for value in (b'', b'MZ', b'MZ'+bytes(100), bytes(128)):
            p.write_bytes(value)
            with self.assertRaises(ValueError):
                pe_machine(p)
        pe(p)
        data = bytearray(p.read_bytes())
        struct.pack_into('<I',data,60,0xFFFFFFFF)
        p.write_bytes(data)
        with self.assertRaises(ValueError):
            pe_machine(p)

    def test_false_native_or_java_manifest_rejected(self):
        original = self.manifest.read_text()
        for field in ('architectures','ltv'):
            m = json.loads(original)
            m[field] = ['x86_64'] if field=='architectures' else {'architectures':['windows-x86_64']}
            self.manifest.write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError,'architecture'):
                check_release_architecture(self.release,'arm64')
        self.manifest.write_text(original)

    def test_tool_download_fails_closed_on_wrong_hash(self):
        source = self.root/'tool.txt'
        source.write_bytes(b'synthetic tool, never executed')
        item = {'url':source.as_uri(),'archive':'tool.txt','sha256':sha(source)}
        p = download(item,self.root/'cache')
        self.assertEqual(p.read_bytes(),source.read_bytes())
        p.write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError,'checksum mismatch'):
            download(item,self.root/'cache')

    def test_arm64_installer_targets_native_os_and_preserves_identity(self):
        native = self.release/'cie_native'
        m = json.loads(self.manifest.read_text())
        m['files'] = {p.relative_to(native).as_posix():sha(p) for p in native.rglob('*') if p.is_file() and p!=self.manifest}
        self.manifest.write_text(json.dumps(m))
        web = self.release/'web-component'
        files = {'cie_prototype_minidriver.dll':sha(web/'cie_prototype_minidriver.dll')}
        (web/'payload-manifest.json').write_text(json.dumps({'files':files,'version':hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()}))
        redist = self.root/'redist.exe'
        redist.write_bytes(b'not executed')
        script, installer, manifest = prepare(self.release,self.root/'Setup','1.0.0',redist,architecture='arm64')
        config = (script.parent/'build-config.iss').read_text(encoding='utf-8-sig')
        self.assertIn('#define TargetArchitecture "arm64"',config)
        self.assertIn('#define VcRedistName "vc_redist.arm64.exe"',config)
        self.assertIn('#define MinimumWindowsVersion "10.0.22000"',config)
        self.assertEqual(installer.name,'firma-con-cie_1.0.0_windows_arm64_setup.exe')
        self.assertEqual(manifest['userDataActions'],[])
        self.assertEqual(manifest['uacOwner'],'installer')
        self.assertIn('7D9C31E3-F685-48E7-88BF-152BF8D331F2',script.read_text())


if __name__ == '__main__':
    unittest.main()
