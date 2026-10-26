#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Install/upgrade/remove a test package ONLY inside an isolated build root.

Requires /.cie-isolated-root, a non-identity user namespace, no PC/SC socket or
USB device tree. Never run this against the host. Test homes are synthetic.
"""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import tempfile
import time

from linux_package_common import ROOT, PACKAGE, APP_ID, PREFIX, run, sha
from package_linux_distribution import elf_files, target_libraries
from ltv_runtime import runtime_architecture


def require_isolated_root():
    if not Path('/.cie-isolated-root').is_file():
        raise RuntimeError('Refusing installation outside the marked disposable root')
    mapping = Path('/proc/self/uid_map').read_text().split()
    if len(mapping) != 3 or mapping[1] == '0' or mapping[2] != '1' or os.geteuid() != 0:
        raise RuntimeError('A one-ID rootless namespace is required for this test')
    if Path('/run/pcscd').exists() or Path('/dev/bus/usb').exists():
        raise RuntimeError('Card interfaces must not be available to this test')


def manager(kind, operation, package=None):
    require_isolated_root()
    if kind == 'deb':
        args = ['apt-get', '-y', '--no-install-recommends', '-o', 'Dpkg::Options::=--path-include=/usr/share/doc/*', '-o', 'Dpkg::Options::=--path-include=/usr/share/licenses/*', 'install', package] if operation != 'remove' else ['dpkg', '--remove', PACKAGE]
    elif kind == 'rpm':
        args = ['dnf', '-y', '--setopt=install_weak_deps=False', '--setopt=tsflags=', 'install', package] if operation != 'remove' else ['dnf', '-y', 'remove', '--no-autoremove', PACKAGE]
    else:
        # Minimal OCI images omit documentation by default. Override that only
        # for these disposable test transactions, so every payload hash is checked.
        config = Path('/tmp/cie-package-pacman.conf')
        config.write_text('\n'.join(line for line in Path('/etc/pacman.conf').read_text().splitlines()
                                   if not line.lstrip().startswith('NoExtract')) + '\n')
        args = ['pacman', '--config', config, '--noconfirm', '-U', package] if operation != 'remove' else ['pacman', '--config', config, '--noconfirm', '-R', PACKAGE]
    return run(*args)


def verify_installed(manifest, kind):
    if kind == "deb":
        version = run("dpkg-query", "-W", "-f=${Version}", PACKAGE).stdout
    elif kind == "rpm":
        version = run("rpm", "-q", "--qf", "%{VERSION}-%{RELEASE}", PACKAGE).stdout
    else:
        version = run("pacman", "-Q", PACKAGE).stdout.split()[1]
    assert version == manifest["version"], (version, manifest["version"])
    for name, digest in manifest['files'].items():
        if not name.startswith(('opt/firma-con-cie/', 'usr/bin/', 'usr/share/')):
            raise ValueError('Unexpected payload prefix')
        path = Path('/') / name
        assert path.is_file() and sha(path) == digest, name
        assert path.stat().st_uid == path.stat().st_gid == 0, name
        assert not path.stat().st_mode & 0o7000, name
    app = Path('/') / PREFIX
    runtime = app / 'cie_native'
    native = json.loads((runtime / 'backend-manifest.json').read_text())
    assert all(sha(runtime / name) == digest for name, digest in native['files'].items())
    assert not (runtime / 'tests').exists()
    elfs = elf_files(app, manifest['architecture'])
    target_libraries(app, elfs)
    run('desktop-file-validate', Path('/usr/share/applications') / (APP_ID + '.desktop'))
    assert len(list(Path('/usr/share/icons/hicolor').glob('*/apps/' + APP_ID + '.png'))) == 9
    assert '/it/giancarloezza/cieid/cie-id.png' in run('gresource', 'list', app / 'Firma con CIE').stdout
    assert Path('/usr/bin/Firma con CIE').read_text() == '#!/bin/sh\nexec "/opt/firma-con-cie/Firma con CIE" "$@"\n'
    for name in ['BUILDING.md', 'STATUS.md', 'LINUX_DISTRIBUTION_PACKAGES.md']:
        assert Path('/usr/share/doc/firma-con-cie', name).read_bytes() == (ROOT / 'docs' / name).read_bytes()
    for browser in ['firefox', 'chrome']:
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(['python3', '-B', str(runtime / 'browser_setup' / (browser + '_setup.py')),
                                     '--action', 'inspect'], env={'HOME': home, 'PATH': '/usr/bin:/bin',
                                     'XDG_DATA_HOME': home + '/data'}, text=True, capture_output=True,
                                     check=True, timeout=25)
            assert json.loads(result.stdout)['ok']
            assert not list(Path(home).iterdir())
    if native.get('ltv'):
        architecture = runtime_architecture('Linux')
        assert native['ltv']['architectures'] == [architecture]
        java = runtime / 'ltv/jre' / architecture / 'bin/java'
        result = run(java, '-Xmx512m', '-Djava.awt.headless=true', '-cp',
                     str(runtime / 'ltv/cie-ltv-worker.jar') + ':' + str(runtime / 'ltv/lib/*'),
                     'it.cieid.ltv.Worker', ROOT / 'assets/prova.pdf', runtime / 'ltv/trust')
        value = json.loads(result.stdout)
        assert value['ok'] and value['signatureCount'] == 0 and not value['allSignaturesLtaValid']
    run('python3', ROOT / 'scripts/check_linux_firefox_abi.py',
        *(runtime / name for name in ['libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so']))
    return len(elfs)


def read_xvfb_display(readfd, timeout=12):
    """Xvfb may write the digits and terminating newline in separate writes."""
    deadline = time.monotonic() + timeout
    value = b''
    try:
        while not value.endswith(b'\n'):
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([readfd], [], [], remaining)[0]:
                raise RuntimeError('Xvfb startup timed out')
            chunk = os.read(readfd, 32)
            if not chunk or len(value) + len(chunk) > 128:
                raise RuntimeError('Xvfb closed its display handshake prematurely')
            value += chunk
        number = value.decode('ascii').strip()
        if not number.isdigit():
            raise RuntimeError('Invalid Xvfb display number')
        return ':' + number
    finally:
        os.close(readfd)


def headless_gui(report_dir, guard, executable='/opt/firma-con-cie/Firma con CIE', startup_delay=6):
    """Launch the real Release app on a private virtual display, PC/SC blocked."""
    with tempfile.TemporaryDirectory() as home, (report_dir / 'headless-gui.log').open('w') as log:
        readfd, writefd = os.pipe()
        server = subprocess.Popen(['Xvfb', '-displayfd', str(writefd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp', '-ac'],
                                  stdout=log, stderr=subprocess.STDOUT, pass_fds=(writefd,))
        os.close(writefd)
        app = None
        try:
            display = read_xvfb_display(readfd)
            assert server.poll() is None, 'Xvfb did not allocate a private display'
            env = dict(os.environ, HOME=home, XDG_DATA_HOME=home + '/data', XDG_CONFIG_HOME=home + '/config',
                       XDG_CACHE_HOME=home + '/cache', DISPLAY=display, GDK_BACKEND='x11',
                       LD_PRELOAD=str(guard), LIBGL_ALWAYS_SOFTWARE='1', NO_AT_BRIDGE='1')
            app = subprocess.Popen([str(executable)], env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
            time.sleep(startup_delay)
            assert app.poll() is None, 'Release app exited on the target distribution'
            # Root framebuffer capture is local to Xvfb, with no host display.
            x = C.CDLL('libX11.so.6')
            x.XOpenDisplay.argtypes = [C.c_char_p]; x.XOpenDisplay.restype = C.c_void_p
            connection = x.XOpenDisplay(display.encode()); assert connection
            x.XDefaultRootWindow.argtypes = [C.c_void_p]; x.XDefaultRootWindow.restype = C.c_ulong
            window = x.XDefaultRootWindow(connection)
            class XImage(C.Structure):
                _fields_ = [('width', C.c_int), ('height', C.c_int), ('xoffset', C.c_int), ('format', C.c_int),
                            ('data', C.c_void_p), ('byte_order', C.c_int), ('bitmap_unit', C.c_int),
                            ('bitmap_bit_order', C.c_int), ('bitmap_pad', C.c_int), ('depth', C.c_int),
                            ('bytes_per_line', C.c_int), ('bits_per_pixel', C.c_int)]
            x.XGetImage.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_ulong, C.c_int]
            x.XGetImage.restype = C.c_void_p
            raw = x.XGetImage(connection, window, 0, 0, 1280, 800, C.c_ulong(-1).value, 2)
            assert raw
            info = C.cast(raw, C.POINTER(XImage)).contents
            assert info.bits_per_pixel == 32
            data = C.string_at(info.data, info.bytes_per_line * info.height)
            rgb = bytearray()
            for row in range(info.height):
                line = data[row * info.bytes_per_line:row * info.bytes_per_line + info.width * 4]
                for col in range(0, len(line), 4):
                    rgb.extend((line[col + 2], line[col + 1], line[col]))
            colors = len({bytes(rgb[n:n + 3]) for n in range(0, len(rgb), 3)})
            assert colors > 20, 'Virtual framebuffer did not show the rendered GUI'
            (report_dir / 'headless-gui.ppm').write_bytes(b'P6\n1280 800\n255\n' + rgb)
            return {'started': True, 'renderedColors': colors, 'virtualDisplayOnly': True,
                    'pcscBlocked': True, 'desktopManualValidation': False}
        finally:
            if app and app.poll() is None:
                # Terminate the isolated process group, including its observer.
                # Window-manager close semantics remain a desktop VM check.
                os.killpg(app.pid, signal.SIGTERM)
                try: app.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(app.pid, signal.SIGKILL); app.wait(timeout=5)
            server.terminate(); server.wait(timeout=5)


def check(package, upgrade, kind, report, guard):
    require_isolated_root()
    package, upgrade = package.resolve(), upgrade.resolve()
    manifest = json.loads((package.parent / 'package-manifest.json').read_text())
    upgraded = json.loads((upgrade.parent / 'package-manifest.json').read_text())
    assert sha(package) == manifest['sha256'] and sha(upgrade) == upgraded['sha256']
    assert manifest['version'] != upgraded['version']
    if kind == 'rpm':
        assert not run('rpm', '-qp', '--scripts', package).stdout.strip()
        assert not run('rpm', '-qp', '--triggers', package).stdout.strip()
    elif kind == 'arch':
        listing = run('bsdtar', '-tf', package).stdout.splitlines()
        assert '.INSTALL' not in listing
    report.parent.mkdir(parents=True, exist_ok=True)
    sentinel = Path('/home/cie-synthetic/.local/share/cie-package-test/paired-record')
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    sentinel.write_bytes(b'synthetic user data - preserve')
    steps = {}
    try:
        if Path('/opt/firma-con-cie/Firma con CIE').exists():
            manager(kind, 'remove')
        result = manager(kind, 'install', package)
        (report.parent / 'install.log').write_text(result.stdout + result.stderr)
        count = verify_installed(manifest, kind)
        steps['install'] = True
        gui = headless_gui(report.parent, guard)
        result = manager(kind, 'upgrade', upgrade)
        (report.parent / 'upgrade.log').write_text(result.stdout + result.stderr)
        verify_installed(upgraded, kind)
        assert sentinel.read_bytes() == b'synthetic user data - preserve'
        steps['upgrade'] = True
        result = manager(kind, 'remove')
        (report.parent / 'remove.log').write_text(result.stdout + result.stderr)
        assert not Path('/opt/firma-con-cie/Firma con CIE').exists()
        assert not Path('/usr/bin/Firma con CIE').exists()
        assert sentinel.read_bytes() == b'synthetic user data - preserve'
        steps['remove'] = True
    except subprocess.CalledProcessError as exc:
        (report.parent / 'failure.log').write_text((exc.stdout or '') + (exc.stderr or ''))
        raise
    result = dict(passed=True, package=package.name, format=kind, isolatedLifecycle=steps,
                  payloadFilesVerified=len(manifest['files']), elfFilesResolved=count,
                  rootOwnershipVerified=True, nativeManifestVerified=True,
                  privateDssWorkerRelocationPassed=True, snapProviderAbiPassed=True,
                  browserHelperReadOnlyInspectionsPassed=True, syntheticUserDataPreserved=True,
                  gui=gui, hostInstallationPerformed=False, browserConfigurationModified=False,
                  snapPermissionsModified=False, cardTestsRun=False)
    report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--upgrade-package', type=Path, required=True)
    parser.add_argument('--format', choices=['deb', 'rpm', 'arch'], required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--no-card-guard', type=Path, required=True)
    args = parser.parse_args()
    check(args.package, args.upgrade_package, args.format, args.report, args.no_card_guard)
