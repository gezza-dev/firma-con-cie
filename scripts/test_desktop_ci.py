#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Desktop CI boundaries: synthetic tools, no network, keychain, card or installer."""
import base64
import ast
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import ci_desktop_common as common
import ci_linux
import ci_macos as mac
import ci_windows_arm64 as windows
import test_linux_tls_runtime as linux_tls


def configuration():
    result = {key:'synthetic-value' for key in mac.SECRET_NAMES}
    result.update(MACOS_TEAM_ID='A123456789',
                  MACOS_SIGNING_IDENTITY='Developer ID Application: Synthetic',
                  MACOS_CERTIFICATE_P12_BASE64=base64.b64encode(b'synthetic certificate').decode(),
                  MACOS_NOTARY_KEY_P8_BASE64=base64.b64encode(b'synthetic notary key').decode())
    return result


class DesktopCI(unittest.TestCase):
    def test_windows_architectures_keep_independent_outputs_and_dss_cpu(self):
        self.addCleanup(windows.select_architecture, 'arm64')
        outputs = []
        for arch, cpu in [('arm64','arm64'), ('x64','x86_64')]:
            windows.select_architecture(arch)
            self.assertEqual(windows.CPU, cpu)
            self.assertEqual(windows.REPORTS.name, 'windows-'+arch)
            outputs.append(windows.TRANSFER)
        self.assertNotEqual(*outputs)
        with self.assertRaises(ValueError):
            windows.select_architecture('x86')

    def test_native_host_architecture_rejects_32_bit_and_maps_linux_arm(self):
        for raw, expected in [('aarch64','arm64'), ('ARM64','arm64'), ('AMD64','x64'), ('x86_64','x64')]:
            with patch.object(common.platform, 'machine', return_value=raw):
                self.assertEqual(common.host_architecture(), expected)
        with patch.object(common.platform, 'machine', return_value='i686'):
            with self.assertRaises(ValueError):
                common.host_architecture()

    def test_windows_phases_never_hardcode_a_different_packaging_cpu(self):
        tree = ast.parse(Path(windows.__file__).read_text())
        checked = 0
        for call in ast.walk(tree):
            if not isinstance(call, ast.Call):
                continue
            for index, argument in enumerate(call.args[:-1]):
                if isinstance(argument, ast.Constant) and argument.value in ('--architecture','--windows-architecture'):
                    self.assertIsInstance(call.args[index+1], ast.Name)
                    self.assertIn(call.args[index+1].id, ('ARCHITECTURE','CPU'))
                    checked += 1
        self.assertEqual(checked, 4)

    def test_mac_build_jdk_resolves_contents_home_from_the_locked_architecture(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            with patch.object(common, 'download', return_value=work/'archive'), patch.object(common, 'extract', return_value=work/'jdk/Contents/Home') as extract, patch.object(common, 'unpack', return_value=work/'maven-home'):
                java, maven, cache = common.java_tools('macos', 'arm64', work)
            self.assertEqual(java, work/'jdk/Contents/Home')
            self.assertEqual(maven, work/'maven-home/bin/mvn')
            self.assertTrue(extract.call_args.args[2].startswith('macos'))
            self.assertIn('aarch64_mac', extract.call_args.args[0]['archive'])

    def test_linux_build_cannot_run_on_another_os(self):
        with patch.object(ci_linux.platform, 'system', return_value='Windows'), patch.object(ci_linux, 'run') as run:
            with self.assertRaises(ValueError):
                ci_linux.build('deb')
            run.assert_not_called()

    def test_linux_tls_keeps_user_namespace_by_default_and_requires_root_to_omit_it(self):
        self.assertIn('--unshare-user', linux_tls.namespace_arguments())
        with patch.object(linux_tls.os, 'geteuid', return_value=1001, create=True):
            with self.assertRaises(RuntimeError):
                linux_tls.namespace_arguments(False)
        with patch.object(linux_tls.os, 'geteuid', return_value=0, create=True):
            self.assertEqual(linux_tls.namespace_arguments(False), [])

    def test_failed_tls_cannot_promote_an_incomplete_linux_build_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reports = root/'reports/linux-x64-deb'
            reports.mkdir(parents=True)
            (reports/'build-result.json').write_text(json.dumps({'softwareChecksPassed':False,'tlsChecksPending':True}))
            (reports/'tls.json').write_text(json.dumps({'passed':False}))
            with patch.object(ci_linux, 'ROOT', root), patch.object(ci_linux.platform, 'system', return_value='Linux'), patch.object(ci_linux.os, 'geteuid', return_value=0, create=True), patch.object(ci_linux, 'host_architecture', return_value='x64'), patch.object(ci_linux, 'python'):
                with self.assertRaises(ValueError):
                    ci_linux.finish_tls('deb')
            self.assertFalse((reports/'result.json').exists())

    def test_mac_missing_secrets_fail_without_echoing_present_values(self):
        with self.assertRaises(ValueError) as error:
            mac.signing_configuration({'MACOS_CERTIFICATE_PASSWORD':'never-print-this'})
        self.assertIn('MACOS_TEAM_ID', str(error.exception))
        self.assertNotIn('never-print-this', str(error.exception))

    def test_windows_toolchain_notices_survive_web_component_packaging(self):
        for toolchain in ('llvm-mingw','mingw-runtime'):
            with self.subTest(toolchain=toolchain), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                runtime = root/'runtime'
                runtime.mkdir()
                for name in ('cie_web.dll','cie-pkcs11.dll'):
                    (runtime/name).write_bytes(b'synthetic binary')
                licenses = runtime/'licenses'
                licenses.mkdir()
                for name in ('LICENSE.txt','LICENSE_AUDIT.md','THIRD_PARTY_NOTICES.md','prototype-LICENSE','prototype-NOTICE.md'):
                    (licenses/name).write_text('synthetic attribution')
                (licenses/'LICENSES').mkdir()
                (licenses/toolchain).mkdir()
                (licenses/toolchain/'copyright').write_text('synthetic runtime attribution')
                files = {p.relative_to(runtime).as_posix():common.sha(p) for p in runtime.rglob('*') if p.is_file()}
                (runtime/'backend-manifest.json').write_text(json.dumps({'files':files,'windows_runtime_dlls':[]}))
                provider = root/'provider.dll'
                provider.write_bytes(b'synthetic provider')
                output = root/'payload'
                subprocess.run([sys.executable,str(common.ROOT/'scripts/package_web_windows.py'),
                                '--runtime',str(runtime),'--provider',str(provider),'--output',str(output)],
                               check=True, capture_output=True)
                manifest = json.loads((output/'payload-manifest.json').read_text())
                name = 'backend/licenses/'+toolchain+'/copyright'
                self.assertEqual((output/name).read_text(), 'synthetic runtime attribution')
                self.assertEqual(manifest['files'][name], common.sha(output/name))

    def test_mac_rejects_ad_hoc_identity_and_invalid_team(self):
        values = configuration()
        values['MACOS_SIGNING_IDENTITY'] = '-'
        with self.assertRaises(ValueError):
            mac.signing_configuration(values)
        values = configuration()
        values['MACOS_TEAM_ID'] = 'invalid'
        with self.assertRaises(ValueError):
            mac.signing_configuration(values)

    def test_mac_build_preserves_reports_created_by_the_source_audit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reports = root/'reports/macos'
            reports.mkdir(parents=True)
            audit = reports/'source-audit.json'
            audit.write_text('synthetic source audit')
            with patch.object(mac, 'ROOT', root), patch.object(mac, 'signing_configuration', return_value=configuration()), patch.object(mac.platform, 'system', return_value='Darwin'), patch.object(mac.platform, 'machine', return_value='arm64'), patch.object(mac.subprocess, 'check_output', return_value='Xcode 26.6\n'), patch.object(mac, 'flutter_checks', side_effect=RuntimeError('stop before toolchain')) as checks:
                with self.assertRaisesRegex(RuntimeError, 'stop before toolchain'):
                    mac.build()
            checks.assert_called_once()
            self.assertEqual(audit.read_text(), 'synthetic source audit')

    def test_credential_command_failure_never_echoes_argv_or_stderr(self):
        output = io.StringIO()
        with patch.object(mac.subprocess, 'run', return_value=SimpleNamespace(returncode=1,stdout='',stderr='secret-from-tool')):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                with self.assertRaises(RuntimeError) as error:
                    mac.confidential('security', 'import', '-P', 'secret-in-argv')
        self.assertNotIn('secret', output.getvalue())
        self.assertNotIn('secret-in-argv', str(error.exception))
        self.assertNotIn('secret-from-tool', str(error.exception))

    def test_apple_id_notarization_does_not_require_an_api_key(self):
        values = configuration()
        for key in ('MACOS_NOTARY_KEY_P8_BASE64','MACOS_NOTARY_KEY_ID','MACOS_NOTARY_ISSUER_ID'):
            values.pop(key)
        with tempfile.TemporaryDirectory() as temporary:
            session = mac.SigningSession(mac.signing_configuration(values), temporary)
            with patch.object(mac, 'confidential', return_value='') as execute:
                with session:
                    pass
            calls = [call.args for call in execute.call_args_list if call.args[:3] == ('xcrun','notarytool','store-credentials')]
            self.assertEqual(len(calls), 1)
            self.assertIn('--apple-id', calls[0])
            self.assertIn('--team-id', calls[0])
            self.assertNotIn('--key', calls[0])

    def test_partial_keychain_setup_restores_search_list_and_removes_only_own_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unrelated = root/'keep.txt'
            unrelated.write_text('keep')
            session = mac.SigningSession(configuration(), root)
            commands = []
            def execute(*args):
                commands.append(args)
                if args[:3] == ('security','list-keychains','-d') and len(args) == 4:
                    return '"/synthetic/login.keychain-db"\n'
                if args[:2] == ('security','import'):
                    raise RuntimeError('synthetic import failure')
                return ''
            with patch.object(mac, 'confidential', side_effect=execute):
                with self.assertRaises(RuntimeError):
                    session.__enter__()
            self.assertFalse(session.folder.exists())
            self.assertEqual(unrelated.read_text(), 'keep')
            self.assertIn(('security','list-keychains','-d','user','-s','/synthetic/login.keychain-db'), commands)

    def test_invalid_base64_is_removed_on_import_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            values = configuration()
            values['MACOS_NOTARY_KEY_P8_BASE64'] = 'invalid!'
            session = mac.SigningSession(values, temporary)
            with patch.object(mac, 'confidential', return_value=''):
                with self.assertRaisesRegex(ValueError, 'MACOS_NOTARY_KEY_P8_BASE64'):
                    session.__enter__()
            self.assertFalse(session.folder.exists())

    def test_always_cleanup_recovers_an_interrupted_session_without_touching_other_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            other = root/'other.p12'
            other.write_text('unrelated')
            folder = root/'firma-cie-signing-synthetic'
            folder.mkdir()
            (folder/'state.json').write_text(json.dumps(['/synthetic/login.keychain-db']))
            (folder/'identity.p12').write_text('synthetic')
            (folder/'notary.p8').write_text('synthetic')
            (folder/'build.keychain-db').write_text('synthetic')
            with patch.object(mac, 'confidential') as confidential, patch.object(mac.subprocess, 'run'):
                mac.cleanup(root)
            self.assertFalse(folder.exists())
            self.assertTrue(other.is_file())
            confidential.assert_called_once_with('security','list-keychains','-d','user','-s','/synthetic/login.keychain-db')

    def test_notarization_requires_accepted_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            session = mac.SigningSession(configuration(), temporary)
            for status in ('Invalid', 'In Progress'):
                with patch.object(mac, 'confidential', return_value=json.dumps({'id':'synthetic','status':status})):
                    with self.assertRaises(RuntimeError):
                        session.notarize(Path('synthetic.zip'))
            with patch.object(mac, 'confidential', return_value=json.dumps({'id':'synthetic','status':'Accepted','extra':'not in receipt'})):
                self.assertEqual(session.notarize(Path('synthetic.zip')), {'id':'synthetic','status':'Accepted'})
            session.close()

    def test_final_artifact_receipt_uses_bytes_after_stapling(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root/'test.dmg'
            artifact.write_bytes(b'before')
            with patch.object(common, 'ROOT', root), patch.object(common, 'source_commit', return_value='synthetic'), patch.object(common, 'application_version', return_value='1.0.1'):
                first = common.receipt(root/'first.json', 'macos', 'universal', [artifact])
                artifact.write_bytes(b'after-stapling')
                second = common.receipt(root/'second.json', 'macos', 'universal', [artifact])
            self.assertNotEqual(first['artifacts'], second['artifacts'])
            self.assertFalse(second['hardwareValidated'])
            self.assertFalse(second['releasePublished'])

    def test_ci_only_starts_manually_and_uploads_no_keychain(self):
        for name in ('desktop-packages.yml','macos-package.yml','linux-package.yml','linux-distributions.yml','windows-package.yml','windows-arm64.yml'):
            text = (common.ROOT/'.github/workflows'/name).read_text()
            self.assertIn('  workflow_dispatch:', text)
            self.assertNotRegex(text, r'(?m)^  (push|pull_request|pull_request_target):')
            self.assertIn('contents: read', text)
            self.assertNotIn('contents: write', text)
        workflow = (common.ROOT/'.github/workflows/macos-package.yml').read_text()
        uploads = workflow.split('uses: actions/upload-artifact@v4')[1:]
        self.assertTrue(uploads)
        for upload in uploads:
            self.assertNotIn('RUNNER_TEMP', upload)
            self.assertNotIn('keychain', upload)
            self.assertNotIn('*.p12', upload)
        self.assertIn('if: always()\n        run: python3 scripts/ci_macos.py cleanup', workflow)


if __name__ == '__main__':
    unittest.main(verbosity=2)
