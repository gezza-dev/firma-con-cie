#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Packaging boundary tests with synthetic bytes; no native code is loaded."""
import json
import os
import threading
import time
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import linux_package_common as common
import package_linux_distribution as distribution
from test_linux_distribution_package import manager, read_xvfb_display


class PackageBoundaries(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'bundle'
        self.bundle.mkdir()
        for name in ['lib', 'data', 'share', 'cie_native']:
            (self.bundle / name).mkdir()
        self.native = self.bundle / 'cie_native'
        names = ['browser_setup/firefox_setup.py', 'browser_setup/chrome_setup.py',
                 'browser_setup/libcie_browser_setup_guard.so', 'cie_card_observer',
                 'cie_crl_fetch', 'tests/synthetic-test']
        for name in names:
            p = self.native / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('synthetic bytes only: ' + name)
            p.chmod(0o755)
        (self.bundle / 'Firma con CIE').write_text('synthetic application')
        (self.bundle / 'Firma con CIE').chmod(0o755)
        self.manifest = {'system': 'linux', 'linux_firefox_snap_core24_abi_verified': True,
                         'files': {n: common.sha(self.native / n) for n in names}}
        self.save()

    def save(self):
        (self.native / 'backend-manifest.json').write_text(json.dumps(self.manifest))

    def test_corrupt_runtime_rejected(self):
        (self.native / 'cie_card_observer').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            common.validate_bundle(self.bundle)

    def test_arm64_elf_cannot_be_packaged_as_x86_64(self):
        elf = self.bundle / 'lib/synthetic.so'
        elf.write_bytes(b'\x7fELFsynthetic')
        with patch.object(distribution, 'run', return_value=SimpleNamespace(stdout='Machine: AArch64\n')):
            self.assertEqual(distribution.elf_files(self.bundle, 'arm64'), [elf])
            with self.assertRaisesRegex(ValueError, 'Expected x86_64 ELF'):
                distribution.elf_files(self.bundle)

    def test_x86_64_elf_cannot_be_packaged_as_arm64(self):
        elf = self.bundle / 'lib/synthetic.so'
        elf.write_bytes(b'\x7fELFsynthetic')
        with patch.object(distribution, 'run', return_value=SimpleNamespace(stdout='Machine: Advanced Micro Devices X86-64\n')):
            self.assertEqual(distribution.elf_files(self.bundle), [elf])
            with self.assertRaisesRegex(ValueError, 'Expected arm64 ELF'):
                distribution.elf_files(self.bundle, 'arm64')

    def test_arm64_bundle_rejects_x86_64_private_jvm(self):
        self.manifest['ltv'] = {'architectures': ['linux-x86_64']}
        self.save()
        with patch('ltv_runtime.platform.machine', return_value='aarch64'):
            with self.assertRaisesRegex(ValueError, 'DSS JVM architecture differs'):
                common.validate_bundle(self.bundle)

    def test_unmanifested_runtime_rejected(self):
        (self.native / 'unexpected').touch()
        with self.assertRaisesRegex(ValueError, 'Unmanifested'):
            common.validate_bundle(self.bundle)

    def test_traversal_and_absolute_manifest_names_rejected(self):
        originals = dict(self.manifest['files'])
        for name in ['../escape', '/absolute']:
            with self.subTest(name=name):
                self.manifest['files'] = dict(originals, **{name: 'invalid'})
                self.save()
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    common.validate_bundle(self.bundle)

    def test_symlink_and_privileged_file_rejected(self):
        p = self.bundle / 'lib/unsafe'
        p.symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            common.validate_bundle(self.bundle)
        p.unlink()
        p.write_text('synthetic'); p.chmod(0o4755)
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            common.validate_bundle(self.bundle)

    def test_missing_executable_rejected(self):
        (self.bundle / 'Firma con CIE').chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'Executable permission'):
            common.validate_bundle(self.bundle)

    def test_dependency_sources_are_separate_without_removing_runtime_or_notices(self):
        names = ['licenses/ltv/dependency-sources/upstream-sources.jar',
                 'licenses/ltv/upstream-LICENSE.txt', 'ltv/lib/upstream.jar']
        for name in names:
            path = self.native / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic upstream material: ' + name)
            self.manifest['files'][name] = common.sha(path)
        self.save()
        manifest = common.validate_bundle(self.bundle)
        for kind in ['deb', 'rpm', 'arch', 'appimage']:
            with self.subTest(kind=kind):
                stage = self.root / kind
                common.stage_payload(self.bundle, stage, manifest, kind)
                native = stage / common.PREFIX / 'cie_native'
                packaged = json.loads((native / 'backend-manifest.json').read_text())
                self.assertFalse((native / 'licenses/ltv/dependency-sources').exists())
                self.assertNotIn(names[0], packaged['files'])
                for name in names[1:]:
                    self.assertEqual(common.sha(native / name), self.manifest['files'][name])
                    self.assertIn(name, packaged['files'])
                self.assertFalse(packaged['packaging']['dependencySourceJarsIncluded'])
                self.assertEqual(common.sha(self.native / names[0]),
                                 self.manifest['files'][names[0]])

    def test_staging_excludes_tests_and_preserves_format_provenance(self):
        manifest = common.validate_bundle(self.bundle)
        for kind in ['deb', 'rpm', 'arch']:
            with self.subTest(kind=kind):
                stage = self.root / kind
                common.stage_payload(self.bundle, stage, manifest, kind)
                native = stage / common.PREFIX / 'cie_native'
                self.assertFalse((native / 'tests').exists())
                packaged = json.loads((native / 'backend-manifest.json').read_text())
                self.assertEqual(packaged['packaging']['type'], kind)
                self.assertNotIn('tests/synthetic-test', packaged['files'])
                self.assertEqual((stage / 'usr/bin/Firma con CIE').read_text(),
                                 '#!/bin/sh\nexec "/opt/firma-con-cie/Firma con CIE" "$@"\n')
                self.assertTrue((stage / 'usr/share/doc/firma-con-cie/BUILDING.md').is_file())
                self.assertEqual((stage / 'usr/share/doc/firma-con-cie/AUTOMATIC_BROWSER_SETUP.md').read_bytes(),
                                 (common.ROOT / 'docs/AUTOMATIC_BROWSER_SETUP.md').read_bytes())
                self.assertFalse(list(stage.glob('**/postinst')))

    def test_release_version_is_mandatory_before_creating_output(self):
        for version in ['', '1.0', 'v1.0.0', '01.0.0', '1.0.0~test20261025.1', '1.0.0/../../bad', '1.0.0;bad']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                distribution.package(self.bundle, self.root / 'out', 'rpm', version)
        self.assertFalse((self.root / 'out').exists())

    def test_current_project_notice_replaces_stale_bundled_copy_only(self):
        name = 'licenses/prototype-NOTICE.md'
        original = self.native / name
        original.parent.mkdir()
        original.write_text('outdated project notice')
        upstream = self.native / 'licenses/upstream-NOTICE.txt'
        upstream.write_text('upstream attribution - preserve exactly')
        for path in [original, upstream]:
            self.manifest['files'][path.relative_to(self.native).as_posix()] = common.sha(path)
        self.save()
        source_hash = common.sha(self.native / 'backend-manifest.json')
        stage = self.root / 'fresh-notice'
        common.stage_payload(self.bundle, stage, self.manifest)
        packaged = stage / common.PREFIX / 'cie_native'
        manifest = json.loads((packaged/'backend-manifest.json').read_text())
        self.assertEqual((packaged/name).read_bytes(), (common.ROOT/'NOTICE.md').read_bytes())
        self.assertEqual(manifest['files'][name], common.sha(packaged/name))
        self.assertEqual(manifest['packaging']['sourceManifestSha256'], source_hash)
        self.assertEqual((packaged/'licenses/upstream-NOTICE.txt').read_bytes(), upstream.read_bytes())
        self.assertEqual(original.read_text(), 'outdated project notice')

    def test_existing_or_nested_output_rejected(self):
        for output in [self.bundle / 'output', self.root]:
            with self.subTest(output=output), self.assertRaises(ValueError):
                distribution.package(self.bundle, output, 'arch', '1.0.0')

    def test_missing_dlopen_graphics_library_rejected(self):
        with patch.object(common, 'run', return_value=SimpleNamespace(stdout='')), \
             self.assertRaisesRegex(ValueError, 'Missing dynamic graphics'):
            common.graphics_libraries()

    def test_lifecycle_guard_refuses_host(self):
        with patch('test_linux_distribution_package.run') as command, \
             self.assertRaisesRegex(RuntimeError, 'Refusing installation'):
            manager('deb', 'install', self.root / 'synthetic.deb')
        command.assert_not_called()

    def test_exported_revision_validated(self):
        receipt = self.root / '.linux-package-source.json'
        receipt.write_text(json.dumps({'baseCommit': 'invalid'}))
        with patch.object(common, 'ROOT', self.root), self.assertRaises(ValueError):
            common.source_revision()


class HeadlessHarness(unittest.TestCase):
    def test_display_handshake_waits_for_newline_before_closing_pipe(self):
        readfd, writefd = os.pipe()
        errors = []
        def writer():
            try:
                os.write(writefd, b'23')
                time.sleep(0.025)
                os.write(writefd, b'\n')
            except OSError as exc:
                errors.append(exc)
            finally:
                os.close(writefd)
        thread = threading.Thread(target=writer)
        thread.start()
        self.assertEqual(read_xvfb_display(readfd, timeout=2), ':23')
        thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
