#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Validated, identical application payload for native Linux packages."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
from ltv_runtime import runtime_architecture
from product_identity import PACKAGE_NAME, ARTIFACT_STEM

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = PACKAGE_NAME
APP_ID = 'it.giancarloezza.prototype.cie_flutter_prototype'
PREFIX = Path('opt/firma-con-cie')


def run(*args, cwd=None):
    try:
        return subprocess.run(list(map(str, args)), cwd=cwd, check=True,
                              capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        if hasattr(exc, 'add_note'):  # Python 3.10 on the AppImage build base.
            exc.add_note(((exc.stdout or '') + (exc.stderr or ''))[-12000:])
        raise


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(tree):
    return sorted(p for p in tree.rglob('*') if p.is_file())


def validate_release_version(version):
    if not re.fullmatch(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', version):
        raise ValueError('Use a release version MAJOR.MINOR.PATCH without a suffix')
    return version


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
    if not {'browser_setup/firefox_setup.py', 'browser_setup/chrome_setup.py', 'browser_setup/libcie_browser_setup_guard.so'} <= set(manifest['files']):
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
    if manifest.get('ltv'):
        architecture = runtime_architecture('Linux')
        if not architecture or manifest['ltv']['architectures'] != [architecture]:
            raise ValueError('DSS JVM architecture differs from package architecture')
        for name in ('ltv/jre/' + architecture + '/bin/java', 'ltv/fetcher/cie_crl_fetch'):
            if not os.access(native / name, os.X_OK):
                raise ValueError('Private DSS executable missing: ' + name)
        for name in ('ltv/cie-ltv-worker.jar', 'ltv/trust/cacerts', 'licenses/ltv/dependencies.lock.json'):
            if not (native / name).is_file():
                raise ValueError('Private DSS runtime incomplete: ' + name)
    return manifest



def stage_payload(bundle, stage, native_manifest, package_type="deb"):
    app = stage / PREFIX
    shutil.copytree(bundle, app, ignore=shutil.ignore_patterns('tests', 'share'))
    # Original source JARs are supplied, unchanged, in the separate release
    # dependency-sources archive. They are not runtime inputs; some carry
    # upstream developer paths in generated source annotations.
    source_jars = 'licenses/ltv/dependency-sources/'
    source_directory = app / 'cie_native' / source_jars
    if source_directory.exists():
        shutil.rmtree(source_directory)
    packaged = dict(native_manifest)
    packaged['files'] = {k: v for k, v in native_manifest['files'].items()
                         if 'tests' not in PurePosixPath(k).parts
                         and not k.startswith(source_jars)}
    # Project notices belong to the current package, including when reusing
    # verified native binaries. Preserve upstream notices and input provenance.
    notice = 'licenses/prototype-NOTICE.md'
    if notice in packaged['files']:
        shutil.copy2(ROOT / 'NOTICE.md', app / 'cie_native' / notice)
        packaged['files'][notice] = sha(app / 'cie_native' / notice)
    packaged['packaging'] = {'type': package_type, 'testProgramsIncluded': False,
                             'dependencySourceJarsIncluded': False,
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
    for name in ('BUILDING.md', 'STATUS.md', 'WEB_AUTHENTICATION.md', 'AUTOMATIC_BROWSER_SETUP.md', 'LINUX_DSS_LTA.md', 'LINUX_PACKAGE.md', 'LINUX_FIREFOX.md', 'LINUX_FIREFOX_SETUP.md', 'LINUX_DISTRIBUTION_PACKAGES.md', 'LINUX_ARM64.md', 'LICENSING.md'):
        shutil.copy2(ROOT / 'docs' / name, doc / name)
    shutil.copy2(ROOT / 'docs/LINUX_CHROME.md', doc / 'LINUX_CHROME.md')
    (doc / 'tools').mkdir()
    shutil.copy2(ROOT / 'scripts/configure_chrome_linux.py', doc / 'tools/configure_chrome_linux.py')
    # These notices cover Flutter, PDFium, the icon and bundled native code.
    # The full dependency notice trees remain adjacent in cie_native/licenses.
    shutil.copy2(ROOT / 'assets/licenses/cie-app-icon-NOTICE.txt', doc / 'icon-NOTICE.txt')
    shutil.copy2(ROOT / 'assets/branding/LICENSE.txt', doc / 'icon-LICENSE.txt')
    license_dir = stage / 'usr/share/licenses' / PACKAGE
    license_dir.mkdir(parents=True)
    shutil.copy2(ROOT / 'LICENSE', license_dir / 'LICENSE')
    shutil.copy2(ROOT / 'NOTICE.md', license_dir / 'NOTICE.md')
    # Normalize copied build-directory permissions; no setuid, writable
    # system files or user-specific caches are installed by this package.
    for p in stage.rglob('*'):
        p.chmod(0o755 if p.is_dir() or p.stat().st_mode & 0o111 else 0o644)


def source_revision():
    """Source identity survives a clean isolated build without exposing .git."""
    receipt = ROOT / '.linux-package-source.json'
    if receipt.exists():
        data = json.loads(receipt.read_text())
        if not re.fullmatch(r'[0-9a-f]{40}', data['baseCommit']):
            raise ValueError('Invalid exported source revision')
        return data
    return {
        'baseCommit': run('git', 'rev-parse', 'HEAD', cwd=ROOT).stdout.strip(),
        'workingTreeModified': bool(run('git', 'status', '--porcelain', cwd=ROOT).stdout),
        'sourceDateEpoch': int(run('git', 'show', '-s', '--format=%ct', 'HEAD', cwd=ROOT).stdout),
    }


GRAPHICS_SONAMES = ('libEGL.so.1', 'libGL.so.1', 'libGLESv2.so.2')


def graphics_libraries():
    """GTK/libepoxy loads these at runtime; DT_NEEDED alone misses them."""
    cache = run('ldconfig', '-p').stdout
    result = set()
    for name in GRAPHICS_SONAMES:
        match = re.search(r'^\s*' + re.escape(name) + r'\s+[^\n]*=>\s+(\S+)', cache, re.M)
        if not match or not Path(match[1]).is_file():
            raise ValueError('Missing dynamic graphics dependency: ' + name)
        result.add(str(Path(match[1]).resolve()))
    return result
