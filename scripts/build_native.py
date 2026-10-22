#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the vendored shared backend, SDK, bridge and card adapter together."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import stat

ROOT = Path(__file__).resolve().parents[1]

def run(*args):
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def copy_binary(source, destination):
    # A fresh inode avoids stale macOS executable-signature caches when a
    # previously executed runtime is refreshed. Replace atomically, never write
    # over an executable that may still be mapped into a running process.
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temporary:
        staging = Path(temporary.name)
    try:
        shutil.copyfile(source, staging)
        staging.chmod(stat.S_IMODE(source.stat().st_mode))
        staging.replace(destination)
    finally:
        staging.unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dependency-prefix', type=Path, required=True)
    parser.add_argument('--system', choices=['macos', 'linux', 'windows'], default={'Darwin':'macos','Linux':'linux','Windows':'windows'}[platform.system()])
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--architectures', help='macOS: arm64 or arm64;x86_64; prefix must match')
    parser.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 6))
    args = parser.parse_args()
    prefix = args.dependency_prefix.resolve()
    build = (args.build_dir or ROOT/'.build'/('native-'+args.system)).resolve()
    output = (args.output or ROOT/'native/runtime'/args.system).resolve()
    cross = args.toolchain is not None
    options = ['-DCMAKE_BUILD_TYPE=Release', '-DCIE_BUILD_BACKEND=ON', '-DCIE_DEPENDENCY_PREFIX='+str(prefix)]
    if cross:
        options += ['-DCMAKE_TOOLCHAIN_FILE='+str(args.toolchain.resolve())]
    if args.system == 'macos':
        options += ['-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0']
        if args.architectures:
            options += ['-DCMAKE_OSX_ARCHITECTURES='+args.architectures]
    run('cmake', '-S', ROOT/'native', '-B', build, '-G', 'Ninja', *options)
    run('cmake', '--build', build, '--parallel', args.jobs)
    if not cross:
        run('ctest', '--test-dir', build, '--output-on-failure')
    if args.system == 'linux':
        run('python3', ROOT/'scripts/check_linux_firefox_abi.py',
            build/'libcie_linux_pkcs11.so', build/'libcie_web.so',
            build/'backend/libcie-pkcs11.so', '--report', build/'firefox-snap-abi.json')
    output.mkdir(parents=True, exist_ok=True)
    fetcher = build/'backend/cie_sign_sdk'/('cie_crl_fetch'+('.exe' if args.system == 'windows' else ''))
    copy_binary(fetcher, output/fetcher.name)
    observer = build/('cie_card_observer'+('.exe' if args.system == 'windows' else ''))
    copy_binary(observer, output/observer.name)
    # Refresh a reused private DSS runtime with this exact native transport.
    if (output/'ltv/fetcher').is_dir():
        copy_binary(fetcher, output/'ltv/fetcher'/fetcher.name)
    suffix = {'macos':'.dylib','linux':'.so','windows':'.dll'}[args.system]
    libprefix = '' if args.system == 'windows' else 'lib'
    for name, directory in [('cie_bridge', build), ('cie_card_adapter', build), ('cie_web', build), ('cie-pkcs11', build/'backend')]:
        path = directory/(libprefix+name+suffix)
        copy_binary(path, output/path.name)
    # A Windows MinGW runtime stays private; do not copy files into System32 or
    # mix MinGW C++ objects with those produced by the Flutter MSVC toolchain.
    if args.system == 'windows':
        compiler = 'x86_64-w64-mingw32-g++-posix' if cross else 'g++'
        for name in ['libwinpthread-1.dll','libgcc_s_seh-1.dll','libstdc++-6.dll']:
            path = Path(subprocess.check_output([compiler, '-print-file-name='+name], text=True).strip())
            if not path.is_file():
                raise SystemExit('Missing private MinGW runtime: '+name)
            copy_binary(path, output/name)
    if args.system == 'linux':
        copy_binary(build/'libcie_linux_pkcs11.so', output/'libcie_linux_pkcs11.so')
    licenses = output/'licenses'
    (output/'tests').mkdir(exist_ok=True)
    for name in ['cie_enrollment_state_tests','cie_web_probe','cie_web_policy_tests','cie_web_sign_request_tests','cie_web_abi_tests','cie_web_crypto_tests']:
        binary=build/(name+('.exe' if args.system=='windows' else ''))
        copy_binary(binary,output/'tests'/binary.name)
    if args.system=='windows':
        copy_binary(build/'cie_web_store_tests.exe',output/'tests/cie_web_store_tests.exe')
    for name in ['cie_cache_crypto_tests'+('.exe' if args.system=='windows' else ''),'cie_pin_tests'+('.exe' if args.system=='windows' else ''),'cie_identification_tests'+('.exe' if args.system=='windows' else ''),'cie_document_tests'+('.exe' if args.system=='windows' else ''),'cie_signing_time_tests'+('.exe' if args.system=='windows' else ''),'cie_cosign_tests'+('.exe' if args.system=='windows' else ''),'cie_network_test_client'+('.exe' if args.system=='windows' else ''),'cie_pairing_store_tests'+('.exe' if args.system=='windows' else ''),'cie_pairing_sod_tests'+('.exe' if args.system=='windows' else ''),libprefix+'cie_bridge_pairing_tests'+suffix,libprefix+'cie_bridge_file_cache_tests'+suffix,libprefix+'fake_backend'+suffix,libprefix+'fake_card_adapter'+suffix]:
        copy_binary(build/name,output/'tests'/name)
    shutil.copy2(ROOT/'native/tests/test_bridge.py',output/'tests/test_bridge.py')
    shutil.copy2(ROOT/'native/tests/test_network.py',output/'tests/test_network.py')
    shutil.copy2(ROOT/'native/tests/test_pairing.py',output/'tests/test_pairing.py')
    shutil.copy2(ROOT/'native/tests/test_pairing_file_store.py',output/'tests/test_pairing_file_store.py')
    shutil.copy2(ROOT/'native/tests/test_file_cache_enrollment.py',output/'tests/test_file_cache_enrollment.py')
    (output/'tests/test_pairing_owner_migration.py').unlink(missing_ok=True)
    shutil.copy2(ROOT/'native/tests/test_pin_invalidation.py',output/'tests/test_pin_invalidation.py')
    shutil.copy2(ROOT/'native/tests/test_enrollment.py',output/'tests/test_enrollment.py')
    shutil.copy2(ROOT/'native/tests/test_web_bridge.py',output/'tests/test_web_bridge.py')
    licenses.mkdir(exist_ok=True)
    shutil.copy2(ROOT/'LICENSE', licenses/'prototype-LICENSE')
    shutil.copy2(ROOT/'NOTICE.md', licenses/'prototype-NOTICE.md')
    shutil.copytree(ROOT/'native/backend/LICENSES', licenses/'LICENSES', dirs_exist_ok=True)
    shutil.copytree(ROOT/'LICENSES', licenses/'prototype', dirs_exist_ok=True)
    for name in ['LICENSE.txt','THIRD_PARTY_NOTICES.md','LICENSE_AUDIT.md']:
        shutil.copy2(ROOT/'native/backend'/name, licenses/name)
    shutil.copytree(ROOT/'native/backend/cie_sign_sdk/trust', licenses/'cie-authorities', dirs_exist_ok=True)
    for name in ['cie_sdk_tests','cie_security_tests','cie_trust_probe']:
        path = build/'backend/cie_sign_sdk'/(name+('.exe' if args.system == 'windows' else ''))
        if path.is_file():
            (output/'tests').mkdir(exist_ok=True)
            copy_binary(path, output/'tests'/path.name)
    handles = build/'backend'/('cie_handle_tests'+('.exe' if args.system == 'windows' else ''))
    if handles.is_file():
        (output/'tests').mkdir(exist_ok=True)
        copy_binary(handles, output/'tests'/handles.name)
    sources = {str(p.relative_to(ROOT)):sha(p) for folder in ['native','scripts']
        for p in sorted((ROOT/folder).rglob('*'))
        if p.is_file() and not any(part in ['runtime','__pycache__'] for part in p.relative_to(ROOT).parts)}
    manifest = dict(system=args.system, bridge_abi=1, backend='source-vendored portable backend',
        architectures=(args.architectures.split(';') if args.architectures else ['x86_64'] if args.system == 'windows' else [platform.machine()]),
        upstream=json.loads((ROOT/'native/backend-upstream.json').read_text())['commit'],
        source_files=sources, dependency_lock=json.loads((ROOT/'native/backend/scripts/dependencies.lock.json').read_text()),
        cross_compiled=cross, tests_executed_on_build_host=not cross,
        full_pin_signing=True, enrollment=True, enrollment_version=2, automatic_idle_card_observation=True,
        card_observation_process=True, card_observation_protocol=1, enrollment_scope="private-prototype-current-user",
        protected_pin_prefix=True, partial_pin_signing=True, enrollment_cache_access=False,
        pairing_storage="per-user-file-cache-v3", os_credential_store=False, legacy_pairings_imported=False,
        file_cache_crypto="AES-256-CBC+HMAC-SHA256-encrypt-then-MAC", local_key_in_private_file=True,
        web_authentication_abi=1, web_authentication_hardware_validated=False,
        linux_firefox_pkcs11=(args.system == 'linux'), linux_web_full_pin_only=(args.system == 'linux'),
        linux_firefox_snap_core24_abi_verified=(args.system == 'linux'),
        linux_firefox_snap_public_certificates_only=(args.system == 'linux'),
        snap_permissions_modified=False,
        browser_registration_performed=False,
        pin_change=True, puk_unblock=True, persistent_pairing_invalidation=True, nonblocking_pairing_cleanup=True,
        files={str(p.relative_to(output)):sha(p) for p in output.rglob('*') if p.is_file() and p.name!='backend-manifest.json'})
    (output/'backend-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('Private runtime prepared:', output)
    if cross:
        print('Cross-compiled only: run the tests on the target OS before claiming runtime/hardware support.')

if __name__ == '__main__':
    main()
