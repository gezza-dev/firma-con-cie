#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise real Inno installation/upgrade/repair/uninstall in an isolated tree.

Uses a distinct application ID, a non-administrative test installer and a fake
component/prerequisite. Never installs the production minidriver or uses a CIE.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from package_windows_installer import build, validate_release, sha


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iscc', type=Path, required=True)
    p.add_argument('--fake-helper', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    q = a.output.resolve()
    if q.exists():
        raise SystemExit('Use a new test report directory')
    q.mkdir(parents=True)
    checks = 0

    def check(value, message):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(message)

    release = q / 'synthetic-release'
    (release / 'web-component/backend').mkdir(parents=True)
    for name in ('Firma con CIE.exe', 'flutter_windows.dll', 'pdfium.dll', 'data/app.so',
                 'cie_native/ltv/cie-ltv-worker.jar', 'cie_native/cie_bridge.dll',
                 'cie_native/cie_card_observer.exe', 'cie_native/licenses/NOTICE.txt',
                 'cie_native/tests/fake_backend.dll', 'cie_native/tests/test_bridge.py',
                 'cie_native/ltv/tests/cie-ltv-tests.jar', 'cie_native/provenance/assembly-final.json',
                 'cie_native/ltv/jre/windows-x86_64/lib/jvm.lib',
                 'cie_native/ltv/jre/windows-x86_64/bin/server/jvm.dll',
                 'cie_native/ltv/jre/windows-x86_64/legal/java.base/LICENSE',
                 'cie_native/licenses/ltv/dependency-sources/test-sources.jar',
                 'data/flutter_assets/NOTICES.Z'):
        f = release / name
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(b'synthetic installer fixture: ' + name.encode())
    (release / 'web-component/backend/cie_web.dll').write_bytes(b'fake unexecuted DLL')
    shutil.copy2(a.fake_helper, release / 'web-component/CIE-Web-Setup.exe')
    native = release / 'cie_native'
    (native / 'backend-manifest.json').write_text(json.dumps({'files': {f.relative_to(native).as_posix(): sha(f) for f in native.rglob('*') if f.is_file()}}))
    files = {'backend/cie_web.dll': sha(release / 'web-component/backend/cie_web.dll')}
    version = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    (release / 'web-component/payload-manifest.json').write_text(json.dumps({'version': version, 'files': files}))
    validate_release(release)
    # Negative payload cases must fail before a compiler or installer is run.
    sample = release / 'web-component/backend/cie_web.dll'
    original = sample.read_bytes()
    sample.write_bytes(b'tampered')
    try:
        validate_release(release)
    except ValueError:
        check(True, 'tamper rejected')
    else:
        check(False, 'tamper accepted')
    sample.write_bytes(original)
    sentinel = release / 'private.card'
    sentinel.write_bytes(b'not real data')
    try:
        validate_release(release)
    except ValueError:
        check(True, 'private data rejected')
    else:
        check(False, 'private data accepted')
    sentinel.unlink()
    sentinel = native / 'unlisted-test.exe'
    sentinel.write_bytes(b'synthetic unlisted file')
    try:
        validate_release(release)
    except ValueError:
        check(True, 'unlisted native file rejected')
    else:
        check(False, 'unlisted native file accepted')
    sentinel.unlink()

    # The original regression: a new installer catalog with an old bridge that
    # still embeds the former ownedName() rules must never be packaged.
    native_manifest = native / 'backend-manifest.json'
    original_manifest = native_manifest.read_bytes()
    windows = json.loads(original_manifest)
    windows.update(system='windows', source_files={})
    native_manifest.write_text(json.dumps(windows))
    try:
        validate_release(release)
    except ValueError as error:
        check('Rebuild the native Windows bridge' in str(error), 'wrong stale bridge error')
    else:
        check(False, 'stale bridge accepted')
    from package_windows_installer import ROOT
    dependencies = {name: sha(ROOT / name) for name in (
        'native/platform/windows/web/setup_policy.h', 'native/platform/windows/web/card_catalog.h')}
    windows['artifacts'] = {'cie_bridge.dll': {'sha256': 'wrong', 'source_files': dependencies}}
    native_manifest.write_text(json.dumps(windows))
    try:
        validate_release(release)
    except ValueError as error:
        check('provenance' in str(error), 'wrong bridge provenance error')
    else:
        check(False, 'wrong bridge provenance accepted')
    windows['artifacts']['cie_bridge.dll']['sha256'] = sha(native / 'cie_bridge.dll')
    native_manifest.write_text(json.dumps(windows))
    validate_release(release)
    check(True, 'current bridge dependencies accepted')
    native_manifest.write_bytes(original_manifest)

    install = q / 'installed app'
    profile = q / 'synthetic-user-profile'
    profile.mkdir()
    for name in ('.key', 'paired.card', 'public.web', 'settings.json', 'preferences.json', 'image.png'):
        (profile / name).write_bytes(b'synthetic-preserved-' + name.encode())
    before = {f.name: sha(f) for f in profile.iterdir()}
    env = dict(os.environ, CIE_INSTALLER_TEST_LOG=str(q / 'helper-calls.txt'))

    def run(name, command, success=True, extra=None):
        result = subprocess.run(list(map(str, command)), env=dict(env, **(extra or {})), capture_output=True, timeout=120)
        (q / (name + '.exit.json')).write_text(json.dumps({'exitCode': result.returncode}))
        check((result.returncode == 0) == success, name + ' unexpected exit ' + str(result.returncode))
        check(before == {f.name: sha(f) for f in profile.iterdir()}, name + ' changed the profile')

    def install_args(exe, name):
        return [exe, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/LANG=english', '/LOG=' + str(q / (name + '.log'))]

    first = build(release, q / 'v1', '0.1.0', a.iscc.resolve(), a.fake_helper.resolve(), test_root=install)
    staged = Path(first['release'])
    audit = json.loads((q / 'v1/build/release-audit.json').read_text())
    check(len(audit['excludedFiles']) == 5, 'wrong development exclusions')
    for name in audit['excludedFiles']:
        check(not (staged / name).exists(), 'development file in staged release')
    for name in ('cie_native/licenses/ltv/dependency-sources/test-sources.jar',
                 'cie_native/ltv/jre/windows-x86_64/legal/java.base/LICENSE',
                 'cie_native/ltv/jre/windows-x86_64/bin/server/jvm.dll',
                 'data/flutter_assets/NOTICES.Z'):
        check(sha(staged / name) == sha(release / name), 'runtime/license changed: ' + name)
    run('preflight-failure', install_args(first['installer'], 'preflight-failure'), False,
        {'CIE_INSTALLER_TEST_FAIL': '--plan-package'})
    check(not install.exists(), 'preflight failure copied the application')
    before_text = (q / 'v1/build/before.txt').read_text(encoding='utf-8-sig')
    check('No reader, CIE or PIN is needed' in before_text, 'installer still requests a card')
    check('ComponentMissing' not in (q / 'v1/build/firma-con-cie.iss').read_text(encoding='utf-8-sig'), 'card-required message remains')
    run('install', install_args(first['installer'], 'install'))
    check((install / 'Firma con CIE.exe').read_bytes() == (release / 'Firma con CIE.exe').read_bytes(), 'fresh install file')
    # Model an installed release from before the public-name change.
    check(all(not (install / name).exists() for name in audit['excludedFiles']), 'fresh install contains test files')
    # Simulate files left by the previous full development installer.
    for name in audit['excludedFiles']:
        f = install / name
        f.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(release / name, f)
    unknown_test = install / 'cie_native/tests/user-added.txt'
    unknown_test.write_bytes(b'preserve unknown test-folder file')
    # Preserve unknown files: uninstall must use its file log, never a tree wipe.
    unknown = install / 'user-added.txt'
    unknown.write_bytes(b'preserve unknown file')
    (release / 'Firma con CIE.exe').write_bytes(b'new synthetic executable')
    second = build(release, q / 'v2', '0.1.1', a.iscc.resolve(), a.fake_helper.resolve(), test_root=install)
    run('component-install-failure', install_args(second['installer'], 'component-install-failure'), False,
        {'CIE_INSTALLER_TEST_FAIL': '--install-package'})
    check(unknown.read_bytes() == b'preserve unknown file', 'component failure removed unknown file')
    run('upgrade', install_args(second['installer'], 'upgrade'))
    check(all(not (install / name).exists() for name in audit['excludedFiles']), 'upgrade left known test files')
    check(unknown_test.read_bytes() == b'preserve unknown test-folder file', 'upgrade removed unknown test-folder file')
    check((install / 'Firma con CIE.exe').read_bytes() == b'new synthetic executable', 'upgrade did not replace app')
    check(unknown.read_bytes() == b'preserve unknown file', 'upgrade removed unknown file')
    run('repair', install_args(second['installer'], 'repair'))
    uninstaller = install / 'uninstall/unins000.exe'
    check(uninstaller.is_file(), 'uninstaller missing')
    run('unregister-failure', [uninstaller, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'], False,
        {'CIE_INSTALLER_TEST_FAIL': '--unregister-package'})
    check((install / 'Firma con CIE.exe').exists(), 'failed unregister removed app files')
    run('uninstall', [uninstaller, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LOG=' + str(q / 'uninstall.log')])
    check(not (install / 'Firma con CIE.exe').exists(), 'uninstall left app executable')
    check(unknown.read_bytes() == b'preserve unknown file', 'uninstall removed unknown file')
    check(unknown_test.read_bytes() == b'preserve unknown test-folder file', 'uninstall removed unknown test-folder file')
    calls = (q / 'helper-calls.txt').read_text().splitlines()
    for command in ('--plan-package', '--install-package', '--unregister-package', '/install'):
        check(command in calls, 'missing integration call: ' + command)
    result = {'checks': checks, 'passed': True, 'realCardOperations': 0, 'productionInstallations': 0,
              'uacRequests': 0, 'syntheticProfileUnchanged': True, 'scope': 'real Inno engine with isolated fake component', 'helperCalls': calls}
    (q / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
