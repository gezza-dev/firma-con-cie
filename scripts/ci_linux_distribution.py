#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Manual Fedora/Arch CI, retaining the audited core24 native browser ABI."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import tarfile

from ci_desktop_common import (ROOT, download, flutter_checks, host_architecture,
                               java_tools, python, receipt, run, sha, source_commit)
from product_identity import application_version
from test_linux_distribution_package import require_isolated_root


def matrices(distribution):
    if distribution not in ('all', 'fedora', 'arch'):
        raise ValueError('Unsupported distribution selection')
    targets = []
    if distribution in ('all', 'fedora'):
        targets += [dict(distribution='fedora', architecture='x64', runner='ubuntu-24.04'),
                    dict(distribution='fedora', architecture='arm64', runner='ubuntu-24.04-arm')]
    if distribution in ('all', 'arch'):
        targets += [dict(distribution='arch', architecture='x64', runner='ubuntu-24.04')]
    runtimes = {t['architecture']:dict(architecture=t['architecture'], runner=t['runner']) for t in targets}
    return {'runtime': {'include': list(runtimes.values())}, 'package': {'include': targets}}


def require_linux_builder():
    if platform.system() != 'Linux' or os.geteuid() == 0:
        raise RuntimeError('Compile only as an ordinary user inside the Linux CI image')


def require_target(distribution):
    architecture = host_architecture()
    if distribution not in ('fedora', 'arch') or (distribution == 'arch' and architecture != 'x64'):
        raise ValueError('Unsupported distribution/architecture')
    release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
    if release.get('ID', '').strip('"') != distribution:
        raise ValueError('Use the requested destination distribution container')
    return architecture


def require_tools(distribution):
    tools = ['git', 'curl', 'unzip', 'xz', 'tar', 'gzip', 'which', 'clang', 'clang++', 'cmake',
             'ninja', 'pkg-config', 'patchelf', 'readelf', 'ldd', 'Xvfb', 'bwrap',
             'desktop-file-validate', 'gresource']
    tools += ['rpm', 'rpmbuild'] if distribution == 'fedora' else ['pacman', 'makepkg', 'bsdtar']
    missing = [tool for tool in tools if not shutil.which(tool)]
    if missing:
        raise RuntimeError('Missing distribution build tools: '+', '.join(missing))
    run('pkg-config', '--exists', 'gtk+-3.0', 'libpcsclite')


def runtime_paths():
    architecture = host_architecture()
    return (ROOT/'.build/ci-distribution-runtime', ROOT/'native/runtime/linux',
            ROOT/('reports/linux-distribution-runtime-'+architecture))


def build_runtime():
    require_linux_builder()
    work, runtime, reports = runtime_paths()
    reports.mkdir(parents=True)
    python('test_linux_distribution_ci.py')
    cpu = 'aarch64' if host_architecture() == 'arm64' else 'x86_64'
    python('build_portable_dependencies.py', '--arch', cpu, '--jobs', '2')
    base = work/'native-base'
    python('build_native.py', '--system', 'linux', '--jobs', '2',
           '--dependency-prefix', ROOT/('.build/dependencies/linux-'+cpu+'/prefix'),
           '--build-dir', work/'native-build', '--output', base)
    java, maven, cache = java_tools('linux', 'arm64' if cpu == 'aarch64' else cpu, work)
    python('build_ltv.py', '--system', 'linux', '--architecture', cpu, '--java-home', java,
           '--maven', maven, '--base-runtime', base, '--output', runtime, '--tools-cache', cache)
    python('smoke_native.py', '--runtime', runtime, '--report', reports/'native.json')
    python('test_ltv.py', '--runtime', runtime, '--report', reports/'ltv.json')
    receipt(reports/'build-result.json', 'linux', host_architecture(), [],
            softwareChecksPassed=False, tlsChecksPending=True)


