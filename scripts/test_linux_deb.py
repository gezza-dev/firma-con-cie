#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Validate a .deb and its dpkg lifecycle in an isolated root (no app/card).

The isolated dpkg database intentionally has no system dependencies installed;
--force-depends is limited to this temporary root. Host dependency resolution
is separately simulated by apt-get; neither operation installs on the host.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
from ltv_runtime import runtime_architecture
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'it.giancarloezza.prototype.cie_flutter_prototype'


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, text=True)


def check(package, report, upgrade_from=None):
    package = package.resolve()
    manifest = json.loads((package.parent / 'package-manifest.json').read_text())
    assert hashlib.sha256(package.read_bytes()).hexdigest() == manifest['sha256']
    from linux_package_common import validate_release_version
    assert manifest['package'] == 'firma-con-cie'
    assert run('dpkg-deb', '-f', package, 'Package').stdout.strip() == 'firma-con-cie'
    assert package.name == f"firma-con-cie_{manifest['version']}_{manifest['architecture']}.deb"
    validate_release_version(manifest['version'])
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
        assert all(name.startswith(('opt/firma-con-cie/', 'usr/bin/', 'usr/share/')) for name in payload)
        assert not any('tests' in Path(name).parts or '.key' == Path(name).name for name in payload)
        tool = extracted / 'usr/share/doc/firma-con-cie/tools/configure_chrome_linux.py'
        assert tool.read_bytes() == (ROOT / 'scripts/configure_chrome_linux.py').read_bytes()
        assert (extracted / 'usr/share/doc/firma-con-cie/LINUX_CHROME.md').is_file()
        for name in ('STATUS.md', 'WEB_AUTHENTICATION.md'):
            assert (extracted / 'usr/share/doc/firma-con-cie' / name).read_bytes() == (ROOT / 'docs' / name).read_bytes()
        launcher = extracted / 'usr/bin/Firma con CIE'
        assert launcher.stat().st_mode & 0o111
        run('sh', '-n', launcher)
        assert launcher.read_text() == '#!/bin/sh\nexec "/opt/firma-con-cie/Firma con CIE" "$@"\n'
        desktop = extracted / 'usr/share/applications' / (APP_ID + '.desktop')
        run('desktop-file-validate', desktop)
        assert 'Exec="/usr/bin/Firma con CIE"\n' in desktop.read_text()
        assert 'TryExec=/usr/bin/Firma con CIE\n' in desktop.read_text()
        assert 'Icon=' + APP_ID + '\n' in desktop.read_text()
        app = extracted / 'opt/firma-con-cie'
        assert '/it/giancarloezza/cieid/cie-id.png' in run('gresource', 'list', app / 'Firma con CIE').stdout
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
        assert (runtime / 'browser_setup/firefox_setup.py').is_file()
        assert (runtime / 'browser_setup/chrome_setup.py').is_file()
        isolated_home = temp / 'chrome-test-home'
        isolated_home.mkdir(mode=0o700)
        inspection = subprocess.run([
            '/usr/bin/python3', '-B', str(runtime / 'browser_setup/chrome_setup.py'), '--action', 'inspect'],
            env={'HOME': str(isolated_home), 'XDG_DATA_HOME': str(isolated_home / '.local/share')},
            capture_output=True, text=True, check=True, timeout=20)
        assert json.loads(inspection.stdout)['ok'] is True
        assert not list(isolated_home.iterdir())
        assert (runtime / 'browser_setup/libcie_browser_setup_guard.so').is_file()
        assert (extracted / 'usr/share/doc/firma-con-cie/LINUX_FIREFOX_SETUP.md').is_file()
        assert not (runtime / 'libcie_setup_no_load_probe.so').exists()
        native = json.loads((runtime / 'backend-manifest.json').read_text())
        assert all(hashlib.sha256((runtime / name).read_bytes()).hexdigest() == digest
                   for name, digest in native['files'].items())
        assert not (runtime / 'tests').exists()
        ltv_checked = False
        if native.get('ltv'):
            architecture = runtime_architecture('Linux')
            assert native['ltv']['architectures'] == [architecture]
            java = runtime / 'ltv/jre' / architecture / 'bin/java'
            assert java.is_file() and os.access(java, os.X_OK)
            assert not (runtime / 'ltv/tests').exists()
            assert (java.parent.parent / 'legal/java.base/LICENSE').is_file()
            # Execute the packaged production worker after relocation. It must
            # work without system Java and must not turn an unsigned PDF into LTA.
            environment = {k: v for k, v in os.environ.items()
                           if k.upper() in {'HOME', 'LANG', 'LC_ALL', 'TEMP', 'TMP'}}
            result = subprocess.run([
                str(java), '-Xmx512m', '-Djava.awt.headless=true',
                '-cp', str(runtime / 'ltv/cie-ltv-worker.jar') + ':' + str(runtime / 'ltv/lib/*'),
                'it.cieid.ltv.Worker', str(ROOT / 'assets/prova.pdf'), str(runtime / 'ltv/trust')],
                env=environment, capture_output=True, text=True, check=True, timeout=90)
            value = json.loads(result.stdout)
            assert value['ok'] and value['signatureCount'] == 0
            assert value['allSignaturesLtaValid'] is False
            ltv_checked = True
        run('python3', ROOT / 'scripts/check_linux_firefox_abi.py',
            *(runtime / name for name in ('libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so')))
        elf_count = 0
        for path in app.rglob('*'):
            if path.is_file() and path.read_bytes()[:4] == b'\x7fELF':
                elf_count += 1
                if path.is_relative_to(runtime / 'ltv/jre'):
                    # Java loads libjvm before its JNI libraries. Model that
                    # private loader context for standalone ldd; the production
                    # worker above runs without LD_LIBRARY_PATH or system Java.
                    environment = dict(os.environ)
                    environment['LD_LIBRARY_PATH'] = os.pathsep.join(map(str, (
                        java.parent.parent / 'lib', java.parent.parent / 'lib/server')))
                    linked = subprocess.run(['ldd', str(path)], env=environment,
                                            capture_output=True, text=True, check=True).stdout
                else:
                    linked = run('ldd', path).stdout
                assert 'not found' not in linked, str(path)
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
                '--force-not-root', '--force-depends', '--force-bad-path', '--no-triggers',
                '--path-include=/usr/share/doc/*', '--path-include=/usr/share/licenses/*']
        if upgrade_from:
            previous = temp / 'previous'
            run('dpkg-deb', '--raw-extract', upgrade_from.resolve(), previous)
            assert {p.name for p in (previous / 'DEBIAN').iterdir()} == {'control', 'md5sums'}
            assert run('dpkg-deb', '-f', upgrade_from.resolve(), 'Package').stdout.strip() == 'firma-con-cie'
            run(*base, '--install', upgrade_from.resolve())
            old_files = {p.relative_to(previous).as_posix() for p in previous.rglob('*')
                         if p.is_file() and 'DEBIAN' not in p.relative_to(previous).parts}
        run(*base, '--install', package)
        if upgrade_from:
            assert all(not (install / name).exists() for name in old_files - set(payload))
            assert sentinel.read_bytes().startswith(b'synthetic user record')
        for name, digest in payload.items():
            assert hashlib.sha256((install / name).read_bytes()).hexdigest() == digest
        version = manifest['version'] + '+upgradecheck1'
        control = extracted / 'DEBIAN/control'
        control.write_text(re.sub(r'^Version: .*$', 'Version: ' + version, control.read_text(), flags=re.M))
        upgrade = temp / 'upgrade.deb'
        run('dpkg-deb', '--root-owner-group', '-Znone', '--build', extracted, upgrade)
        run(*base, '--install', upgrade)
        assert run('dpkg-query', '--admindir=' + str(database), '-W', '-f=${Version}',
                   'firma-con-cie').stdout == version
        assert sentinel.read_bytes().startswith(b'synthetic user record')
        run(*base, '--remove', 'firma-con-cie')
        assert sentinel.exists()
        assert all(not (install / name).exists() for name in payload)
        # Simulate the host's package resolver without invoking installation or
        # downloading anything. Failure exposes unsupported dependency versions.
        apt = run('apt-get', '--simulate', '--no-remove', 'install', package)
        summary = {'passed': True, 'package': package.name, 'payloadFilesVerified': len(payload),
                   'rootOwnershipVerified': True, 'desktopEntryValid': True,
                   'embeddedIconVerified': True, 'hicolorIcons': len(icons), 'gtkIconLookupPassed': True,
                   'elfFilesResolved': elf_count, 'nativeManifestVerified': True,
                   'privateDssWorkerRelocationPassed': ltv_checked,
                   'snapProviderAbiPassed': True, 'isolatedDpkgInstallPassed': True,
                   'chromeHelperReadOnlyInspectionPassed': True,
                   'isolatedDpkgUpgradePassed': True, 'isolatedDpkgRemovePassed': True,
                   'previousPrefixUpgradePassed': bool(upgrade_from),
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
    parser.add_argument('--upgrade-from', type=Path, help='Also test migration from a prior .deb in the isolated root')
    args = parser.parse_args()
    check(args.package, args.report, args.upgrade_from)
