#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Native Fedora/Arch x86_64 test packages from a validated Linux bundle.

Run inside the destination distribution. Never installs packages, runs the GUI,
loads PKCS#11 or connects to PC/SC. No application-specific install scriptlets.
"""
import argparse
import gzip
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

from linux_package_common import (ROOT, PACKAGE, PREFIX, files, run, sha,
                                  source_revision, stage_payload, validate_bundle, graphics_libraries, GRAPHICS_SONAMES)


def elf_files(stage):
    result = [p for p in files(stage) if p.read_bytes()[:4] == b'\x7fELF']
    for path in result:
        if not re.search(r'Machine:\s+Advanced Micro Devices X86-64\s*$',
                         run('readelf', '-h', path).stdout, re.M):
            raise ValueError('Expected x86_64 ELF: ' + str(path))
    return result


def target_libraries(stage, elfs):
    """Resolve every ELF against the guest distribution, including private JNI."""
    directories = sorted({str(p.parent) for p in elfs if '.so' in p.name})
    environment = dict(os.environ, LD_LIBRARY_PATH=os.pathsep.join(directories))
    system = graphics_libraries()
    for path in elfs:
        result = subprocess.run(['ldd', str(path)], env=environment, text=True,
                                capture_output=True, check=True)
        if 'not found' in result.stdout + result.stderr:
            raise ValueError('Unresolved target ABI: ' + str(path) + '\n' + result.stdout)
        for line in result.stdout.splitlines():
            match = re.search(r'(?:=>\s+|^\s*)(/\S+)\s+\(', line)
            if match:
                dependency = Path(match[1]).resolve()
                if not dependency.is_relative_to(stage):
                    system.add(str(dependency))
    return system


def payload_tar(stage, path, epoch):
    def normalized(info):
        info.uid = info.gid = 0
        info.uname = info.gname = 'root'
        info.mtime = epoch
        return info
    with path.open('wb') as out, gzip.GzipFile(fileobj=out, filename='', mode='wb',
                                              mtime=epoch, compresslevel=1) as zipped:
        with tarfile.open(fileobj=zipped, mode='w|') as archive:
            for name in ('opt', 'usr'):
                archive.add(stage / name, arcname=name, filter=normalized)


def rpm_package(stage, elfs, inputs, output, version, release, epoch):
    configdir = run('rpm', '-E', '%{_rpmconfigdir}').stdout.strip()
    raw = run(Path(configdir) / 'rpmdeps', '--requires', *elfs).stdout.splitlines()
    private_names = {p.name for p in elfs}
    requires = sorted({r.strip() for r in raw if r.strip()
                       and r.split('(', 1)[0] not in private_names}
                      | {'/bin/sh', 'pcsc-lite', 'python3', 'nss-tools', 'ca-certificates'}
                      | {name + '()(64bit)' for name in GRAPHICS_SONAMES})
    top = inputs / 'rpmbuild'
    for name in ('SOURCES', 'SPECS', 'BUILD', 'BUILDROOT', 'RPMS', 'SRPMS'):
        (top / name).mkdir(parents=True)
    shutil.copy2(inputs / 'payload.tar.gz', top / 'SOURCES/payload.tar.gz')
    owned = [p for p in stage.rglob('*') if p.is_dir() and
             (p.is_relative_to(stage / PREFIX) or
              p.is_relative_to(stage / 'usr/share/doc' / PACKAGE) or
              p.is_relative_to(stage / 'usr/share/licenses' / PACKAGE))]
    def quoted(p):
        name = '/' + p.relative_to(stage).as_posix()
        if any(c in name for c in '\n\r"%'):
            raise ValueError('Unsupported RPM payload filename')
        return '"' + name + '"'
    (top / 'SOURCES/files.list').write_text('\n'.join(
        ['%dir ' + quoted(p) for p in sorted(owned)] +
        [('%license ' if p.is_relative_to(stage / 'usr/share/licenses' / PACKAGE) else '') + quoted(p) for p in files(stage)]) + '\n')
    spec = f'''# Generated local test recipe; runtime provenance is in package-manifest.json.
%global debug_package %{{nil}}
%global __debug_install_post %{{nil}}
%global __os_install_post %{{nil}}
%global _build_id_links none
Name: {PACKAGE}
Version: {version}
Release: {release}
Summary: Firma con CIE - local Linux test build
License: LicenseRef-FirmaConCIE-Bundled
URL: https://github.com/gezza-dev/cie-id-desktop
Source0: payload.tar.gz
Source1: files.list
BuildArch: x86_64
AutoReqProv: no
Requires: {', '.join(requires)}
Recommends: pcsc-lite-ccid

%description
Independent CIE application with a private native/DSS runtime. Bundled license
texts are included. Browser setup is explicitly initiated by the user in Home.
This test recipe is not a submission to the Fedora package repositories.

%prep
%setup -q -c -T
tar -xzf %{{SOURCE0}}

%install
mkdir -p "%{{buildroot}}"
cp -a opt usr "%{{buildroot}}/"

%files -f %{{SOURCE1}}
'''
    specpath = top / ('SPECS/' + PACKAGE + '.spec')
    specpath.write_text(spec)
    run('rpmbuild', '-bb', '--define', '_topdir ' + str(top), '--define', '_smp_mflags -j2',
        '--define', '_smp_build_ncpus 2', '--define', '_binary_payload w6.xzdio', specpath)
    built, = (top / 'RPMS/x86_64').glob('*.rpm')
    target = output / built.name
    shutil.copy2(built, target)
    shutil.copy2(specpath, output / (PACKAGE + '.spec'))
    (output / 'requires.txt').write_text('\n'.join(requires) + '\n')
    return target, version + '-' + release


def arch_package(stage, system_libraries, inputs, output, version, pkgrel):
    owners = {run('pacman', '-Qoq', path).stdout.strip() for path in system_libraries}
    depends = sorted(owners | {'bash', 'pcsclite', 'python', 'nss', 'ca-certificates'})
    # Source tar is generated from the verified bundle. makepkg verifies its
    # checksum, metadata and dependencies, then fakeroot records root ownership.
    recipe = f'''# Generated native local-test recipe; no install script or browser hooks.
pkgname={PACKAGE}
pkgver={version}
pkgrel={pkgrel}
pkgdesc='Firma con CIE - local Linux test build'
arch=('x86_64')
url='https://github.com/gezza-dev/cie-id-desktop'
license=('LicenseRef-FirmaConCIE-Bundled')
depends=({' '.join(repr(n) for n in depends)})
optdepends=('ccid: CCID smart card reader driver')
options=('!strip' '!debug' '!buildflags')
source=('payload.tar.gz')
sha256sums=('{sha(inputs / 'payload.tar.gz')}')

package() {{
    cp -a --no-preserve=ownership "$srcdir/opt" "$srcdir/usr" "$pkgdir/"
}}
'''
    (inputs / 'PKGBUILD').write_text(recipe)
    if os.geteuid() == 0:
        raise ValueError('Run Arch packaging as an ordinary user inside the isolated build root')
    config = inputs / 'makepkg.conf'
    config.write_text('source /etc/makepkg.conf\nCOMPRESSZST=(zstd -c -T2 -10 -)\nMAKEFLAGS=-j2\n')
    run('makepkg', '--config', config, '--cleanbuild', '--noconfirm', cwd=inputs)
    built, = inputs.glob('*.pkg.tar.zst')
    target = output / built.name
    shutil.copy2(built, target)
    shutil.copy2(inputs / 'PKGBUILD', output / 'PKGBUILD')
    (output / 'requires.txt').write_text('\n'.join(depends) + '\n')
    return target, version + '-' + pkgrel


def package(bundle, output, kind, test_version, pkgrel='1'):
    match = re.fullmatch(r'(\d[\d.]*)~test(\d{8}\.\d+)', test_version)
    if not match or not re.fullmatch(r'[1-9]\d*(?:\.\d+)?', pkgrel):
        raise ValueError('Explicit ~testYYYYMMDD.N version and numeric Arch pkgrel required')
    bundle, output = bundle.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(bundle):
        raise ValueError('Use a new output directory outside the bundle')
    osrelease = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines()
                     if '=' in line)
    expected = 'fedora' if kind == 'rpm' else 'arch'
    if osrelease.get('ID', '').strip('"') != expected:
        raise ValueError('Build this package inside the ' + expected + ' environment')
    native = validate_bundle(bundle)
    revision = source_revision()
    work = ROOT / ('.build/package-' + kind)
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as directory:
        temp = Path(directory)
        stage, inputs = temp / 'stage', temp / 'inputs'
        inputs.mkdir()
        stage_payload(bundle, stage, native, package_type=kind)
        elfs = elf_files(stage)
        system = target_libraries(stage, elfs)
        payload = {p.relative_to(stage).as_posix(): sha(p) for p in files(stage)}
        payload_tar(stage, inputs / 'payload.tar.gz', revision['sourceDateEpoch'])
        output.mkdir(parents=True)
        if kind == 'rpm':
            release = '0.test' + match[2] + '.fc' + osrelease['VERSION_ID'].strip('"')
            target, version = rpm_package(stage, elfs, inputs, output, match[1], release,
                                          revision['sourceDateEpoch'])
        else:
            target, version = arch_package(stage, system, inputs, output,
                                            match[1] + '_test' + match[2], pkgrel)
        manifest = dict(revision, package=PACKAGE, version=version, architecture='x86_64',
                        format=kind, targetDistribution=expected, file=target.name,
                        sha256=sha(target), bytes=target.stat().st_size,
                        inputBundle=str(bundle), applicationPrefix='/' + str(PREFIX),
                        elfFilesChecked=len(elfs), runtimeManifestVerified=True,
                        testProgramsIncluded=False, ltvIncluded=bool(native.get('ltv')),
                        appLaunched=False, cardTestsRun=False, browserConfigurationModified=False,
                        snapPermissionsModified=False, files=payload)
        (output / 'package-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (output / 'SHA256SUMS').write_text(manifest['sha256'] + '  ' + target.name + '\n')
        print(json.dumps({k: v for k, v in manifest.items() if k != 'files'}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--format', choices=['rpm', 'arch'], required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--pkgrel', default='1')
    args = parser.parse_args()
    package(args.bundle, args.output, args.format, args.version, args.pkgrel)
