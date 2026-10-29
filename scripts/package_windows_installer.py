#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the Windows x64/ARM64 installer from a complete, validated Release folder.

Does not install anything, contact a card or read a user profile. Requires Inno
Setup 7.1 and Microsoft's signed matching VC redistributable (VS Build Tools/Redist).
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
from product_identity import windows_installer_name
from windows_architecture import check_release_architecture
from windows_helper_manifest import check_helper_manifest

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'packaging/windows/release-policy.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_file(root, name):
    rel = PurePosixPath(name)
    if rel.is_absolute() or any(x in ('', '.', '..') for x in rel.parts) or any(x in name for x in ':\\"'):
        raise ValueError('Invalid package path: ' + name)
    path = root.joinpath(*rel.parts)
    for item in (path, *path.parents):
        if item.is_symlink() or item.is_junction():
            raise ValueError('Package contains a link: ' + name)
        if item == root:
            break
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Missing package file: ' + name)
    return path


def validate_release(release):
    for name in ('Firma con CIE.exe', 'flutter_windows.dll', 'pdfium.dll', 'data/app.so',
                 'web-component/CIE-Web-Setup.exe', 'cie_native/ltv/cie-ltv-worker.jar',
                 'cie_native/cie_card_observer.exe'):
        safe_file(release, name)
    counts = {}
    for folder, manifest_name in (('cie_native', 'backend-manifest.json'), ('web-component', 'payload-manifest.json')):
        base = release / folder
        manifest = json.loads((base / manifest_name).read_text(encoding='utf-8'))
        for name, digest in manifest['files'].items():
            if sha(safe_file(base, name)) != digest:
                raise ValueError('Checksum mismatch: ' + folder + '/' + name)
        actual = {p.relative_to(base).as_posix() for p in base.rglob('*') if p.is_file()}
        expected = set(manifest['files']) | {manifest_name}
        if folder == 'web-component':
            expected.add('CIE-Web-Setup.exe')
        if actual != expected:
            raise ValueError('Unlisted or missing payload files in ' + folder)
        if folder == 'cie_native' and manifest.get('system') == 'windows':
            # The bridge embeds ownedName(), shared with the installer. A
            # current helper cannot compensate for a stale compiled bridge.
            artifact = manifest.get('artifacts', {}).get('cie_bridge.dll')
            if artifact and artifact.get('sha256') != manifest['files'].get('cie_bridge.dll'):
                raise ValueError('Native bridge provenance does not match the binary')
            sources = artifact.get('source_files', {}) if artifact else manifest.get('source_files', {})
            for dependency in ('native/platform/windows/web/setup_policy.h',
                               'native/platform/windows/web/card_catalog.h'):
                if sources.get(dependency) != sha(ROOT / dependency):
                    raise ValueError('Rebuild the native Windows bridge for the current card catalog: ' + dependency)
        counts[folder] = len(manifest['files'])
    web = json.loads((release / 'web-component/payload-manifest.json').read_text())
    if not re.fullmatch('[0-9a-f]{64}', web['version']):
        raise ValueError('Invalid web payload version')
    if hashlib.sha256(json.dumps(web['files'], sort_keys=True).encode()).hexdigest() != web['version']:
        raise ValueError('Web payload version does not match its contents')
    # Reject accidental inclusion of personal data, even outside the manifests.
    for path in release.rglob('*'):
        rel = path.relative_to(release).as_posix()
        if path.is_symlink() or path.is_junction():
            raise ValueError('Link in Release: ' + rel)
        if path.is_file() and (path.name in ('.key', 'settings.json', 'preferences.json') or
                               path.suffix.lower() in ('.card', '.web', '.pfx', '.p12')):
            raise ValueError('User data in Release: ' + rel)
    return web, counts


