#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fresh-profile first pairing: production ABI/WinCrypt, synthetic card and MY.

The MY store is memory-only; cache and invalidation files live in a temporary
test namespace. Reader access is disabled in the test bridge. No real identity,
PIN, certificate store, registry or installed component is used.
"""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('bridge', type=Path)
p.add_argument('backend', type=Path)
p.add_argument('adapter', type=Path)
p.add_argument('component', type=Path)
p.add_argument('--case', choices=['first', 'invalid-pin', 'store-failure', 'foreign-certificate'])
a = p.parse_args()
if not a.case:
    for case in ['first', 'invalid-pin', 'store-failure', 'foreign-certificate']:
        run = subprocess.run([sys.executable, str(Path(__file__).resolve()), *map(str, [a.bridge.resolve(), a.backend.resolve(), a.adapter.resolve(), a.component.resolve()]), '--case', case], capture_output=True, text=True, timeout=60)
        assert run.returncode == 0, run.stdout + run.stderr
        print(run.stdout.strip())
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix='cie-first-pairing-') as folder:
    root = Path(folder)
    (root / 'state').mkdir()
    os.environ['CIE_PAIRING_TEST_CACHE'] = str(root)
    os.environ['CIE_PAIRING_TEST_STATE'] = str(root / 'state')
    cookie = os.add_dll_directory(str(a.bridge.resolve().parent))
    lib = c.CDLL(str(a.bridge.resolve()))
    adapter = c.CDLL(str(a.adapter.resolve()))
    lib.cie_bridge_free.argtypes = [c.c_void_p]
    lib.test_component_path.argtypes = [c.c_wchar_p]
    lib.test_component_path(str(a.component.resolve()))
    checks = 0

    def check(value):
        global checks
        checks += 1
        assert value, f'{a.case}: check {checks}'

    def call(name, *args):
        fn = getattr(lib, 'cie_bridge_' + name)
        fn.restype = c.c_void_p
        ptr = fn(*[v.encode() if isinstance(v, str) else v for v in args])
        try:
            return json.loads(c.string_at(ptr).decode('utf-8'))
        finally:
            lib.cie_bridge_free(ptr)

    check(not (root / 'cache-v3').exists())
    check(lib.test_certificate_count() == 0)
    check(call('load', str(a.backend.resolve()), str(a.adapter.resolve()))['enrollmentVersion'] == 2)
    check(call('enrollments')['records'] == [])
    check(call('web_status') == {'ok': True, 'available': True})
    check(adapter.fake_enrollment_attempts() == 0)
    if a.case == 'store-failure':
        lib.test_fail_certificate_store(1)
    elif a.case == 'foreign-certificate':
        check(lib.test_add_foreign_certificate() == 1)
        check(lib.test_browser_binding() == 1)  # DER only: no owner or KSP binding.
    # Entirely synthetic PIN, consumed only by the fake adapter.
    pin = c.create_string_buffer(b'00000000' if a.case == 'invalid-pin' else b'12345678')
    result = call('enroll', 'FAKE READER', 'TEST', pin)
    check(pin.raw == bytes(len(pin)))
    check(adapter.fake_enrollment_attempts() == 1)
    check(adapter.fake_pair_attempts() == 0 and adapter.fake_web_attempts() == 0)
    if a.case == 'first':
        check(result.get('ok') is True and result.get('code') is None)
        check(all(result.get(k) is True for k in ['readyForSigning', 'publicDataSaved', 'webProvisioned', 'systemComponentAvailable']))
        check(lib.test_certificate_count() == 1)
        check(lib.test_browser_binding() == 31)  # DER, KSP, container, owner marker, public label.
        for _ in range(3):
            record = call('enrollments')['records'][0]
            check(record['webProvisioned'] is True and record['readyForSigning'] is True)
        check(len(list((root / 'cache-v3').glob('*.web'))) == 1)
    elif a.case == 'invalid-pin':
        check(result.get('code') == 'pin_incorrect')
        check(lib.test_certificate_count() == 0)
        check(call('enrollments')['records'] == [])
        check(not list((root / 'cache-v3').glob('*.web')))
    else:
        check(result.get('code') == ('web_store_unavailable' if a.case == 'store-failure' else 'web_certificate_conflict'))
        check(result.get('readyForSigning') is True and result.get('publicDataSaved') is True)
        check(result.get('webProvisioned') is False)
        check(lib.test_certificate_count() == (0 if a.case == 'store-failure' else 1))
        if a.case == 'foreign-certificate':
            check(lib.test_browser_binding() == 1)  # Pre-existing association unchanged.
    check(adapter.fake_enrollment_attempts() == 1)
    check(lib.test_reader_attempts() == 0)
    print(json.dumps({'case': a.case, 'checks': checks, 'passed': True, 'freshProfile': True,
                      'completeEnrollmentCalls': 0, 'simulatedAuthentications': 1,
                      'realCardOperations': 0, 'realUserCertificateStoreOperations': 0}))
