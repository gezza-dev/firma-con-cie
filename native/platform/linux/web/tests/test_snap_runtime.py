#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Firefox Snap NSS in memory, mandatory PC/SC guard; no browser/profile changes."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import shlex
import subprocess


def inside(runtime, guard_path):
    assert os.environ.get('SNAP_NAME') == 'firefox', 'Must run inside Firefox Snap'
    guard = C.CDLL(str(guard_path))
    guard.CieNoCardCalls.restype = C.c_uint
    # Verify that the guard, not pcsc-lite, owns the global entry point.
    assert C.cast(C.CDLL(None).SCardEstablishContext, C.c_void_p).value == C.cast(guard.SCardEstablishContext, C.c_void_p).value
    provider = C.CDLL(str(runtime / 'libcie_linux_pkcs11.so'))
    assert not hasattr(provider, 'CieTestMetric')
    provider.CieLinuxWebAbiVersion.restype = C.c_uint
    assert provider.CieLinuxWebAbiVersion() == 1
    nss = C.CDLL('/snap/firefox/current/usr/lib/firefox/libnss3.so')
    def api(name, result, *args):
        fn = getattr(nss, name)
        fn.restype = result
        fn.argtypes = list(args)
        return fn
    no_db = api('NSS_NoDB_Init', C.c_int, C.c_void_p)
    shutdown = api('NSS_Shutdown', C.c_int)
    load = api('SECMOD_LoadUserModule', C.c_void_p, C.c_char_p, C.c_void_p, C.c_int)
    find = api('SECMOD_FindModule', C.c_void_p, C.c_char_p)
    unload = api('SECMOD_UnloadUserModule', C.c_int, C.c_void_p)
    destroy = api('SECMOD_DestroyModule', None, C.c_void_p)
    version = api('NSS_GetVersion', C.c_char_p)
    assert no_db(None) == 0
    handle = found = None
    try:
        path = str(runtime / 'libcie_linux_pkcs11.so')
        assert '"' not in path and '\n' not in path
        handle = load(f'name="CIE Snap Software Test" library="{path}"'.encode(), None, 0)
        assert handle
        found = find(b'CIE Snap Software Test')
        assert found, 'Provider must be in the NSS loaded-module list'
    finally:
        if found:
            destroy(found)
        if handle:
            assert unload(handle) == 0
            destroy(handle)
        assert shutdown() == 0
    return dict(passed=True, nssVersion=version().decode(), actualFirefoxSnap=True,
                productionModuleLoadedInMemory=True, pcscBlocked=True,
                blockedPcscAttempts=guard.CieNoCardCalls(), realCardOperations=0,
                pinPrompts=0, browserStarted=False, browserProfileAccessed=False,
                snapPermissionsModified=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime', type=Path)
    parser.add_argument('guard', type=Path)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--fake-module', type=Path,
                        help='Also exercise full-PIN signing with the isolated simulated-card provider')
    args = parser.parse_args()
    runtime, guard = args.runtime.resolve(), args.guard.resolve()
    assert guard.name == 'libcie_linux_no_card_guard.so' and guard.is_file()
    if args.inside:
        print(json.dumps(inside(runtime, guard)))
        return
    command = ('LD_LIBRARY_PATH=/snap/firefox/current/usr/lib/firefox:"$LD_LIBRARY_PATH" '
               'LD_PRELOAD=' + shlex.quote(str(guard)) + ' python3 ' +
               shlex.join([str(Path(__file__).resolve()), str(runtime), str(guard), '--inside']))
    completed = subprocess.run(['snap', 'run', '--shell', 'firefox', '-c', command],
                               capture_output=True, text=True, timeout=30, check=True)
    result = json.loads(completed.stdout)
    if args.fake_module:
        fake = args.fake_module.resolve()
        assert fake.name == 'libcie_linux_pkcs11_fake.so' and fake.is_file()
        test = Path(__file__).with_name('test_nss.py').resolve()
        synthetic_command = ('LD_LIBRARY_PATH=/snap/firefox/current/usr/lib/firefox:"$LD_LIBRARY_PATH" '
                             'LD_PRELOAD=' + shlex.quote(str(guard)) + ' python3 ' +
                             shlex.join([str(test), str(fake), '--snap-public']))
        synthetic = subprocess.run(['snap', 'run', '--shell', 'firefox', '-c', synthetic_command],
                                   capture_output=True, text=True, timeout=30, check=True)
        result = dict(passed=True, production=result, synthetic=json.loads(synthetic.stdout))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