def stage_release(source, target):
    """Copy a runtime-only distribution; never mutate the development runtime.

    Exclusions are explicit paths, never suffix guesses: source JARs, license
    manifests, JVM legal notices and Flutter NOTICES are retained byte for byte.
    """
    validate_release(source)
    policy = json.loads(POLICY.read_text(encoding='utf-8'))
    if target.exists():
        raise ValueError('Use a new staged Release directory')
    target.mkdir(parents=True)
    excluded, retained = {}, {}
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(source).as_posix()
        reason = policy['excludeFiles'].get(name)
        for prefix, description in policy['excludeDirectories'].items():
            if name.startswith(prefix):
                reason = description
        if reason:
            # Never allow policy edits to silently remove attribution material.
            if 'licenses' in path.relative_to(source).parts or 'legal' in path.relative_to(source).parts:
                raise ValueError('Cannot exclude license material: ' + name)
            excluded[name] = {'sha256': sha(path), 'bytes': path.stat().st_size, 'reason': reason}
            continue
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        retained[name] = sha(path)
        if sha(destination) != retained[name]:
            raise ValueError('Staging changed a runtime file: ' + name)
    original = source / 'cie_native/backend-manifest.json'
    native = json.loads(original.read_text(encoding='utf-8'))
    native['files'] = {k: v for k, v in native['files'].items() if 'cie_native/' + k not in excluded}
    native['distribution'] = {'profile': policy['profile'], 'sourceManifestSha256': sha(original),
                              'policySha256': sha(POLICY), 'excludedFileCount': len(excluded)}
    (target / 'cie_native/backend-manifest.json').write_text(json.dumps(native, indent=2) + '\n', encoding='utf-8')
    validate_release(target)
    return {'profile': policy['profile'], 'policySha256': sha(POLICY),
            'sourceManifestSha256': sha(original), 'excludedFiles': excluded,
            'excludedBytes': sum(f['bytes'] for f in excluded.values()),
            'retainedFilesUnchanged': len(retained) - 1,
            'sourceBytes': sum(p.stat().st_size for p in source.rglob('*') if p.is_file()),
            'releaseBytes': sum(p.stat().st_size for p in target.rglob('*') if p.is_file())}


def quote(value):
    value = str(value)
    if any(x in value for x in ('"', '\r', '\n')):
        raise ValueError('Invalid Inno argument')
    return '"' + value + '"'