def finish_runtime():
    work, runtime, reports = runtime_paths()
    if (platform.system() != 'Linux' or os.geteuid() != 0 or not Path('/.dockerenv').is_file()
            or not Path('/work/.cie-appimage-isolated-root').is_file()):
        raise RuntimeError('Use the disposable runtime test container')
    python('test_linux_tls_runtime.py', '--client', runtime/'tests/cie_network_test_client',
           '--report', reports/'tls.json', '--no-user-namespace')
    if not json.loads((reports/'tls.json').read_text())['passed']:
        raise RuntimeError('Native TLS regression failed')
    output = ROOT/('dist/linux-distribution-runtime-'+host_architecture())
    output.mkdir(parents=True)
    archive = output/'runtime.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(runtime, arcname='runtime')
    # Complete the receipt recorded by the ordinary builder. Root must not run
    # Git against another user's checkout or change Git's ownership safeguards.
    result = json.loads((reports/'build-result.json').read_text())
    if result['architecture'] != host_architecture():
        raise ValueError('Runtime build receipt architecture mismatch')
    result.update(artifacts={archive.relative_to(ROOT).as_posix():sha(archive)},
                  softwareChecksPassed=True, tlsChecksPending=False, nativeTlsChecksPassed=True,
                  nativeBuildDistribution='Ubuntu 24.04', nativeManifestSha256=sha(runtime/'backend-manifest.json'))
    (output/'runtime-source.json').write_text(json.dumps(result, indent=2)+'\n')


def extract_runtime(archive, metadata, destination, architecture):
    data = json.loads(metadata.read_text())
    if (data['sourceCommit'] != source_commit() or data['architecture'] != architecture
            or not data['softwareChecksPassed'] or not data['nativeTlsChecksPassed']):
        raise ValueError('Runtime provenance or architecture differs from the current build')
    if list(data['artifacts'].values()) != [sha(archive)]:
        raise ValueError('Runtime archive checksum mismatch')
    if destination.exists():
        raise ValueError('Use a fresh runtime extraction directory')
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        if sum(m.size for m in members) > 3*1024**3:
            raise ValueError('Unexpected runtime archive size')
        for member in members:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'runtime'
                    or '\\' in member.name or ':' in member.name
                    or not (member.isfile() or member.isdir()) or member.mode & 0o7000):
                raise ValueError('Unsafe runtime archive member')
        tar.extractall(destination, filter='data')
    runtime = destination/'runtime'
    if sha(runtime/'backend-manifest.json') != data['nativeManifestSha256']:
        raise ValueError('Native manifest checksum mismatch')
    manifest = json.loads((runtime/'backend-manifest.json').read_text())
    for name, digest in manifest['source_files'].items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or not relative.parts or relative.parts[0] not in ('native', 'scripts'):
            raise ValueError('Unsafe native source provenance')
        if sha(ROOT/name) != digest:
            raise ValueError('Native source provenance mismatch: '+name)
    return runtime


