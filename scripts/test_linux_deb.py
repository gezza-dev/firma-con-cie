#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Validate a test .deb and its dpkg lifecycle in an isolated root (no app/card).

The isolated dpkg database intentionally has no system dependencies installed;
--force-depends is limited to this temporary root. Host dependency resolution
is separately simulated by apt-get; neither operation installs on the host.
"""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'it.giancarloezza.prototype.cie_flutter_prototype'


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, text=True)


def check(package, report):
    package = package.resolve()
    manifest = json.loads((package.parent / 'package-manifest.json').read_text())
    assert hashlib.sha256(package.read_bytes()).hexdigest() == manifest['sha256']
    assert manifest['package'] == 'cie-id-desktop' and '~test' in manifest['version']
    work = ROOT / '.build/linux-deb'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='test-', dir=work) as directory:
        temp = Path(directory)
        extracted = temp / 'extracted'
        run('dpkg-deb', '--raw-extract', package, extracted)
        assert {p.name for p in (extracted / 'DEBIAN').iterdir()} == {'control', 'md5sums'}
        archive = run('dpkg-deb', '--contents', package).stdout
        assert all(line.split()[1] == 'root/root' for line in archive.splitlines())
        payload = {p.relative_to(extracted).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in extracted.rglob('*') if p.is_file() and 'DEBIAN' not in p.parts}
        assert payload == manifest['files']
        assert all(name.startswith(('opt/cie-id-desktop/', 'usr/bin/', 'usr/share/')) for name in payload)
        assert not any('tests' in Path(name).parts or '.key' == Path(name).name for name in payload)
        launcher = extracted / 'usr/bin/CIE-ID'
        assert launcher.stat().st_mode & 0o111
        run('sh', '-n', launcher)
        assert launcher.read_text() == '#!/bin/sh\nexec /opt/cie-id-desktop/CIE-ID "$@"\n'
        desktop = extracted / 'usr/share/applications' / (APP_ID + '.desktop')
        run('desktop-file-validate', desktop)
        assert 'Exec=/usr/bin/CIE-ID\n' in desktop.read_text()
        assert 'TryExec=/usr/bin/CIE-ID\n' in desktop.read_text()
        assert 'Icon=' + APP_ID + '\n' in desktop.read_text()
        app = extracted / 'opt/cie-id-desktop'
        assert '/it/giancarloezza/cieid/cie-id.png' in run('gresource', 'list', app / 'CIE-ID').stdout
        icons = list((extracted / 'usr/share/icons/hicolor').glob('*/apps/' + APP_ID + '.png'))
        assert len(icons) == 9
        # Resolve the installed icon name using GTK's actual icon theme loader,
        # without initializing GTK, opening a window or loading the application.
        gtk = C.CDLL('libgtk-3.so.0')
        gtk.gtk_icon_theme_new.restype = C.c_void_p
        gtk.gtk_icon_theme_set_search_path.argtypes = [C.c_void_p, C.POINTER(C.c_char_p), C.c_int]
        gtk.gtk_icon_theme_set_custom_theme.argtypes = [C.c_void_p, C.c_char_p]
        gtk.gtk_icon_theme_lookup_icon.argtypes = [C.c_void_p, C.c_char_p, C.c_int, C.c_int]
        gtk.gtk_icon_theme_lookup_icon.restype = C.c_void_p
        gtk.gtk_icon_info_get_filename.argtypes = [C.c_void_p]
        gtk.gtk_icon_info_get_filename.restype = C.c_char_p
        obj = C.CDLL('libgobject-2.0.so.0')
        obj.g_object_unref.argtypes = [C.c_void_p]
        theme = gtk.gtk_icon_theme_new()
        search = (C.c_char_p * 2)(str(extracted / 'usr/share/icons').encode(), b'/usr/share/icons')
        gtk.gtk_icon_theme_set_search_path(theme, search, 2)
        gtk.gtk_icon_theme_set_custom_theme(theme, b'hicolor')
        icon = gtk.gtk_icon_theme_lookup_icon(theme, APP_ID.encode(), 64, 0)
        assert icon
        resolved = Path(gtk.gtk_icon_info_get_filename(icon).decode())
        assert resolved.is_relative_to(extracted) and resolved.is_file()
        obj.g_object_unref(icon)
        obj.g_object_unref(theme)
        runtime = app / 'cie_native'
        native = json.loads((runtime / 'backend-manifest.json').read_text())
        assert all(hashlib.sha256((runtime / name).read_bytes()).hexdigest() == digest
                   for name, digest in native['files'].items())
        assert not (runtime / 'tests').exists()
        run('python3', ROOT / 'scripts/check_linux_firefox_abi.py',
            *(runtime / name for name in ('libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so')))
        elf_count = 0
        for path in app.rglob('*'):
            if path.is_file() and path.read_bytes()[:4] == b'\x7fELF':
                elf_count += 1
                assert 'not found' not in run('ldd', path).stdout
        assert elf_count == manifest['elfFilesChecked']
        # No maintainer scripts are allowed above, and every dpkg write/log is
        # directed into this temporary tree. No root privileges are requested.
        install = temp / 'installed'
        database = install / 'var/lib/dpkg'
        database.mkdir(parents=True)
        (database / 'status').touch()
        sentinel = install / 'home/test/.local/share/cie-package-test/paired-record'
        sentinel.parent.mkdir(parents=True)
        sentinel.write_bytes(b'synthetic user record - keep on upgrade and removal')
        base = ['dpkg', '--root=' + str(install), '--log=' + str(temp / 'dpkg.log'),
                '--force-not-root', '--force-depends', '--force-bad-path', '--no-triggers']
        run(*base, '--install', package)
        for name, digest in payload.items():
            assert hashlib.sha256((install / name).read_bytes()).hexdigest() == digest
        version = manifest['version'] + '+upgradecheck1'
        control = extracted / 'DEBIAN/control'
        control.write_text(re.sub(r'^Version: .*$', 'Version: ' + version, control.read_text(), flags=re.M))
        upgrade = temp / 'upgrade.deb'
        run('dpkg-deb', '--root-owner-group', '-Znone', '--build', extracted, upgrade)
        run(*base, '--install', upgrade)
        assert run('dpkg-query', '--admindir=' + str(database), '-W', '-f=${Version}',
                   'cie-id-desktop').stdout == version
        assert sentinel.read_bytes().startswith(b'synthetic user record')
        run(*base, '--remove', 'cie-id-desktop')
        assert sentinel.exists()
        assert all(not (install / name).exists() for name in payload)
        # Simulate the host's package resolver without invoking installation or
        # downloading anything. Failure exposes unsupported dependency versions.
        apt = run('apt-get', '--simulate', '--no-remove', 'install', package)
        summary = {'passed': True, 'package': package.name, 'payloadFilesVerified': len(payload),
                   'rootOwnershipVerified': True, 'desktopEntryValid': True,
                   'embeddedIconVerified': True, 'hicolorIcons': len(icons), 'gtkIconLookupPassed': True,
                   'elfFilesResolved': elf_count, 'nativeManifestVerified': True,
                   'snapProviderAbiPassed': True, 'isolatedDpkgInstallPassed': True,
                   'isolatedDpkgUpgradePassed': True, 'isolatedDpkgRemovePassed': True,
                   'syntheticUserDataPreserved': True, 'hostAptSimulationPassed': apt.returncode == 0,
                   'hostInstallationPerformed': False, 'appLaunched': False, 'cardTestsRun': False,
                   'browserConfigurationModified': False, 'snapPermissionsModified': False,
                   'visualDesktopValidationPerformed': False}
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(summary, indent=2) + '\n')
        report.with_suffix('.apt.log').write_text(apt.stdout + apt.stderr)
        print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    check(args.package, args.report)
