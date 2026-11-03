#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fedora/Arch CI boundaries using synthetic archives and package commands only."""
import io
import json
from pathlib import Path
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import ci_linux_distribution as ci
import package_linux_distribution as packaging
import test_linux_distribution_package as lifecycle
import test_linux_tls_runtime as tls


class DistributionCI(unittest.TestCase):
    def test_missing_build_or_inspection_tool_is_reported_before_compilation(self):
        for missing in ('which', 'gresource', 'openssl'):
            with self.subTest(tool=missing), \
                 patch.object(ci.shutil,'which',side_effect=lambda tool:None if tool==missing else '/synthetic/tool'), \
                 patch.object(ci,'run') as run, self.assertRaisesRegex(RuntimeError,'Missing distribution build tools: '+missing):
                ci.require_tools('fedora')
            run.assert_not_called()

    def test_tls_mount_uses_canonical_certificates_directory(self):
        directory=Path('/synthetic/linked-certificates');canonical=Path('/synthetic/real-certificates')
        ca=Path('/synthetic/ca.pem')
        with patch.object(Path,'resolve',return_value=canonical) as resolve:
            arguments=tls.trust_mount_arguments(ca,directory)
        resolve.assert_called_once_with(strict=True)
        self.assertEqual(arguments,['--tmpfs',str(canonical),'--ro-bind',str(ca),str(canonical/'ca-certificates.crt')])

    def test_matrix_selects_only_requested_native_cpus(self):
        all_targets = ci.matrices('all')
        self.assertEqual([(p['distribution'], p['architecture']) for p in all_targets['package']['include']],
                         [('fedora', 'x64'), ('fedora', 'arm64'), ('arch', 'x64')])
        self.assertEqual([p['runner'] for p in all_targets['runtime']['include']],
                         ['ubuntu-24.04', 'ubuntu-24.04-arm'])
        self.assertEqual(len(ci.matrices('fedora')['package']['include']), 2)
        self.assertEqual(ci.matrices('arch')['runtime']['include'],
                         [{'architecture':'x64', 'runner':'ubuntu-24.04'}])
        with self.assertRaises(ValueError): ci.matrices('untrusted-input')

    def test_rpm_accepts_aarch64_but_arch_remains_x86_64_only(self):
        for machine in ('arm64', 'aarch64'):
            self.assertEqual(packaging.package_architecture('rpm', machine), 'aarch64')
            with self.assertRaises(ValueError): packaging.package_architecture('arch', machine)
        self.assertEqual(packaging.package_architecture('arch', 'AMD64'), 'x86_64')
        with self.assertRaises(ValueError): packaging.package_architecture('rpm', 'armv7l')

    def test_arm_rpm_recipe_and_output_use_aarch64_and_private_dependencies_stay_private(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); stage = root/'stage'; inputs = root/'inputs'; output = root/'output'
            for p in (stage, inputs, output):p.mkdir()
            (inputs/'payload.tar.gz').write_bytes(b'synthetic payload')
            elf = stage/'libprivate.so';elf.write_bytes(b'synthetic ELF')
            def command(*args, **kwargs):
                if args[0] == 'rpmbuild':
                    path = inputs/'rpmbuild/RPMS/aarch64/firma-con-cie-1.0.1-2.fc44.aarch64.rpm'
                    path.parent.mkdir(parents=True);path.write_bytes(b'synthetic RPM')
                if str(args[0]).endswith('rpmdeps'):
                    return SimpleNamespace(stdout='libprivate.so()(64bit)\nlibc.so.6(GLIBC_2.39)(64bit)\n')
                if args[:2] == ('rpm', '-E'):return SimpleNamespace(stdout='/synthetic/rpm')
                return SimpleNamespace(stdout='firma-con-cie')
            with patch.object(packaging, 'run', side_effect=command):
                artifact, version = packaging.rpm_package(stage, [elf], inputs, output, '1.0.1', '2.fc44', 0, 'aarch64')
            self.assertEqual(artifact.name, 'firma-con-cie_1.0.1_linux_fedora_aarch64.rpm')
            self.assertEqual(version, '1.0.1-2.fc44')
            self.assertIn('BuildArch: aarch64', (output/'firma-con-cie.spec').read_text())
            self.assertNotIn('libprivate.so', (output/'requires.txt').read_text())
            self.assertIn('GLIBC_2.39', (output/'requires.txt').read_text())

    def test_arch_download_name_omits_pkgrel_while_recipe_keeps_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);stage=root/'stage';inputs=root/'inputs';output=root/'output'
            for folder in (stage,inputs,output):folder.mkdir()
            (inputs/'payload.tar.gz').write_bytes(b'synthetic payload')
            def command(*args,**kwargs):
                if args[0]=='makepkg':
                    (inputs/'firma-con-cie-1.0.2-7-x86_64.pkg.tar.zst').write_bytes(b'synthetic Arch package')
                if args[:2]==('pacman','-Qp'):return SimpleNamespace(stdout='firma-con-cie 1.0.2-7')
                return SimpleNamespace(stdout='glibc')
            with patch.object(packaging,'run',side_effect=command), patch.object(packaging.os,'geteuid',return_value=1000):
                artifact,version=packaging.arch_package(stage,[],inputs,output,'1.0.2','7')
            self.assertEqual(artifact.name,'firma-con-cie_1.0.2_linux_arch_x86_64.pkg.tar.zst')
            self.assertEqual(version,'1.0.2-7')
            self.assertIn('pkgrel=7', (output/'PKGBUILD').read_text())
            self.assertEqual(artifact.read_bytes(),b'synthetic Arch package')

    def archive_fixture(self, root, member='runtime/backend-manifest.json', source_files=None):
        manifest = json.dumps({'source_files':source_files or {}}).encode()
        archive = root/'runtime.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            info = tarfile.TarInfo(member);info.size=len(manifest);info.mode=0o644
            tar.addfile(info, io.BytesIO(manifest))
        import hashlib
        metadata = root/'runtime-source.json'
        metadata.write_text(json.dumps({'sourceCommit':'synthetic-commit', 'architecture':'arm64',
            'softwareChecksPassed':True, 'nativeTlsChecksPassed':True,
            'artifacts':{'runtime.tar.gz':ci.sha(archive)},
            'nativeManifestSha256':hashlib.sha256(manifest).hexdigest()}))
        return archive, metadata

    def test_runtime_rejects_wrong_commit_cpu_or_failed_tests_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);archive, metadata = self.archive_fixture(root)
            original = json.loads(metadata.read_text())
            for key,value in [('sourceCommit','other'), ('architecture','x64'),
                              ('softwareChecksPassed',False), ('nativeTlsChecksPassed',False)]:
                metadata.write_text(json.dumps(dict(original, **{key:value})))
                with patch.object(ci, 'source_commit', return_value='synthetic-commit'), self.assertRaises(ValueError):
                    ci.extract_runtime(archive, metadata, root/'extracted', 'arm64')
                self.assertFalse((root/'extracted').exists())

    def test_runtime_rejects_tampered_archive_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);archive, metadata = self.archive_fixture(root)
            archive.write_bytes(archive.read_bytes()+b'tampered')
            with patch.object(ci, 'source_commit', return_value='synthetic-commit'), self.assertRaisesRegex(ValueError, 'checksum'):
                ci.extract_runtime(archive, metadata, root/'extracted', 'arm64')
            self.assertFalse((root/'extracted').exists())

    def test_runtime_rejects_archive_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);archive, metadata = self.archive_fixture(root, 'runtime/../../escape')
            with patch.object(ci, 'source_commit', return_value='synthetic-commit'), self.assertRaisesRegex(ValueError, 'Unsafe'):
                ci.extract_runtime(archive, metadata, root/'extracted', 'arm64')
            self.assertFalse((root/'escape').exists())

    def test_runtime_source_hashes_must_match_this_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);source = root/'scripts/synthetic.py';source.parent.mkdir();source.write_text('original')
            archive, metadata = self.archive_fixture(root, source_files={'scripts/synthetic.py':ci.sha(source)})
            with patch.object(ci, 'ROOT', root), patch.object(ci, 'source_commit', return_value='synthetic-commit'):
                self.assertTrue(ci.extract_runtime(archive, metadata, root/'good', 'arm64').is_dir())
                source.write_text('modified')
                with self.assertRaisesRegex(ValueError, 'source provenance mismatch'):
                    ci.extract_runtime(archive, metadata, root/'bad', 'arm64')

    def test_container_install_mode_requires_both_markers_and_root(self):
        with patch.object(lifecycle.os, 'geteuid', return_value=0, create=True), patch.object(Path, 'exists', return_value=False):
            for missing in ('.dockerenv', '.cie-distribution-ci-root'):
                with patch.object(Path, 'is_file', lambda p:p.name!=missing), self.assertRaises(RuntimeError):
                    lifecycle.require_isolated_root(container=True)
            with patch.object(Path, 'is_file', return_value=True):
                lifecycle.require_isolated_root(container=True)
        with patch.object(lifecycle.os, 'geteuid', return_value=1001, create=True), self.assertRaises(RuntimeError):
            lifecycle.require_isolated_root(container=True)

    def test_container_install_mode_still_refuses_card_interfaces(self):
        with patch.object(lifecycle.os, 'geteuid', return_value=0, create=True), \
             patch.object(Path, 'is_file', return_value=True), patch.object(Path, 'exists', return_value=True), \
             self.assertRaisesRegex(RuntimeError, 'Card interfaces'):
            lifecycle.require_isolated_root(container=True)

    def test_runtime_root_phase_completes_builder_receipt_without_running_git(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);runtime = root/'runtime';runtime.mkdir()
            (runtime/'backend-manifest.json').write_text('{}')
            reports = root/'reports';reports.mkdir()
            (reports/'build-result.json').write_text(json.dumps({'sourceCommit':'synthetic-commit',
                'architecture':'x64','softwareChecksPassed':False,'tlsChecksPending':True}))
            (reports/'tls.json').write_text(json.dumps({'passed':True}))
            with patch.object(ci,'ROOT',root), patch.object(ci,'runtime_paths',return_value=(root/'work',runtime,reports)), \
                 patch.object(ci.platform,'system',return_value='Linux'), \
                 patch.object(ci.os,'geteuid',return_value=0,create=True), patch.object(Path,'is_file',return_value=True), \
                 patch.object(ci,'host_architecture',return_value='x64'), patch.object(ci,'python'), \
                 patch.object(ci,'source_commit',side_effect=AssertionError('Root must not run Git')), \
                 patch.object(ci,'receipt',side_effect=AssertionError('Root must complete the existing receipt')):
                ci.finish_runtime()
            result = json.loads((root/'dist/linux-distribution-runtime-x64/runtime-source.json').read_text())
            self.assertEqual(result['sourceCommit'],'synthetic-commit')
            self.assertTrue(result['softwareChecksPassed'])
            self.assertFalse(result['tlsChecksPending'])

    def test_failed_target_tls_never_produces_a_success_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);reports = root/'reports/linux-fedora-x64';reports.mkdir(parents=True)
            for parent in (root/'dist/linux-fedora-x64', root/'.build/ci-fedora/upgrade'):
                parent.mkdir(parents=True);(parent/'package-manifest.json').write_text(json.dumps({'file':'synthetic.rpm','format':'rpm'}))
            (reports/'build-result.json').write_text('{}')
            def command(name,*args):
                (reports/'tls.json').write_text(json.dumps({'passed':False}))
                (reports/'package.json').write_text(json.dumps({'passed':True}))
            with patch.object(ci,'ROOT',root), patch.object(ci,'require_target',return_value='x64'), \
                 patch.object(ci,'require_isolated_root'), patch.object(ci,'python',side_effect=command), self.assertRaises(RuntimeError):
                ci.validate_target('fedora')
            self.assertFalse((reports/'result.json').exists())

    def test_distribution_workflow_is_manual_and_never_uploads_the_upgrade_fixture(self):
        text = (ci.ROOT/'.github/workflows/linux-distributions.yml').read_text()
        self.assertIn('  workflow_dispatch:', text)
        self.assertIn('  workflow_call:', text)
        self.assertNotRegex(text, r'(?m)^  (push|pull_request|pull_request_target):')
        self.assertIn('contents: write', text)
        self.assertNotIn('--privileged', text)
        self.assertNotIn('/var/run/docker.sock', text)
        self.assertNotIn('upload-artifact@', text)
        self.assertIn('ci_release.py upload --target linux-', text)
        self.assertNotIn('--directory .build/ci-', text)



if __name__ == '__main__':
    unittest.main(verbosity=2)
