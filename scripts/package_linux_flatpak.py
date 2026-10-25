#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Assemble a local x86_64 Flatpak test bundle, without installing or launching it.

Consumes an already compiled, validated release bundle. This is local test
packaging, not a Flathub source-build submission. The runtime is supplied by
Flathub; the PC/SC client and its notices come from the explicit build sysroot.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import tempfile
import xml.etree.ElementTree as ET

from linux_package_common import ROOT, APP_ID as NATIVE_ID, PREFIX, run, sha, files, validate_bundle, stage_payload, source_revision
from package_linux_distribution import elf_files

PROFILE = ROOT / 'linux/flatpak/it.giancarloezza.FirmaConCIE.Test.json'
APP_ID = 'it.giancarloezza.FirmaConCIE.Test'
RUNTIME_REPO = 'https://dl.flathub.org/repo/flathub.flatpakrepo'
PERMISSIONS = {
    '--socket=wayland', '--socket=fallback-x11', '--share=ipc', '--device=dri',
    '--share=network', '--socket=pcsc', '--talk-name=org.freedesktop.secrets',
    '--persist=.local', '--talk-name=it.giancarloezza.FirmaConCIE.BrowserHelper1',
    '--env=GTK_USE_PORTAL=1',
}


def profile():
    value = json.loads(PROFILE.read_text())
    if value['id'] != APP_ID or value['command'] != 'firma-con-cie' or value['branch'] != 'test':
        raise ValueError('Use the separate Flatpak test identity and branch')
    if len(value['finish-args']) != len(PERMISSIONS) or set(value['finish-args']) != PERMISSIONS:
        raise ValueError('Unexpected Flatpak permissions')
    return value


def metainfo(app_id, version):
    component = ET.Element('component', type='desktop-application')
    for tag, text in [('id', app_id), ('metadata_license', 'CC0-1.0'),
                      ('project_license', 'BSD-3-Clause'),
                      ('name', 'Firma con CIE (Flatpak test)'),
                      ('summary', 'Electronic identity card and document signing')]:
        ET.SubElement(component, tag).text = text
    ET.SubElement(component, 'developer_name').text = 'Gian Carlo Ezza'
    desc = ET.SubElement(component, 'description')
    ET.SubElement(desc, 'p').text = 'Independent local test build for document signing and verification with Italian CIE cards. Browser setup requires the separate host companion, installed by the user. Bundled components have additional licenses in the included notices.'
    ET.SubElement(component, 'launchable', type='desktop-id').text = app_id + '.desktop'
    ET.SubElement(component, 'url', type='homepage').text = 'https://github.com/gezza-dev/cie-id-desktop'
    ET.SubElement(component, 'content_rating', type='oars-1.1')
    categories = ET.SubElement(component, 'categories')
    for category in ['Utility', 'Security']:
        ET.SubElement(categories, 'category').text = category
    ET.SubElement(ET.SubElement(component, 'releases'), 'release', version=version, date='2026-10-24')
    ET.indent(component)
    return ET.tostring(component, encoding='unicode') + '\n'


def stage(bundle, destination, native, pcsc_library, pcsc_license, version):
    """Copy a production payload; tests and user/browser data are never inputs."""
    if not pcsc_library.is_file() or not pcsc_license.is_file():
        raise ValueError('Supply the PC/SC client and its copyright from the build sysroot')
    if 'BSD-3-clause' not in pcsc_license.read_text():
        raise ValueError('Expected the complete pcsc-lite copyright notice')
    stage_payload(bundle, destination / 'native-layout', native, 'flatpak')
    original = destination / 'native-layout'
    target = destination / 'flatpak'
    payload = target / 'files'
    payload.mkdir(parents=True)
    (payload / 'lib').mkdir()
    shutil.move(str(original / PREFIX), str(payload / 'lib/firma-con-cie'))
    shutil.copy2(pcsc_library, payload / 'lib/libpcsclite.so.1')
    (payload / 'bin').mkdir()
    launcher = payload / 'bin/firma-con-cie'
    launcher.write_text('#!/bin/sh\numask 077\nexport GTK_USE_PORTAL=1\nexec "/app/lib/firma-con-cie/Firma con CIE" "$@"\n')
    launcher.chmod(0o755)
    share = payload / 'share'
    shutil.move(str(original / 'usr/share'), str(share))
    # Native executable assets keep their resource identity; exported entries
    # get the distinct Flatpak test ID so both installations can coexist.
    desktop = share / 'applications' / (NATIVE_ID + '.desktop')
    text = desktop.read_text().replace('Name=Firma con CIE\n', 'Name=Firma con CIE (Flatpak test)\n')
    text = text.replace('Exec="/usr/bin/Firma con CIE"', 'Exec=firma-con-cie')
    text = text.replace('TryExec=/usr/bin/Firma con CIE', 'TryExec=firma-con-cie')
    text = text.replace('Icon=' + NATIVE_ID, 'Icon=' + APP_ID)
    text = text.replace('StartupWMClass=' + NATIVE_ID, 'StartupWMClass=' + APP_ID)
    desktop.unlink()
    desktop = desktop.with_name(APP_ID + '.desktop')
    desktop.write_text(text)
    run('desktop-file-validate', desktop)
    for icon in (share / 'icons').rglob(NATIVE_ID + '.png'):
        # Flatpak exported raster icons must not exceed 512 pixels.
        size = icon.parent.parent.name.split('x')
        if len(size) == 2 and max(map(int, size)) > 512:
            icon.unlink()
        else:
            icon.rename(icon.with_name(APP_ID + '.png'))
    notices = share / 'licenses' / APP_ID
    notices.mkdir(parents=True)
    shutil.copy2(pcsc_license, notices / 'pcsc-lite-copyright')
    shutil.copy2(ROOT / 'docs/LINUX_FLATPAK.md', share / 'doc/cie-id-desktop/LINUX_FLATPAK.md')
    (share / 'metainfo').mkdir()
    (share / 'metainfo' / (APP_ID + '.metainfo.xml')).write_text(metainfo(APP_ID, version))
    # No host-browser registration utility is exported as a launcher.
    tools = share / 'doc/cie-id-desktop/tools'
    if tools.exists():
        shutil.rmtree(tools)
    shutil.rmtree(original)
    value = profile()
    (target / 'metadata').write_text('[Application]\nname=' + APP_ID + '\nruntime=' + value['runtime'] + '/x86_64/' + value['runtime-version'] + '\nsdk=' + value['sdk'] + '/x86_64/' + value['runtime-version'] + '\ncommand=firma-con-cie\n')
    return target


