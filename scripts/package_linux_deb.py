#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build a local-test .deb from a release bundle; never install or launch it.

Requires dpkg-dev, desktop-file-utils and binutils. All ELF dependencies are
computed with dpkg-shlibdeps, including the modules loaded dynamically by Dart.
No maintainer script changes a browser, user cache, Snap connection or service.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from linux_package_common import (ROOT, PACKAGE, PREFIX, run, sha, files,
                                  validate_bundle, stage_payload, source_revision, graphics_libraries)


def package(bundle, output, version):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+:~\-]*', version) or '~test' not in version:
        raise ValueError('Use an explicit Debian test version containing ~test')
    run('dpkg', '--validate-version', version)
    bundle, output = bundle.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(bundle):
        raise ValueError('Use a new output directory outside the input bundle')
    native_manifest = validate_bundle(bundle)
    graphics_libraries()
    arch = run('dpkg', '--print-architecture').stdout.strip()
    machines = {'amd64': 'Advanced Micro Devices X86-64', 'arm64': 'AArch64'}
    if arch not in machines:
        raise ValueError('Supported package architectures: amd64, arm64')
    elf_input = [p for p in files(bundle) if 'tests' not in p.relative_to(bundle).parts
                 and p.read_bytes()[:4] == b'\x7fELF']
    for elf in elf_input:
        header = run('readelf', '-h', elf).stdout
        if not re.search(r'Machine:\s*' + re.escape(machines[arch]) + r'\s*$', header, re.M):
            raise ValueError('ELF architecture differs from package architecture')
    # Keep the tested Snap ABI as a prerequisite, without initializing PKCS#11.
    run('python3', ROOT / 'scripts/check_linux_firefox_abi.py',
        *(bundle / 'cie_native' / n for n in
          ('libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so')))
    work = ROOT / '.build/linux-deb'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='package-', dir=work) as temp:
        temp = Path(temp)
        stage = temp / PACKAGE
        control = stage / 'DEBIAN'
        control.mkdir(parents=True)
        stage_payload(bundle, stage, native_manifest)
        app = stage / PREFIX
        # Analyze the installed layout, not build-tree paths; private unversioned
        # DSOs stay in this package. Missing system dependencies remain fatal.
        debian = temp / 'debian'
        debian.mkdir()
        (debian / 'control').write_text(
            f'Source: {PACKAGE}\n\nPackage: {PACKAGE}\nArchitecture: any\nDescription: Local test\n')
        elf_files = [p for p in files(app) if p.read_bytes()[:4] == b'\x7fELF']
        private_library_dirs = sorted({p.parent for p in elf_files if '.so' in p.name})
        dependencies = run('dpkg-shlibdeps', '-O', '-S' + str(stage),
                           '-l' + str(app / 'lib'), '-l' + str(app / 'cie_native'),
                           *('-l' + str(p) for p in private_library_dirs),
                           *('-e' + str(p) for p in elf_files), cwd=temp)
        dep = next(s.removeprefix('shlibs:Depends=') for s in dependencies.stdout.splitlines()
                   if s.startswith('shlibs:Depends='))
        dep += ', libegl1, libgl1, libgles2, pcscd, ca-certificates, python3, libnss3-tools'
        installed_size = sum((p.stat().st_size + 1023) // 1024 for p in files(stage))
        (control / 'control').write_text(
            f'Package: {PACKAGE}\nVersion: {version}\nArchitecture: {arch}\n'
            'Maintainer: Gian Carlo Ezza <61827135+gezza-dev@users.noreply.github.com>\n'
            f'Installed-Size: {installed_size}\nDepends: {dep}\nRecommends: libccid\n'
            'Section: utils\nPriority: optional\n'
            'Homepage: https://github.com/gezza-dev/cie-id-desktop\n'
            'Description: Firma con CIE - local Linux test build\n'
            ' Independent desktop application for Italian CIE cards and document signing.\n'
            ' Includes the full-PIN Firefox/desktop Chrome PKCS#11 provider.\n'
            ' Firefox setup is user-initiated in the application; installation does not configure browsers.\n' +
            (' Includes local DSS/LTA validation with a private Java runtime.\n'
             if native_manifest.get('ltv') else
             ' Local test package; Linux DSS/LTA runtime is not included.\n'))
        payload = {p.relative_to(stage).as_posix(): sha(p)
                   for p in files(stage) if 'DEBIAN' not in p.relative_to(stage).parts}
        (control / 'md5sums').write_text(''.join(
            hashlib.md5((stage / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in sorted(payload)))
        revision = source_revision()
        commit = revision['baseCommit']
        dirty = revision['workingTreeModified']
        environment = dict(os.environ)
        environment.setdefault('SOURCE_DATE_EPOCH', str(revision['sourceDateEpoch']))
        output.mkdir(parents=True)
        target = output / f'{PACKAGE}_{version}_{arch}.deb'
        built = subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-z6',
                                '--threads-max=2', '--build', str(stage), str(target)],
                               env=environment, capture_output=True, text=True, check=True)
        metadata = {'package': PACKAGE, 'version': version, 'architecture': arch,
                    'file': target.name, 'sha256': sha(target), 'bytes': target.stat().st_size,
                    'baseCommit': commit, 'workingTreeModified': dirty,
                    'sourceSnapshotSha256': revision.get('sourceSnapshotSha256'),
                    'sourceDateEpoch': revision['sourceDateEpoch'],
                    'inputBundle': str(bundle), 'applicationPrefix': '/' + str(PREFIX),
                    'depends': dep, 'elfFilesChecked': len(elf_files),
                    'runtimeManifestVerified': True, 'testProgramsIncluded': False,
                    'ltvIncluded': bool(native_manifest.get('ltv')),
                    'appLaunched': False, 'cardTestsRun': False,
                    'browserConfigurationModified': False, 'snapPermissionsModified': False,
                    'files': payload}
        (output / 'package-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
        (output / 'SHA256SUMS').write_text(metadata['sha256'] + '  ' + target.name + '\n')
        shutil.copy2(ROOT / 'docs/LINUX_PACKAGE.md', output / 'LEGGIMI.md')
        (output / 'dependency-scan.log').write_text(dependencies.stdout + dependencies.stderr)
        print(built.stdout.strip())
        print(json.dumps({k: v for k, v in metadata.items() if k != 'files'}, indent=2))
        return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True, help='Debian version containing ~test')
    args = parser.parse_args()
    package(args.bundle, args.output, args.version)


if __name__ == '__main__':
    main()
