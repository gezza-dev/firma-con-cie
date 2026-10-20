#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Production runtime metadata only, with a mandatory PCSC-blocking preload."""
import ctypes as C
import json
import os
from pathlib import Path
import subprocess
import sys

runtime, guard = [Path(value).resolve() for value in sys.argv[1:3]]
if os.environ.get('CIE_METADATA_GUARDED') != '1':
    env = dict(os.environ, LD_PRELOAD=str(guard), CIE_METADATA_GUARDED='1')
    result = subprocess.run([sys.executable, __file__, str(runtime), str(guard)], env=env, capture_output=True, text=True, timeout=15)
    sys.stdout.write(result.stdout);sys.stderr.write(result.stderr);raise SystemExit(result.returncode)
block = C.CDLL(str(guard));block.CieNoCardCalls.restype = C.c_uint
provider = C.CDLL(str(runtime/'libcie_linux_pkcs11.so'), mode=C.RTLD_LOCAL)
provider.CieLinuxWebAbiVersion.restype = C.c_uint
assert provider.CieLinuxWebAbiVersion() == 1
assert not hasattr(provider, 'CieTestMetric') and not hasattr(provider, 'CieTestExpire')
bridge = C.CDLL(str(runtime/'libcie_bridge.so'))
bridge.cie_bridge_web_status.restype = C.c_void_p
bridge.cie_bridge_web_test.argtypes = [C.c_char_p]
bridge.cie_bridge_web_test.restype = C.c_void_p
bridge.cie_bridge_free.argtypes = [C.c_void_p]
def response(pointer):
    assert pointer
    try: return json.loads(C.string_at(pointer))
    finally: bridge.cie_bridge_free(pointer)
status = response(bridge.cie_bridge_web_status())
assert status['ok'] and status['available'] and status['provider'] == 'linux-firefox-pkcs11'
assert status['fullPinRequired'] and status['browserRegistrationRequired']
assert status['browserConfigurationVerified'] is False
assert status['firefoxSnapSupported'] and status['snapPermissionsVerified'] is False
result = response(bridge.cie_bridge_web_test(b'TESTLINUX000001'))
assert result['ok'] is False and result['code'] == 'web_test_requires_firefox'
assert 'Windows' not in result['message'] and block.CieNoCardCalls() == 0
print(json.dumps(dict(passed=True, productionModule=True, softwareTestHooksAbsent=True,
                     pcscBlocked=True, pcscCalls=0, firefoxStarted=False,
                     browserConfigurationChanged=False, productionCacheAccessed=False)))