def package(bundle, output, pcsc_library, pcsc_license, version):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+~_-]*test[A-Za-z0-9.+~_-]*', version):
        raise ValueError('Use an explicit test version')
    bundle, output = bundle.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(bundle):
        raise ValueError('Use a new output directory outside the input bundle')
    value = profile()
    native = validate_bundle(bundle)
    elf_files(bundle)  # Every input ELF must be x86_64.
    if APP_ID not in run('strings', bundle / 'Firma con CIE').stdout.splitlines():
        raise ValueError('Rebuild the GUI with CIE_FLATPAK_APP_ID=' + APP_ID)
    runtime_ref = value['runtime'] + '//'+value['runtime-version']
    runtime_commit = run('flatpak', 'info', '--user', '--show-commit', runtime_ref).stdout.strip()
    work = ROOT / '.build/linux-flatpak-packaging'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='package-', dir=work) as directory:
        target = stage(bundle, Path(directory), native, pcsc_library.resolve(), pcsc_license.resolve(), version)
        elfs = elf_files(target / 'files')
        run('flatpak', 'build-finish', '--command=firma-con-cie', *value['finish-args'], target)
        revision = source_revision()
        output.mkdir(parents=True)
        repository = output / 'repo'
        run('flatpak', 'build-export', '--disable-sandbox', '--arch=x86_64',
            '--subject=Firma con CIE Flatpak test ' + version, repository, target, 'test')
        filename = 'firma-con-cie-' + version + '-x86_64.flatpak'
        run('flatpak', 'build-bundle', '--arch=x86_64', '--runtime-repo=' + RUNTIME_REPO,
            repository, output / filename, APP_ID, 'test')
        # The deployable Flatpak is sandboxed; --disable-sandbox above only
        # allows the exporter to validate local icons inside a nested build root.
        metadata = (target / 'metadata').read_text()
        payload = {p.relative_to(target / 'files').as_posix(): sha(p) for p in files(target / 'files')}
        result = {'format': 'flatpak-local-test', 'appId': APP_ID, 'branch': 'test',
                  'version': version, 'architecture': 'x86_64', 'file': filename,
                  'bytes': (output / filename).stat().st_size, 'sha256': sha(output / filename),
                  **revision, 'runtime': runtime_ref, 'testedRuntimeCommit': runtime_commit,
                  'pcscClientSha256': sha(pcsc_library), 'pcscClientCopyrightSha256': sha(pcsc_license),
                  'finishArgs': value['finish-args'], 'elfFilesChecked': len(elfs),
                  'inputBundle': str(bundle), 'runtimeManifestVerified': True,
                  'testProgramsIncluded': False, 'browserConfigurationSupported': True, 'externalBrowserHelperRequired': True, 'browserFullPinRequired': True,
                  'browserConfigurationModified': False, 'cardTestsRun': False,
                  'hostInstallationPerformed': False, 'appLaunched': False, 'files': payload}
        (output / 'package-manifest.json').write_text(json.dumps(result, indent=2)+'\n')
        (output / 'metadata').write_text(metadata)
        (output / 'SHA256SUMS').write_text(result['sha256']+'  '+filename+'\n')
        shutil.copy2(PROFILE, output / PROFILE.name)
        shutil.copy2(ROOT / 'docs/LINUX_FLATPAK.md', output / 'LEGGIMI.md')
        print(json.dumps({k: v for k, v in result.items() if k != 'files'}, indent=2))
        return output / filename


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pcsc-library', type=Path, required=True)
    parser.add_argument('--pcsc-license', type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    package(args.bundle, args.output, args.pcsc_library, args.pcsc_license, args.version)


if __name__ == '__main__':
    main()
