#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Export light/dark desktop icons from the document/signature artwork (Pillow >= 10)."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/branding'
APP_ID = 'it.giancarloezza.prototype.cie_flutter_prototype'
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
LINUX_SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)


def svg(content, size):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'xmlns:xlink="http://www.w3.org/1999/xlink" width="{size}" '
            f'height="{size}" viewBox="0 0 {size} {size}">\n{content}\n</svg>\n')


def srgb(color):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return 'srgb:' + ','.join(f'{value:.8f}' for value in rgb) + ',1.00000000'


def write_sources(config):
    """Compose one original foreground with the two application theme bases."""
    size = config['canvas']
    scale = config['foregroundScale']
    margin = size * (1 - scale) / 2
    encoded = base64.b64encode((ASSETS / 'source/document-signature.png').read_bytes()).decode('ascii')
    native = ROOT / 'macos/Runner/AppIcon.icon'
    native_assets = native / 'Assets'
    native_assets.mkdir(parents=True, exist_ok=True)
    body = (f'<image width="{size}" height="{size}" '
            f'xlink:href="data:image/png;base64,{encoded}"/>')
    (native_assets / 'Document-signature.svg').write_text(svg(body, size), encoding='utf-8')
    for theme, color in config['themes'].items():
        # The foreground is identical in both themes: only the base changes.
        base = f'<rect width="{size}" height="{size}" fill="{color}"/>'
        (native_assets / f'Base-{theme}.svg').write_text(svg(base, size), encoding='utf-8')
        flat = svg(
            f'<rect width="{size}" height="{size}" rx="{config["cornerRadius"]}" fill="{color}"/>\n'
            f'<g transform="translate({margin} {margin}) scale({scale})">\n{body}\n</g>', size)
        (ASSETS / f'source/firma-con-cie-{theme}.svg').write_text(flat, encoding='utf-8')
    shutil.copyfile(ASSETS / f'source/firma-con-cie-{config["default"]}.svg', ASSETS / 'source/firma-con-cie.svg')
    light, dark = config['themes']['light'], config['themes']['dark']
    def variants(prefix):
        return [{'value': f'{prefix}-light.svg'}] + [
                {'appearance': appearance, 'value': f'{prefix}-dark.svg'}
                for appearance in ('dark', 'tinted')]
    document = {
        'fill-specializations': [{'value': {'solid': srgb(light)}}] + [
            {'appearance': appearance, 'value': {'solid': srgb(dark)}}
            for appearance in ('dark', 'tinted')],
        'groups': [{
            'name': 'Firma con CIE',
            # Icon Composer orders the frontmost layer first.
            'layers': [
                {'image-name': 'Document-signature.svg',
                 'name': 'Documento e firma', 'glass': False, 'opacity': 1,
                 'position': {'scale': scale, 'translation-in-points': [0, 0]}},
                {'image-name-specializations': variants('Base'),
                 'name': 'Base opaca del tema', 'glass': False, 'opacity': 1}],
            'specular': False, 'blur-material': 0,
            'shadow': {'kind': 'none', 'opacity': 0},
            'translucency': {'enabled': False, 'value': 0}}],
        'supported-platforms': {'squares': ['macOS']}}
    (native / 'icon.json').write_text(json.dumps(document, indent=2) + '\n')
    # Retire script-owned resources of the former official-derived logo.
    for name in ('Black.svg', 'firma-con-cie-circle.png', 'Circle-light.svg', 'Circle-dark.svg'):
        (native_assets / name).unlink(missing_ok=True)
    return native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render-source', action='store_true',
                        help='Render both composed SVG masters using macOS sips')
    args = parser.parse_args()
    config = json.loads((ASSETS / 'themes.json').read_text())
    native = write_sources(config)
    outputs = [ASSETS / 'themes.json']
    masters = {}
    for theme in config['themes']:
        target = ASSETS / f'master/firma-con-cie-{theme}.png'
        if args.render_source:
            if not shutil.which('sips'):
                raise SystemExit('--render-source requires macOS sips; use committed PNGs elsewhere')
            subprocess.run(['sips', '-s', 'format', 'png',
                            str(ASSETS / f'source/firma-con-cie-{theme}.svg'), '--out', str(target)],
                           check=True)
        masters[theme] = Image.open(target).convert('RGBA')
        if masters[theme].size != (1024, 1024):
            raise SystemExit('Expected 1024 × 1024 masters')
        outputs.append(target)
    default = config['default']
    shutil.copyfile(ASSETS / f'master/firma-con-cie-{default}.png', ASSETS / 'master/firma-con-cie.png')
    outputs.append(ASSETS / 'master/firma-con-cie.png')

    def png(path, size, theme=default):
        path.parent.mkdir(parents=True, exist_ok=True)
        masters[theme].resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)
        outputs.append(path)

    # Explicit export sets for both appearances on all three platforms.
    for theme, master in masters.items():
        iconset = ASSETS / f'macos/{theme}/firma-con-cie.iconset'
        for logical in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = '@2x' if scale == 2 else ''
                png(iconset / f'icon_{logical}x{logical}{suffix}.png', logical * scale, theme)
        icns = ASSETS / f'macos/{theme}/firma-con-cie.icns'
        if shutil.which('iconutil'):
            subprocess.run(['iconutil', '--convert', 'icns', str(iconset),
                            '--output', str(icns)], check=True)
        else:
            master.save(icns, format='ICNS')
        outputs.append(icns)
        ico = ASSETS / f'windows/{theme}/firma-con-cie.ico'
        ico.parent.mkdir(parents=True, exist_ok=True)
        master.save(ico, format='ICO', sizes=[(n, n) for n in ICO_SIZES])
        outputs.append(ico)
        for size in LINUX_SIZES:
            png(ASSETS / f'linux/{theme}/hicolor/{size}x{size}/apps/{APP_ID}.png', size, theme)

    # Compatibility paths and runners default to light; macOS uses the native
    # document's appearance selection. EXE/desktop launchers have static icons.
    for source, destination in [
        (ASSETS / f'macos/{default}/firma-con-cie.icns', ASSETS / 'macos/firma-con-cie.icns'),
        (ASSETS / f'windows/{default}/firma-con-cie.ico', ASSETS / 'windows/firma-con-cie.ico'),
        (ASSETS / f'windows/{default}/firma-con-cie.ico', ROOT / 'windows/runner/resources/app_icon.ico')]:
        shutil.copyfile(source, destination)
        outputs.append(destination)
    for logical in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            png(ASSETS / f'macos/firma-con-cie.iconset/icon_{logical}x{logical}{suffix}.png',
                logical * scale)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        png(ROOT / f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png', size)
    for size in LINUX_SIZES:
        png(ASSETS / f'linux/hicolor/{size}x{size}/apps/{APP_ID}.png', size)
    png(ROOT / 'linux/resources/cie-id.png', 256)

    packaged = ASSETS / 'macos/AppIcon.icon'
    shutil.copytree(native, packaged, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.DS_Store'))
    for name in ('Black.svg', 'firma-con-cie-circle.png', 'Circle-light.svg', 'Circle-dark.svg'):
        (packaged / 'Assets' / name).unlink(missing_ok=True)
    outputs.extend(p for p in native.rglob('*') if p.is_file() and p.name != '.DS_Store')
    outputs.extend(p for p in packaged.rglob('*') if p.is_file() and p.name != '.DS_Store')
    outputs.extend(p for p in (ASSETS / 'source').iterdir() if p.is_file())

    desktop = ASSETS / f'linux/{APP_ID}.desktop'
    desktop.write_text(
        '[Desktop Entry]\nType=Application\nName=Firma con CIE\n'
        'Comment=Electronic identity card and document signing\n'
        'Comment[it]=Carta di identità elettronica e firma dei documenti\n'
        f'Exec="Firma con CIE"\nTryExec=Firma con CIE\nIcon={APP_ID}\nTerminal=false\n'
        f'Categories=Utility;Security;\nStartupWMClass={APP_ID}\n'
        'Keywords=CIE;smartcard;signature;PDF;\n'
        'Keywords[it]=CIE;carta;identità;firma;PDF;\n', encoding='utf-8')
    outputs.append(desktop)
    shutil.copyfile(ASSETS / 'LICENSE.txt', ASSETS / 'linux/icon-LICENSE.txt')
    outputs.extend([ASSETS / 'LICENSE.txt', ASSETS / 'linux/icon-LICENSE.txt',
                    ASSETS / 'provenance.json', ASSETS / 'imagegen-prompt.txt',
                    ASSETS / 'README.md',
                    ROOT / 'assets/licenses/cie-app-icon-NOTICE.txt',
                    ROOT / 'assets/licenses/cie-app-icon-LICENSE.txt'])
    manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(set(outputs))}
    (ASSETS / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    archive = ROOT / 'dist/branding/firma-con-cie-icons.zip'
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(ASSETS.rglob('*')):
            if path.is_file() and path.name != '.DS_Store':
                bundle.write(path, Path('firma-con-cie-icons') / path.relative_to(ASSETS))
    print(f'Exported {len(manifest)} icon resources; archive: {archive}')


if __name__ == '__main__':
    main()
