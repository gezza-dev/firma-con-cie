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
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'cie-id-desktop'
APP_ID = 'it.giancarloezza.prototype.cie_flutter_prototype'
PREFIX = Path('opt/firma-con-cie')


def run(*args, cwd=None):
    return subprocess.run(list(map(str, args)), cwd=cwd, check=True,
                          capture_output=True, text=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(tree):
    return sorted(p for p in tree.rglob('*') if p.is_file())


def validate_bundle(bundle):
    if not bundle.is_dir() or set(p.name for p in bundle.iterdir()) != {
            'Firma con CIE', 'lib', 'data', 'cie_native', 'share'}:
        raise ValueError('Expected a complete Linux release bundle')
    for p in bundle.rglob('*'):
        mode = p.lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)) or mode & 0o7000:
            raise ValueError('Unsupported link, special file or permissions in bundle')
    native = bundle / 'cie_native'
    manifest = json.loads((native / 'backend-manifest.json').read_text())
    if not {'browser_setup/firefox_setup.py', 'browser_setup/libcie_browser_setup_guard.so'} <= set(manifest['files']):
        raise ValueError('Rebuild the runtime with the Firefox guided setup helper')
    if manifest['system'] != 'linux' or not manifest.get('linux_firefox_snap_core24_abi_verified'):
        raise ValueError('Use a Linux runtime with the Firefox Snap ABI check')
    for name, digest in manifest['files'].items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name:
            raise ValueError('Unsafe runtime manifest path')
        if sha(native / name) != digest:
            raise ValueError('Native runtime checksum mismatch: ' + name)
    actual = {p.relative_to(native).as_posix() for p in files(native)}
    if actual != set(manifest['files']) | {'backend-manifest.json'}:
        raise ValueError('Unmanifested native runtime file')
    for name in ('Firma con CIE', 'cie_native/cie_crl_fetch', 'cie_native/cie_card_observer'):
        if not os.access(bundle / name, os.X_OK):
            raise ValueError('Executable permission missing: ' + name)
    return manifest


