#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build native Linux packages inside fresh, architecture-matched CI containers."""
import argparse
import json
import os
from pathlib import Path
import platform
import tarfile

from ci_desktop_common import (ROOT, download, flutter_checks, host_architecture,
                               java_tools, python, receipt, run, sha)
from product_identity import application_version


def build(kind):
    if platform.system() != 'Linux':
        raise ValueError('Linux CI requires Linux')
    architecture = host_architecture()
    cpu = 'aarch64' if architecture == 'arm64' else 'x86_64'
    work = ROOT/('.build/ci-linux-'+kind)
    work.mkdir(parents=True)
    reports = ROOT/('reports/linux-'+architecture+'-'+kind)
    reports.mkdir(parents=True)
    python('build_portable_dependencies.py', '--arch', cpu, '--jobs', '2')
    base = work/'native-base'
    python('build_native.py', '--system', 'linux', '--jobs', '2',
           '--dependency-prefix', ROOT/('.build/dependencies/linux-'+cpu+'/prefix'),
           '--build-dir', work/'native-build', '--output', base)
    java, maven, cache = java_tools('linux', 'arm64' if architecture == 'arm64' else 'x86_64', work)
    runtime = ROOT/'native/runtime/linux'
    python('build_ltv.py', '--system', 'linux', '--architecture', cpu,
           '--java-home', java, '--maven', maven, '--base-runtime', base,
           '--output', runtime, '--tools-cache', cache)
    python('smoke_native.py', '--runtime', runtime, '--report', reports/'native.json')
    python('test_ltv.py', '--runtime', runtime, '--report', reports/'ltv.json')
    for name in ('test_ltv_runtime.py', 'test_linux_packaging.py', 'test_linux_appimage_packaging.py',
                 'test_desktop_ci.py'):
        python(name)
    # These tests include the private D-Bus PackageKit wire fixtures on Linux.
    flutter_checks()
    os.environ['CMAKE_BUILD_PARALLEL_LEVEL'] = '2'
    run('flutter', '--suppress-analytics', 'build', 'linux', '--release', '--no-pub')
    bundle = ROOT/('build/linux/'+architecture+'/release/bundle')
    preview = json.loads((ROOT/'native/preview/pdfium.lock.json').read_text())['artifacts']['linux-'+architecture]
    with tarfile.open(download(preview, cache)) as archive:
        entry = next(m for m in archive.getmembers() if m.name.lstrip('./') == 'lib/libpdfium.so')
        import hashlib
        if hashlib.sha256(archive.extractfile(entry).read()).hexdigest() != sha(bundle/'lib/libpdfium.so'):
            raise ValueError('PDFium differs from the architecture-matched publisher lock')
    output = ROOT/('dist/linux-'+architecture+'-'+kind)
    if kind == 'deb':
        python('package_linux_deb.py', '--bundle', bundle, '--output', output,
               '--version', application_version())
        package, = output.glob('*.deb')
        python('test_linux_deb.py', package, '--report', reports/'deb.json')
        artifacts = [package]
        # Preserve Unix modes/symlinks when passing the complete bundle to
        # optional distribution-specific packagers or downloading it locally.
        tar = output/('firma-con-cie-linux-'+architecture+'-bundle.tar.gz')
        with tarfile.open(tar, 'w:gz') as archive:
            archive.add(bundle, arcname='bundle')
        artifacts.append(tar)
    else:
        lock_name = 'runtime-aarch64.lock.json' if architecture == 'arm64' else 'runtime.lock.json'
        lock = json.loads((ROOT/'linux/appimage'/lock_name).read_text())
        lock['archive'] = 'appimage-runtime-'+cpu
        runtime_file = download(lock, cache)
        runtime_file.chmod(0o755)
        python('package_linux_appimage.py', '--bundle', bundle, '--output', output,
               '--runtime', runtime_file, '--version', application_version())
        artifacts = list(output.glob('*.AppImage'))
        # Read-only extraction/inventory and ABI checks; no FUSE or GUI launch.
        manifest = json.loads((output/'package-manifest.json').read_text())
        if not manifest['elfFilesChecked'] or manifest['cardTestsRun']:
            raise ValueError('Invalid AppImage validation evidence')
        for name, digest in manifest['files'].items():
            if sha(output/'AppDir'/name) != digest:
                raise ValueError('AppImage payload checksum mismatch')
    receipt(reports/'build-result.json', 'linux', architecture, artifacts,
            packageFormat=kind, softwareChecksPassed=False, tlsChecksPending=True)


def finish_tls(kind):
    if platform.system() != 'Linux' or os.geteuid() != 0:
        raise ValueError('The TLS phase requires root in the isolated CI container')
    architecture = host_architecture()
    reports = ROOT/('reports/linux-'+architecture+'-'+kind)
    work = ROOT/('.build/ci-linux-'+kind)
    python('test_linux_tls_runtime.py', '--client', work/'native-build/cie_network_test_client',
           '--report', reports/'tls.json', '--no-user-namespace')
    if not json.loads((reports/'tls.json').read_text())['passed']:
        raise ValueError('Native HTTPS trust checks did not pass')
    result = json.loads((reports/'build-result.json').read_text())
    result.update(softwareChecksPassed=True, tlsChecksPending=False, nativeTlsChecksPassed=True)
    (reports/'result.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('format', choices=['deb', 'appimage'])
    parser.add_argument('--tls-check', action='store_true')
    args = parser.parse_args()
    (finish_tls if args.tls_check else build)(args.format)
