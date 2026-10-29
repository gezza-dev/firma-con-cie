#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Package an already signed Universal app as a signed, non-notarized DMG.

Requires ds_store==1.3.1. Does not modify the source app or install anything.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile

from ds_store import DSStore
from build_paths import macos_paths
from product_identity import macos_image_name
from macos_signing import MacCodeSigner

# Finder stores absolute AppKit coordinates, with y increasing upwards.
# A high y asks Finder to fit the window near the top of the opening display,
# independently of the packaging Mac's resolution, Dock or monitor layout.
WINDOW_BOUNDS = '{{100, 100000}, {640, 420}}'


def run(*args, capture=False):
    return subprocess.run(list(map(str, args)), check=True,
                          stdout=subprocess.PIPE if capture else None)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(app):
    result = {}
    for path in sorted(app.rglob('*')):
        name = path.relative_to(app).as_posix()
        if path.is_symlink():
            result[name] = {'link': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': sha256(path),
                            'mode': stat.S_IMODE(path.stat().st_mode)}
    return result


def validate_app(app, expected=None):
    run('codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    native = app / 'Contents/Frameworks/CIEPrototype'
    extension = app / 'Contents/PlugIns/CIEPrototypeToken.appex'
    extension_info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
    binaries = [app / 'Contents/MacOS' / info['CFBundleExecutable'],
                native / 'cie_card_observer', *sorted(native.glob('*.dylib')),
                extension / 'Contents/MacOS' / extension_info['CFBundleExecutable']]
    for executable in (binaries[0], binaries[1], binaries[-1]):
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError('Missing executable permission: ' + str(executable))
    if not list(native.glob('*.dylib')):
        raise ValueError('Missing private middleware/runtime')
    for binary in binaries:
        architectures = run('lipo', '-archs', binary, capture=True).stdout.decode().split()
        if set(architectures) != {'arm64', 'x86_64'}:
            raise ValueError('Expected Universal binary: ' + str(binary))
    actual = inventory(app)
    if expected is not None and actual != expected:
        raise ValueError('Packaged app differs from the signed source bundle')
    return actual


def finder_layout(folder):
    with DSStore.open(str(folder / '.DS_Store'), 'w+') as store:
        store['.']['vSrn'] = ('long', 1)
        store['.']['icvl'] = ('type', b'icnv')
        store['.']['vstl'] = ('type', b'icnv')
        store['.']['bwsp'] = dict(
            WindowBounds=WINDOW_BOUNDS, ShowStatusBar=False,
            ShowToolbar=False, ShowPathbar=False, ShowSidebar=False,
            ContainerShowSidebar=False, PreviewPaneVisibility=False,
            SidebarWidth=0, ShowTabView=False)
        store['.']['icvp'] = dict(
            viewOptionsVersion=1, backgroundType=0,
            backgroundColorRed=1.0, backgroundColorGreen=1.0,
            backgroundColorBlue=1.0,
            # Keep spacing below 100 so Finder accepts the saved icon view.
            gridOffsetX=0.0, gridOffsetY=0.0, gridSpacing=54.0,
            arrangeBy='none', showIconPreview=True, showItemInfo=False,
            labelOnBottom=True, textSize=14.0, axTextSize=14.0, iconSize=112.0,
            scrollPositionX=0.0, scrollPositionY=0.0)
        store['Firma con CIE.app']['Iloc'] = (175, 155)
        store['Applicazioni']['Iloc'] = (465, 155)


def clean_packaged_metadata(app):
    # HFS+ adds FinderInfo even to read-only JRE license files. Temporarily
    # allow owner writes on this disposable copy, then restore every mode.
    modes = []
    try:
        for path in [app, *app.rglob('*')]:
            if path.is_symlink():
                continue
            mode = stat.S_IMODE(path.stat().st_mode)
            if not mode & stat.S_IWUSR:
                path.chmod(mode | stat.S_IWUSR)
                modes.append((path, mode))
        for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
            # Missing attributes are expected; validate_app checks the result.
            subprocess.run(['xattr', '-dr', attribute, str(app)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        for path, mode in reversed(modes):
            path.chmod(mode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path,
                        help='Override the local/default signed app location')
    parser.add_argument('--identity', required=True,
                        help='Apple code signing identity for the disk image')
    parser.add_argument('--developer-id', action='store_true',
                        help='Require Developer ID Application and a secure timestamp')
    parser.add_argument('--output', type=Path,
                        help='Override the local/default DMG destination')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    signer = MacCodeSigner(args.identity, args.developer_id)
    if args.app is None or args.output is None:
        local_paths = macos_paths(Path(__file__).resolve().parents[1])
        args.app = args.app or local_paths['destination'] / 'Firma con CIE.app'
        if args.output is None:
            version = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
            args.output = local_paths['dmg'].parent / macos_image_name(version)
    if args.app.is_symlink() or args.app.name != 'Firma con CIE.app':
        raise ValueError('Provide a real signed Firma con CIE.app bundle')
    app, output = args.app.resolve(), args.output.absolute()
    if output.exists() or output.is_symlink():
        raise FileExistsError('Refusing to replace an existing DMG: ' + str(output))
    if output.suffix.lower() != '.dmg' or app in output.parents:
        raise ValueError('Output must be a DMG outside the source app')
    original = validate_app(app)
    signer.verify(app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.firma-con-cie-dmg-', dir=output.parent) as temporary:
        work = Path(temporary)
        stage = work / 'contents'
        stage.mkdir()
        run('ditto', app, stage / app.name)
        (stage / 'Applicazioni').symlink_to('/Applications')
        finder_layout(stage)
        validate_app(stage / app.name, original)
        writable = work / 'layout.dmg'
        run('hdiutil', 'create', '-srcfolder', stage, '-volname', 'Firma con CIE',
            '-fs', 'HFS+', '-format', 'UDRW', writable)
        mount = work / 'volume'
        mount.mkdir()
        attached = False
        try:
            run('hdiutil', 'attach', '-nobrowse', '-noautoopen',
                '-mountpoint', mount, '-plist', writable, capture=True)
            attached = True
            finder_layout(mount)
            # HFS+ creation can add FinderInfo to the copied bundle. Clean
            # only the packaged app, before freezing the volume.
            clean_packaged_metadata(mount / app.name)
            validate_app(mount / app.name, original)
        finally:
            if attached:
                run('hdiutil', 'detach', mount)
        image = work / output.name
        run('hdiutil', 'convert', writable, '-format', 'UDZO',
            '-imagekey', 'zlib-level=9', '-o', image)
        # Keep the product identifier stable for both signing modes.
        signer.sign(image, disk_image=True,
                    identifier='it.giancarloezza.CIEID.Desktop.dmg')
        run('codesign', '--verify', '--strict', '--verbose=2', image)
        signer.verify(image, disk_image=True)
        run('hdiutil', 'verify', image)
        attached = False
        try:
            run('hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                '-mountpoint', mount, '-plist', image, capture=True)
            attached = True
            visible = {p.name for p in mount.iterdir() if not p.name.startswith('.')}
            if visible != {'Firma con CIE.app', 'Applicazioni'}:
                raise ValueError('Unexpected visible contents in disk image')
            if not (mount / 'Applicazioni').is_symlink() or os.readlink(mount / 'Applicazioni') != '/Applications':
                raise ValueError('Invalid Applications link')
            with DSStore.open(str(mount / '.DS_Store'), 'r') as store:
                assert store['.']['bwsp']['WindowBounds'] == WINDOW_BOUNDS
                assert store['Firma con CIE.app']['Iloc'] == (175, 155)
                assert store['Applicazioni']['Iloc'] == (465, 155)
            validate_app(mount / app.name, original)
            copied = work / 'installation-check' / app.name
            copied.parent.mkdir()
            run('ditto', mount / app.name, copied)
            validate_app(copied, original)
        finally:
            if attached:
                run('hdiutil', 'detach', mount)
        if inventory(app) != original:
            raise ValueError('Source app changed during packaging')
        if output.exists() or output.is_symlink():
            raise FileExistsError(output)
        image.rename(output)
    receipt = dict(image=str(output), application=str(app),
                   volume='Firma con CIE', format='UDZO',
                   signing_identity=args.identity, notarized=False,
                   signing_type='Developer ID Application' if args.developer_id else 'Apple Development',
                   bytes=output.stat().st_size, sha256=sha256(output),
                   layout=dict(window_size=[640, 420],
                               window_bounds=WINDOW_BOUNDS,
                               position_policy='finder-fit-near-top-left', icon_size=112,
                               app=[175, 155], applications=[465, 155]),
                   applications_link='Applicazioni -> /Applications',
                   verified_after_mount=True, verified_after_copy=True,
                   application_files=original)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(receipt, indent=2) + '\n')
    print('Signed DMG (not notarized):', output)
    print('SHA256:', receipt['sha256'])


if __name__ == '__main__':
    main()