def prepare(release, output, version, vc_redist, *, test_root=None, architecture=None):
    release, output = release.resolve(), output.resolve()
    if output.is_relative_to(release) or release.is_relative_to(output):
        raise ValueError('Release and installer output directories must not overlap')
    if output.exists():
        raise ValueError('Use a new installer output directory')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:\.\d+)?', version):
        raise ValueError('Invalid installer version')
    validate_release(release)
    if architecture and not test_root:
        check_release_architecture(release, architecture)
        check_helper_manifest(release / 'web-component/CIE-Web-Setup.exe')
    output.mkdir(parents=True)
    work = output / 'build'
    work.mkdir()
    source_release = release
    release = output / 'Release'
    audit = stage_release(source_release, release)
    (work / 'release-audit.json').write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
    shutil.copy2(source_release / 'cie_native/backend-manifest.json', work / 'source-backend-manifest.json')
    web, counts = validate_release(release)
    script = work / 'firma-con-cie.iss'
    shutil.copy2(ROOT / 'packaging/windows/firma-con-cie.iss', script)
    name = windows_installer_name(version, architecture or 'x64')
    if test_root:
        name += '-ISOLATED-TEST'
    before = work / 'before.txt'
    before.write_text(
        'Firma con CIE\n\n'
        'Italiano\nL’installer installa l’app e il componente di accesso ai siti. '
        'Non occorre collegare il lettore o appoggiare la CIE e non viene richiesto il PIN. '
        'Sono registrati gli ATR e le maschere dei 12 modelli del middleware ufficiale. '
        'Gli aggiornamenti preservano le registrazioni compatibili esistenti.\n'
        'Abbinamenti, impostazioni e immagini personali vengono conservati, anche durante la disinstallazione. '
        'Non è necessario avviare l’app prima di ogni accesso dal browser.\n'
        f'È incluso Microsoft Visual C++ Redistributable {architecture or "x64"}. Firma con CIE è un progetto indipendente, non un prodotto ufficiale IPZS.\n\n'
        'English\nSetup installs the app and website access component. '
        'No reader, CIE or PIN is needed during installation. '
        'The ATRs and masks of the 12 official middleware card models are registered. '
        'Updates preserve compatible existing registrations.\n'
        'Pairings, settings and personal images are preserved, including when uninstalling. '
        'The app does not need to stay open for browser authentication.\n'
        f'Microsoft Visual C++ Redistributable {architecture or "x64"} is included. Firma con CIE is an independent project, not an official IPZS product.\n',
        encoding='utf-8-sig')
    files = {f.relative_to(release).as_posix(): sha(f) for f in sorted(release.rglob('*')) if f.is_file()}
    manifest_path = work / 'installation-manifest.json'
    manifest = {'version': version, 'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'sourceChanges': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).splitlines(),
                'releaseFiles': files, 'webPayloadVersion': web['version'], 'validatedPayloadCounts': counts,
                'vcRedistSha256': sha(vc_redist), 'userDataActions': [], 'uacOwner': 'installer', 'cardPinRequested': False}
    manifest['architecture'] = architecture or 'x64'
    manifest['distribution'] = {k: v for k, v in audit.items() if k != 'excludedFiles'}
    manifest['cardCatalog'] = json.loads((ROOT / 'packaging/windows/card-catalog.json').read_text())
    source_paths = ['lib/main.dart', 'lib/windows_web_setup.dart', 'lib/guide_view.dart',
                    'lib/browser_setup.dart', 'windows/runner/browser_inventory.h',
                    'windows/runner/web_setup.h', 'macos/Runner/MainFlutterWindow.swift',
                    'lib/app_updates.dart', 'lib/certificate_validity.dart', 'lib/information_view.dart',
                    'lib/enrollment.dart', 'native/platform/linux/web/pkcs11.cpp',
                    'native/platform/windows/pkcs11/CMakeLists.txt',
                    'lib/l10n/catalog.g.dart', 'windows/runner/web_setup.cpp',
                    'native/platform/windows/web/setup.cpp', 'native/platform/windows/web/setup_policy.h',
                    'native/platform/windows/web/setup.manifest', 'native/platform/windows/web/setup.rc',
                    'native/platform/windows/web/CMakeLists.txt', 'scripts/windows_helper_manifest.py',
                    'native/platform/windows/web/minidriver.cpp', 'packaging/windows/firma-con-cie.iss',
                    'scripts/package_windows_installer.py', 'scripts/product_identity.py', 'packaging/windows/release-policy.json',
                    'packaging/windows/card-catalog.json', 'native/platform/windows/web/card_catalog.h',
                    'native/platform/windows/web/setup_catalog.h', 'native/platform/windows/web/setup_registry.h']
    manifest['sourceFileHashes'] = {name: sha(ROOT / name) for name in source_paths}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    config = {'AppVersion': version, 'ReleasePath': release, 'OutputPath': output,
              'OutputName': name, 'AppIcon': ROOT / 'windows/runner/resources/app_icon.ico',
              'ProjectLicense': ROOT / 'LICENSE', 'BeforeFile': before,
              'BuildManifest': manifest_path, 'VcRedist': vc_redist.resolve(),
              'TargetArchitecture': 'arm64' if architecture == 'arm64' else 'x64os',
              'MinimumWindowsVersion': '10.0.22000' if architecture == 'arm64' else '10.0',
              'VcRedistName': 'vc_redist.' + (architecture or 'x64') + '.exe'}
    if test_root:
        config['TestInstallPath'] = test_root.resolve()
    lines = [f'#define {k} {quote(v)}' for k, v in config.items()]
    if test_root:
        lines.append('#define InstallerTest')
    (work / 'build-config.iss').write_text('\n'.join(lines) + '\n', encoding='utf-8-sig')
    entries = []
    prefix = '{autopf}\\CIE ID Flutter Prototype\\WebToken\\' + web['version']
    if test_root:
        prefix = str(test_root.resolve() / 'system-component' / web['version'])
    for payload_name in web['files']:
        path = release / 'web-component' / payload_name
        destination = prefix + ('\\' + str(PurePosixPath(payload_name).parent).replace('/', '\\') if PurePosixPath(payload_name).parent != PurePosixPath('.') else '')
        entries.append('Source: ' + quote(path) + '; DestDir: ' + quote(destination) + '; Flags: onlyifdoesntexist uninsrestartdelete')
    (work / 'web-files.iss').write_text('\n'.join(entries) + '\n', encoding='utf-8-sig')
    # An upgrade from the earlier development bundle must also shrink on disk.
    # Delete only individually named excluded files, never trees or user files.
    cleanup = ['Type: files; Name: ' + quote('{app}\\' + name.replace('/', '\\'))
               for name in audit['excludedFiles']]
    (work / 'development-cleanup.iss').write_text('\n'.join(cleanup) + '\n', encoding='utf-8-sig')
    return script, output / (name + '.exe'), manifest


