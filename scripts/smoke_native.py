#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Read-only runtime checks. No PIN, no signing and no personal output in reports."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import sys
from runtime_test_tools import test_tools_runtime

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--test-tools-runtime', type=Path, help='Verified external development tools; not installed with the app')
parser.add_argument('--document', type=Path, help='Optional document; reports flags only, never signer names')
parser.add_argument('--report', type=Path)
parser.add_argument('--detect-only', action='store_true', help=argparse.SUPPRESS)
parser.add_argument('--detect', action='store_true', help='Read public card information without a PIN')
args = parser.parse_args()
runtime = args.runtime.resolve()
test_tools = test_tools_runtime(runtime, args.test_tools_runtime)
system = platform.system()
suffix = {'Darwin':'.dylib', 'Windows':'.dll', 'Linux':'.so'}[system]
prefix = '' if system == 'Windows' else 'lib'
# Retain the safe directory cookie for the full test lifetime.
dll_directory = os.add_dll_directory(str(runtime)) if system == 'Windows' else None
manifest = json.loads((runtime/'backend-manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((runtime/name).read_bytes()).hexdigest() == digest, 'Runtime checksum mismatch: '+name
bridge = ctypes.CDLL(str(runtime/(prefix+'cie_bridge'+suffix)))
bridge.cie_bridge_free.argtypes = [ctypes.c_void_p]
for name, count in [('load',2),('verify',1),('detect',0)]:
    function = getattr(bridge,'cie_bridge_'+name)
    function.argtypes = [ctypes.c_char_p]*count
    function.restype = ctypes.c_void_p

def call(name,*values):
    pointer = getattr(bridge,'cie_bridge_'+name)(*[str(x).encode('utf-8') for x in values])
    assert pointer, 'Empty native response'
    try: return json.loads(ctypes.string_at(pointer).decode('utf-8'))
    finally: bridge.cie_bridge_free(pointer)

def flags(result):
    return dict(ok=result.get('ok'), code=result.get('code'), signatureCount=result.get('signatureCount'),
        trustChainChecked=result.get('trustChainChecked'), trustChainValidated=result.get('trustChainValidated'),
        signers=[{k:s.get(k) for k in ['signatureValid','certificateWithinValidity','revocationStatus',
            'trustChainChecked','trustChainValidated','trustChainStatus','trustChainReason','trustSource',
            'chainLength','chainRevocationStatus','revocationSource','revocationReason','timestampStatus','timestampReason','timestampTime','historicalStatus','historicalReason','tsaHistoricalRevocationStatus','signerHistoricalRevocationStatus']} for s in result.get('signers',[])])

report = dict(system=system, machine=platform.machine(), backendLoaded=False)
response = call('load',runtime/(prefix+'cie-pkcs11'+suffix),runtime/(prefix+'cie_card_adapter'+suffix))
assert response.get('ok') and response.get('canSign'), response.get('code')
report['backendLoaded'] = True
if args.detect_only:
    result = call('detect')
    public = dict(ok=result.get('ok'),code=result.get('code'),nativeCode=result.get('nativeCode'),
        readers=len(result.get('readers',[])),cards=sum(bool(r.get('isCie')) for r in result.get('readers',[])))
    print('CIE_DETECTION_JSON='+json.dumps(public),flush=True)
    raise SystemExit(0)
exe = '.exe' if system == 'Windows' else ''
env = os.environ.copy()
if system == 'Windows': env['PATH'] = str(runtime)+os.pathsep+env.get('PATH','')
with tempfile.TemporaryDirectory(prefix='cie-port-test-') as temporary:
    folder = Path(temporary)
    # Recreate fixtures on each PC: their test certificate is valid for one hour.
    for name, parameters in [('cie_security_tests', ['--temporal-fixtures', 'temporal-fixtures']), ('cie_handle_tests', []), ('cie_sdk_tests', ['fixtures'])]:
        result = subprocess.run([str(test_tools/'tests'/(name+exe)),*parameters], cwd=folder, env=env, capture_output=True)
        report[name] = dict(passed=result.returncode == 0, returnCode=result.returncode)
        report[name]['stdout'] = result.stdout.decode('utf-8',errors='replace')
        if result.returncode:
            report[name]['diagnostic'] = result.stderr.decode('utf-8',errors='replace')
    fixtures = folder/'fixtures'
    # The native SDK tests already cover valid, tampered and repeated signatures.
    # Verify a generated file through the *same* ABI the UI uses.
    if report['cie_sdk_tests']['passed']:
        documents = sorted(fixtures.glob('*.pdf')) + sorted(fixtures.glob('*.p7m'))
        checks = [flags(call('verify',path)) for path in documents]
        assert any(any(s['signatureValid'] for s in item['signers']) for item in checks), 'No valid PDF through the bridge'
        for extension in ['pdf','p7m']:
            result = flags(call('verify',fixtures/('valid.'+extension)))
            assert result['ok'] and any(s['signatureValid'] for s in result['signers']), 'Valid '+extension+' rejected'
            invalid = flags(call('verify',fixtures/('tampered.'+extension)))
            assert not invalid['ok'] or not all(s['signatureValid'] for s in invalid['signers']), 'Tampered '+extension+' accepted'
            unicode_path = folder/('documento-àè-漢字.'+extension)
            shutil.copy2(fixtures/('valid.'+extension),unicode_path)
            assert flags(call('verify',unicode_path)) == result, 'UTF-8 path altered verification'
        report['utf8Paths'] = True
        report['fixtureVerifications'] = checks
    else:
        report['fixtureVerifications'] = dict(skipped=True, reason='SDK fixture generator failed')
        report['utf8Paths'] = dict(skipped=True, reason='SDK fixture generator failed')
    temporal = folder/'temporal-fixtures'
    if report['cie_security_tests']['passed']:
        stamped = flags(call('verify',temporal/'timestamped-untrusted.p7m'))
        assert stamped['ok'] and stamped['signers'][0]['signatureValid']
        assert stamped['signers'][0]['timestampStatus'] == 'indeterminate'
        assert stamped['signers'][0]['historicalStatus'] == 'indeterminate'
        stamped_pdf = flags(call('verify',temporal/'signature-timestamp-untrusted.pdf'))
        assert stamped_pdf['ok'] and stamped_pdf['signers'][0]['signatureValid']
        assert stamped_pdf['signers'][0]['timestampStatus'] == 'indeterminate'
        assert stamped_pdf['signers'][0]['historicalStatus'] == 'indeterminate'
        document = call('verify',temporal/'document-timestamp-untrusted.pdf')
        assert document['ok'] and document['signatureCount'] == 0
        assert document['documentTimestampCount'] == 1 and document['documentTimestampStatus'] == 'indeterminate'
        report['temporalUntrustedFixtures'] = dict(signatureTimestamp=stamped,pdfSignatureTimestamp=stamped_pdf,
            documentTimestampCount=document['documentTimestampCount'],documentTimestampStatus=document['documentTimestampStatus'],
            syntheticTestRootNeverInstalled=True)
    missing = call('verify',folder/'missing.pdf')
    assert missing.get('code') == 'input_missing'
    report['missingPathHandled'] = True
if args.detect:
    # A driver can block inside SCardConnect. A public-information probe runs in
    # its own process so it can time out without terminating a signing attempt.
    try:
        probe = subprocess.run([sys.executable,str(Path(__file__).resolve()),'--runtime',str(runtime),'--detect-only'],
            capture_output=True,timeout=30)
        marker = 'CIE_DETECTION_JSON='
        lines = probe.stdout.decode('utf-8',errors='replace').splitlines()
        matches = [line[len(marker):] for line in lines if line.startswith(marker)]
        report['cardDetection'] = json.loads(matches[-1]) if matches else dict(ok=False,code='probe_failed',returnCode=probe.returncode)
    except subprocess.TimeoutExpired:
        report['cardDetection'] = dict(ok=False,code='pcsc_timeout',readers=None,cards=None)
if args.document:
    report['documentVerification'] = flags(call('verify',args.document.resolve()))
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(0 if all(report[name]['passed'] for name in ['cie_security_tests','cie_handle_tests','cie_sdk_tests']) else 1)