def package(bundle, output, version):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+:~\-]*', version) or '~test' not in version:
        raise ValueError('Use an explicit Debian test version containing ~test')
    run('dpkg', '--validate-version', version)
    bundle, output = bundle.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(bundle):
        raise ValueError('Use a new output directory outside the input bundle')
    native_manifest = validate_bundle(bundle)
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
        app = stage / PREFIX
        shutil.copytree(bundle, app, ignore=shutil.ignore_patterns('tests', 'share'))
        packaged = dict(native_manifest)
        packaged['files'] = {k: v for k, v in native_manifest['files'].items()
                             if not k.startswith('tests/')}
        packaged['packaging'] = {'type': 'deb-local-test', 'testProgramsIncluded': False,
                                 'sourceManifestSha256': sha(bundle / 'cie_native/backend-manifest.json')}
        (app / 'cie_native/backend-manifest.json').write_text(json.dumps(packaged, indent=2) + '\n')
        bindir = stage / 'usr/bin'
        bindir.mkdir(parents=True)
        launcher = bindir / 'Firma con CIE'
        launcher.write_text('#!/bin/sh\nexec "/opt/firma-con-cie/Firma con CIE" "$@"\n')
        launcher.chmod(0o755)
        applications = stage / 'usr/share/applications'
        applications.mkdir(parents=True)
        desktop = applications / (APP_ID + '.desktop')
        text = (ROOT / 'assets/branding/linux' / desktop.name).read_text()
        text = text.replace('Exec="Firma con CIE"\n', 'Exec="/usr/bin/Firma con CIE"\n').replace('TryExec=Firma con CIE\n', 'TryExec=/usr/bin/Firma con CIE\n')
        desktop.write_text(text)
        run('desktop-file-validate', desktop)
        icons = stage / 'usr/share/icons/hicolor'
        shutil.copytree(ROOT / 'assets/branding/linux/hicolor', icons)
        doc = stage / 'usr/share/doc' / PACKAGE
        doc.mkdir(parents=True)
        shutil.copy2(ROOT / 'LICENSE', doc / 'copyright')
        shutil.copy2(ROOT / 'NOTICE.md', doc / 'NOTICE.md')
        for name in ('BUILDING.md', 'LINUX_PACKAGE.md', 'LINUX_FIREFOX.md', 'LINUX_FIREFOX_SETUP.md', 'LICENSING.md'):
            shutil.copy2(ROOT / 'docs' / name, doc / name)
        shutil.copy2(ROOT / 'docs/LINUX_CHROME.md', doc / 'LINUX_CHROME.md')
        (doc / 'tools').mkdir()
        shutil.copy2(ROOT / 'scripts/configure_chrome_linux.py', doc / 'tools/configure_chrome_linux.py')
        # These notices cover Flutter, PDFium, the icon and bundled native code.
        # The full dependency notice trees remain adjacent in cie_native/licenses.
        shutil.copy2(ROOT / 'assets/licenses/cie-app-icon-NOTICE.txt', doc / 'icon-NOTICE.txt')
        shutil.copy2(ROOT / 'assets/branding/LICENSE.txt', doc / 'icon-LICENSE.txt')
        # Normalize copied build-directory permissions; no setuid, writable
        # system files or user-specific caches are installed by this package.
        for p in stage.rglob('*'):
            p.chmod(0o755 if p.is_dir() or p.stat().st_mode & 0o111 else 0o644)
        # Analyze the installed layout, not build-tree paths; private unversioned
        # DSOs stay in this package. Missing system dependencies remain fatal.
        debian = temp / 'debian'
        debian.mkdir()
        (debian / 'control').write_text(
            f'Source: {PACKAGE}\n\nPackage: {PACKAGE}\nArchitecture: any\nDescription: Local test\n')
        elf_files = [p for p in files(app) if p.read_bytes()[:4] == b'\x7fELF']
        dependencies = run('dpkg-shlibdeps', '-O', '-S' + str(stage),
                           '-l' + str(app / 'lib'), '-l' + str(app / 'cie_native'),
                           *('-e' + str(p) for p in elf_files), cwd=temp)
        dep = next(s.removeprefix('shlibs:Depends=') for s in dependencies.stdout.splitlines()
                   if s.startswith('shlibs:Depends='))
        dep += ', pcscd, ca-certificates, python3, libnss3-tools'
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
            ' Firefox setup is user-initiated in the application; installation does not configure browsers.\n'
            ' Local test package; Linux DSS/LTA runtime is not included.\n')
        payload = {p.relative_to(stage).as_posix(): sha(p)
                   for p in files(stage) if 'DEBIAN' not in p.relative_to(stage).parts}
        (control / 'md5sums').write_text(''.join(
            hashlib.md5((stage / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in sorted(payload)))
        commit = run('git', 'rev-parse', 'HEAD', cwd=ROOT).stdout.strip()
        dirty = bool(run('git', 'status', '--porcelain', cwd=ROOT).stdout)
        environment = dict(os.environ)
        environment.setdefault('SOURCE_DATE_EPOCH', run('git', 'show', '-s', '--format=%ct',
                                                     'HEAD', cwd=ROOT).stdout.strip())
        output.mkdir(parents=True)
        target = output / f'{PACKAGE}_{version}_{arch}.deb'
        built = subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-z6',
                                '--threads-max=2', '--build', str(stage), str(target)],
                               env=environment, capture_output=True, text=True, check=True)
        metadata = {'package': PACKAGE, 'version': version, 'architecture': arch,
                    'file': target.name, 'sha256': sha(target), 'bytes': target.stat().st_size,
                    'baseCommit': commit, 'workingTreeModified': dirty,
                    'inputBundle': str(bundle), 'applicationPrefix': '/' + str(PREFIX),
                    'depends': dep, 'elfFilesChecked': len(elf_files),
                    'runtimeManifestVerified': True, 'testProgramsIncluded': False,
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
