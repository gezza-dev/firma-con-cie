#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Real file-store ABI with synthetic adapter/backend. No PC/SC or credentials."""
import ctypes as c
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

if len(sys.argv) == 4:
    with tempfile.TemporaryDirectory(prefix='cie-cache-abi-') as root:
        env = dict(os.environ, CIE_PAIRING_TEST_CACHE=root,
            CIE_PAIRING_TEST_STATE=str(Path(root)/'invalidations'))
        for stage in ['seed', 'restart']:
            subprocess.run([sys.executable, __file__, *sys.argv[1:], stage], env=env, check=True)
    print('FILE_CACHE_ABI: one enrollment, restart, partial-PIN PDF/P7M, corruption stops before authentication, removal without decrypt; synthetic only')
    raise SystemExit(0)

bridge_path, backend_path, adapter_path = map(lambda x: Path(x).resolve(), sys.argv[1:4])
runtime = bridge_path.parent.parent if bridge_path.parent.name == 'tests' else bridge_path.parent
scope = os.add_dll_directory(str(runtime)) if os.name == 'nt' else None
bridge = c.CDLL(str(bridge_path)); adapter = c.CDLL(str(adapter_path))
bridge.cie_bridge_free.argtypes = [c.c_void_p]
def call(operation, *args):
    fn = getattr(bridge, 'cie_bridge_' + operation);fn.restype = c.c_void_p
    if operation == 'sign_paired_network':
        fn.argtypes = [c.c_char_p] * 6 + [c.c_void_p]
    else:
        fn.argtypes = [c.c_char_p] * len(args)
    values = [x.encode() if isinstance(x, str) else x for x in args]
    ptr = fn(*values)
    try:
        raw = c.string_at(ptr).decode()
        assert all(secret not in raw for secret in ['12345678', '5678', '1234'])
        return json.loads(raw)
    finally:
        bridge.cie_bridge_free(ptr)

assert call('load', str(backend_path), str(adapter_path))['canPair']
if sys.argv[4] == 'seed':
    pin = c.create_string_buffer(b'12345678')
    result = call('enroll', 'Reader', 'TEST', pin)
    assert result['ok'] and not pin.value and adapter.fake_enrollment_attempts() == 1
else:
    result = call('enrollments')
    assert result['storage'] == 'file-cache-v3' and len(result['records']) == 1
    assert result['records'][0]['readyForSigning'] and result['records'][0]['publicDataSaved']
    assert adapter.fake_enrollment_attempts() == 0
    root = Path(os.environ['CIE_PAIRING_TEST_CACHE'])
    source = root / 'document.pdf';source.write_bytes(b'Synthetic input')
    for format in ['pdf', 'p7m']:
        pin = c.create_string_buffer(b'5678');target = root / ('signed.' + format)
        result = call('sign_paired_network', 'Reader', 'TEST', str(source), str(target), format, pin, None)
        assert result['ok'] and target.is_file() and not pin.value, result
    before = adapter.fake_attempts()
    record = root / 'cache-v3/TEST.card';damaged = bytearray(record.read_bytes());damaged[-1] ^= 1;record.write_bytes(damaged)
    assert call('enrollments')['records'][0]['code'] == 'pairing_cache_invalid'
    pin = c.create_string_buffer(b'5678')
    result = call('sign_paired_network', 'Reader', 'TEST', str(source), str(root/'blocked.p7m'), 'p7m', pin, None)
    assert result['code'] == 'pairing_store_unavailable' and not pin.value and adapter.fake_attempts() == before, result
    assert call('forget_enrollment', 'TEST')['ok'] and not record.exists()
    assert not call('enrollments')['records'] and adapter.fake_enrollment_attempts() == 0