def build_target(distribution, runtime_input):
    require_linux_builder()
    architecture = require_target(distribution)
    require_tools(distribution)
    work = ROOT/('.build/ci-'+distribution)
    work.mkdir(parents=True)
    reports = ROOT/('reports/linux-'+distribution+'-'+architecture)
    reports.mkdir(parents=True)
    for name in ('test_linux_distribution_ci.py', 'test_linux_packaging.py', 'test_ltv_runtime.py'):
        python(name)
    runtime = extract_runtime(runtime_input/'runtime.tar.gz', runtime_input/'runtime-source.json', work/'input', architecture)
    shutil.copytree(runtime, ROOT/'native/runtime/linux')
    shutil.copy2(runtime_input/'runtime-source.json', reports/'runtime-source.json')
    shutil.copy2('/work/ci-system-packages.txt', reports/'system-packages.txt')
    python('smoke_native.py', '--runtime', runtime, '--report', reports/'native.json')
    python('test_ltv.py', '--runtime', runtime, '--report', reports/'ltv.json')
    flutter_checks()
    os.environ['CMAKE_BUILD_PARALLEL_LEVEL'] = '2'
    run('flutter', '--suppress-analytics', 'build', 'linux', '--release', '--no-pub')
    bundle = ROOT/('build/linux/'+architecture+'/release/bundle')
    # Verify the downloaded PDFium against the CPU-matched publisher lock.
    item = json.loads((ROOT/'native/preview/pdfium.lock.json').read_text())['artifacts']['linux-'+architecture]
    import hashlib
    with tarfile.open(download(item, work/'downloads')) as tar:
        member = next(m for m in tar.getmembers() if m.name.lstrip('./') == 'lib/libpdfium.so')
        if hashlib.sha256(tar.extractfile(member).read()).hexdigest() != sha(bundle/'lib/libpdfium.so'):
            raise ValueError('PDFium differs from the architecture-matched publisher lock')
    kind = 'rpm' if distribution == 'fedora' else 'arch'
    output = ROOT/('dist/linux-'+distribution+'-'+architecture)
    for destination, release in ((output, '1'), (work/'upgrade', '2')):
        python('package_linux_distribution.py', '--format', kind, '--bundle', bundle,
               '--output', destination, '--version', application_version(), '--pkgrel', release)
    shutil.copy2(ROOT/'docs/LINUX_DISTRIBUTION_PACKAGES.md', output/'LEGGIMI.md')
    manifest = json.loads((output/'package-manifest.json').read_text())
    receipt(reports/'build-result.json', 'linux', architecture, [output/manifest['file']],
            distribution=distribution, packageFormat=kind, nativeBuildDistribution='Ubuntu 24.04',
            softwareChecksPassed=False, tlsChecksPending=True, lifecycleChecksPending=True)


def validate_target(distribution):
    architecture = require_target(distribution)
    require_isolated_root(container=True)
    work = ROOT/('.build/ci-'+distribution)
    runtime = ROOT/'native/runtime/linux'
    reports = ROOT/('reports/linux-'+distribution+'-'+architecture)
    python('test_linux_tls_runtime.py', '--client', runtime/'tests/cie_network_test_client',
           '--report', reports/'tls.json', '--no-user-namespace')
    output = ROOT/('dist/linux-'+distribution+'-'+architecture)
    manifest = json.loads((output/'package-manifest.json').read_text())
    upgrade = json.loads((work/'upgrade/package-manifest.json').read_text())
    python('test_linux_distribution_package.py', output/manifest['file'],
           '--upgrade-package', work/'upgrade'/upgrade['file'], '--format', manifest['format'],
           '--no-card-guard', runtime/'browser_setup/libcie_browser_setup_guard.so',
           '--report', reports/'package.json', '--container-root')
    for name in ('tls', 'package'):
        if not json.loads((reports/(name+'.json')).read_text())['passed']:
            raise RuntimeError('Distribution validation failed: '+name)
    result = json.loads((reports/'build-result.json').read_text())
    result.update(softwareChecksPassed=True, tlsChecksPending=False, lifecycleChecksPending=False,
                  nativeTlsChecksPassed=True, packageLifecycleChecksPassed=True)
    (reports/'result.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['matrix', 'runtime', 'runtime-tls', 'build', 'validate'])
    parser.add_argument('--distribution', choices=['all', 'fedora', 'arch'])
    parser.add_argument('--runtime-input', type=Path)
    args = parser.parse_args()
    if args.action == 'matrix':
        result = matrices(args.distribution)
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            for name, value in result.items():
                output.write(name+'='+json.dumps(value, separators=(',', ':'))+'\n')
    elif args.action == 'runtime':
        build_runtime()
    elif args.action == 'runtime-tls':
        finish_runtime()
    elif not args.distribution or (args.action == 'build' and not args.runtime_input):
        parser.error('Destination distribution and runtime input are required')
    elif args.action == 'build':
        build_target(args.distribution, args.runtime_input.resolve())
    else:
        validate_target(args.distribution)
