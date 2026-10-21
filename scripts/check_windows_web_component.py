#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Probe the shipped bridge's component metadata; no card/authentication/cache access.

--expect-available is appropriate only on a PC with the component installed.
The probe calls web_status, never load/detect/enroll/test/sign or PIN operations.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime', type=Path, required=True)
p.add_argument('--expect-available', action='store_true')
p.add_argument('--report', type=Path)
a = p.parse_args()
if os.name != 'nt':
    raise SystemExit('Windows only')
runtime = a.runtime.resolve()
cookie = os.add_dll_directory(str(runtime))
bridge = ctypes.CDLL(str(runtime / 'cie_bridge.dll'))
bridge.cie_bridge_abi_version.restype = ctypes.c_uint32
bridge.cie_bridge_web_status.restype = ctypes.c_void_p
bridge.cie_bridge_free.argtypes = [ctypes.c_void_p]
value = bridge.cie_bridge_web_status()
if not value:
    raise SystemExit('Empty bridge status')
try:
    status = json.loads(ctypes.string_at(value).decode('utf-8'))
finally:
    bridge.cie_bridge_free(value)
result = {'bridgeAbi': bridge.cie_bridge_abi_version(), 'componentAvailable': status.get('available'),
          'ok': status.get('ok'), 'cardOperations': 0, 'pinOperations': 0, 'systemWrites': 0}
result['passed'] = result['bridgeAbi'] == 1 and result['ok'] is True and (
    not a.expect_available or result['componentAvailable'] is True)
if a.report:
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, indent=2))
sys.exit(0 if result['passed'] else 1)