def build(release, output, version, compiler, vc_redist, **kwargs):
    script, installer, manifest = prepare(release, output, version, vc_redist, **kwargs)
    manifest['innoCompilerSha256'] = sha(compiler)
    (script.parent / 'installation-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    result = subprocess.run([str(compiler), '/Qp', str(script)], capture_output=True, timeout=600)
    (output / 'build.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('Inno Setup failed: ' + (result.stdout + result.stderr).decode(errors='replace')[-3500:])
    result = {'installer': str(installer), 'bytes': installer.stat().st_size,
              'sha256': sha(installer), 'releaseFiles': len(manifest['releaseFiles']),
              'validatedPayloadCounts': manifest['validatedPayloadCounts'], 'sourceCommit': manifest['sourceCommit']}
    result['release'] = str(output.resolve() / 'Release')
    result['distribution'] = manifest['distribution']
    (output / 'package-result.json').write_text(json.dumps(result, indent=2) + '\n')
    installer.with_suffix('.exe.sha256').write_text(result['sha256'] + '  ' + installer.name + '\n')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--release', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--iscc', required=True, type=Path)
    p.add_argument('--vc-redist', required=True, type=Path)
    p.add_argument('--version', default='1.0.0')
    p.add_argument('--architecture', choices=['x64', 'arm64'], default='x64')
    args = p.parse_args()
    # Verify Microsoft's prerequisite before it is embedded in an elevated setup.
    environment = dict(os.environ, CIE_INSTALLER_VC_REDIST=str(args.vc_redist.resolve()))
    shell = shutil.which('pwsh.exe') or shutil.which('powershell.exe')
    if not shell:
        raise SystemExit('PowerShell is required to verify the Microsoft prerequisite')
    check = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command',
        '$s=Get-AuthenticodeSignature -LiteralPath $env:CIE_INSTALLER_VC_REDIST; if($s.Status -ne "Valid" -or $s.SignerCertificate.Subject -notmatch "Microsoft Corporation"){exit 1}'],
        env=environment, capture_output=True)
    if check.returncode:
        raise SystemExit('Microsoft VC redistributable signature verification failed')
    # The signed bootstrapper can be x86 on either target. Verify its product
    # description as well, rather than inferring its payload CPU from PE Machine.
    environment['CIE_INSTALLER_EXPECTED_CPU'] = args.architecture
    check = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command',
        '$d=(Get-Item -LiteralPath $env:CIE_INSTALLER_VC_REDIST).VersionInfo.FileDescription; '
        'if($d -notmatch [regex]::Escape($env:CIE_INSTALLER_EXPECTED_CPU)){exit 1}'], env=environment)
    if check.returncode:
        raise SystemExit('Microsoft VC redistributable architecture mismatch')
    print(json.dumps(build(args.release, args.output, args.version, args.iscc, args.vc_redist,
                           architecture=args.architecture), indent=2))


if __name__ == '__main__':
    main()
