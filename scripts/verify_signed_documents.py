#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify existing local signatures; never authenticates, signs or prints identity.

The native bridge reports integrity, certificate dates and revocation separately.
OpenSSL -noverify checks cryptographic integrity, without validating a trust chain.
"""
import argparse
import ctypes
import json
import os
import platform
import shutil
from pathlib import Path
import subprocess
import tempfile

from pypdf import PdfReader

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', required=True, type=Path)
parser.add_argument('--input', required=True, type=Path)
parser.add_argument('--pdf', type=Path)
parser.add_argument('--p7m', type=Path)
parser.add_argument('--report', required=True, type=Path)
parser.add_argument('--openssl', default=shutil.which('openssl'), help='OpenSSL CLI for an independent CMS check')
parser.add_argument('--require-history', action='store_true', help='Require every signature to have verified historical validity, not only a declared date or token')
parser.add_argument('--require-trust', action='store_true', help='Also require a trusted current chain and good revocation for the whole chain')
args = parser.parse_args()
if args.pdf is None and args.p7m is None:
    parser.error('Specify --pdf and/or --p7m')
if not args.openssl:
    parser.error('OpenSSL CLI not found; specify --openssl')
runtime = args.runtime.resolve()
system = platform.system()
libprefix = '' if system == 'Windows' else 'lib'
suffix = {'Darwin': '.dylib', 'Windows': '.dll', 'Linux': '.so'}[system]
cookie = os.add_dll_directory(str(runtime)) if system == 'Windows' else None
bridge = ctypes.CDLL(str(runtime / (libprefix + 'cie_bridge' + suffix)))
bridge.cie_bridge_free.argtypes = [ctypes.c_void_p]
for name, count in [('load', 2), ('verify', 1)]:
    f = getattr(bridge, 'cie_bridge_' + name)
    f.argtypes = [ctypes.c_char_p] * count
    f.restype = ctypes.c_void_p

def call(name, *values):
    pointer = getattr(bridge, 'cie_bridge_' + name)(*[str(v).encode('utf-8') for v in values])
    if not pointer:
        raise RuntimeError('empty_native_response')
    try:
        return json.loads(ctypes.string_at(pointer).decode('utf-8'))
    finally:
        bridge.cie_bridge_free(pointer)

def flags(result):
    return {k: result.get(k) for k in ['ok', 'code', 'nativeCode', 'signatureCount', 'trustChainChecked', 'trustChainValidated']} | {
        'signers': [{k: s.get(k) for k in ['signatureValid', 'certificateWithinValidity', 'revocationStatus',
                    'trustChainChecked', 'trustChainValidated', 'trustChainStatus', 'trustChainError',
                    'trustChainReason', 'trustSource', 'chainLength', 'chainRevocationStatus', 'revocationSource', 'revocationReason', 'timestampStatus', 'timestampReason', 'timestampTime', 'historicalStatus', 'historicalReason', 'tsaHistoricalRevocationStatus', 'signerHistoricalRevocationStatus']}
                    for s in result.get('signers', [])]}

def cms_verify(signature, output, content=None):
    command = [args.openssl, 'cms', '-verify', '-noverify',
               '-binary', '-inform', 'DER', '-in', str(signature), '-out', str(output)]
    if content is not None:
        command += ['-content', str(content)]
    # Errors can contain certificate information: capture, report only return code.
    return subprocess.run(command, capture_output=True, timeout=60).returncode

def der_without_padding(value):
    data = bytes(value)
    if len(data) < 2 or data[0] != 0x30:
        raise ValueError('invalid_cms_der')
    size = data[1]
    if size & 0x80:
        count = size & 0x7f
        if not 1 <= count <= 4 or len(data) < 2 + count:
            raise ValueError('invalid_cms_length')
        length = 2 + count + int.from_bytes(data[2:2 + count], 'big')
    else:
        length = 2 + size
    if length > len(data) or any(data[length:]):
        raise ValueError('invalid_cms_padding')
    return data[:length]

loaded = call('load', runtime / (libprefix + 'cie-pkcs11' + suffix),
              runtime / (libprefix + 'cie_card_adapter' + suffix))
if not loaded.get('ok'):
    raise SystemExit('backend_load_failed')
report = {'backendLoaded': True, 'trustChainValidationPerformed': False,
          'independentCmsTrustValidationPerformed': False,
          'hardwareSigningPerformedByThisScript': False}
scratch_root = args.report.resolve().parent
scratch_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='local-signature-check-', dir=scratch_root) as temporary:
    scratch = Path(temporary).resolve()
    assert scratch.is_relative_to(scratch_root)
    if args.pdf is not None:
        if not args.pdf.is_file():
            report['pdf'] = {'status': 'awaiting_user_signature'}
        else:
            data = args.pdf.read_bytes()
            native = flags(call('verify', args.pdf.resolve()))
            reader = PdfReader(args.pdf)
            signatures = []
            for field in (reader.get_fields() or {}).values():
                if field.get('/FT') != '/Sig' or field.get('/V') is None:
                    continue
                value = field['/V'].get_object()
                if value.get('/SubFilter') == '/ETSI.RFC3161':
                    continue # Document timestamps are reported separately by the native validator.
                ranges = [int(x) for x in value.get('/ByteRange', [])]
                valid_range = (len(ranges) == 4 and ranges[0] == 0 and ranges[1] > 0
                               and ranges[2] > ranges[1] and ranges[3] >= 0
                               and ranges[2] + ranges[3] <= len(data))
                item = {'byteRangeWithinFile': valid_range, 'coversWholeFile': False,
                        'cmsValid': False, 'opensslReturnCode': None}
                if valid_range:
                    item['coversWholeFile'] = ranges[2] + ranges[3] == len(data)
                    gap = data[ranges[1]:ranges[2]]
                    item['contentsGapIsHexString'] = gap.startswith(b'<') and gap.endswith(b'>')
                    cms_path = scratch / 'signature.der'
                    content_path = scratch / 'signed-bytes.bin'
                    cms_path.write_bytes(der_without_padding(value['/Contents']))
                    content_path.write_bytes(data[:ranges[1]] + data[ranges[2]:ranges[2] + ranges[3]])
                    item['opensslReturnCode'] = cms_verify(cms_path, scratch / 'verified.bin', content_path)
                    item['cmsValid'] = item['opensslReturnCode'] == 0
                signatures.append(item)
            report['pdf'] = {'status': 'verified', 'native': native, 'independentSignatures': signatures,
                             'integrityPassed': bool(signatures) and native.get('ok') is True
                             and native.get('signatureCount') == len(signatures)
                             and all(s.get('signatureValid') for s in native['signers'])
                             and all(s['cmsValid'] and s['byteRangeWithinFile'] and s.get('contentsGapIsHexString')
                                     for s in signatures)
                             and any(s['coversWholeFile'] for s in signatures)}
    if args.p7m is not None:
        if not args.p7m.is_file():
            report['p7m'] = {'status': 'awaiting_user_signature'}
        else:
            native = flags(call('verify', args.p7m.resolve()))
            extracted = scratch / 'extracted-content.bin'
            result = cms_verify(args.p7m.resolve(), extracted)
            matches = result == 0 and extracted.read_bytes() == args.input.read_bytes()
            report['p7m'] = {'status': 'verified', 'native': native, 'opensslReturnCode': result,
                             'cmsValid': result == 0, 'extractedContentMatchesInput': matches,
                             'integrityPassed': matches and native.get('ok') is True
                             and native.get('signatureCount', 0) > 0
                             and all(s.get('signatureValid') for s in native['signers'])}
report['allRequestedFilesPresent'] = all(report.get(k, {}).get('status') != 'awaiting_user_signature'
                                       for k in ('pdf', 'p7m'))
report['allPresentSignaturesValid'] = all(report.get(k, {}).get('integrityPassed', True)
                                        for k in ('pdf', 'p7m'))
present = [report[k] for k in ('pdf', 'p7m') if report.get(k, {}).get('status') == 'verified']
report['trustChainValidationPerformed'] = bool(present) and all(
    item['native'].get('trustChainChecked') is True for item in present)
report['allPresentCertificatesTrustedAndNotRevoked'] = bool(present) and all(
    item['native'].get('trustChainValidated') is True and bool(item['native']['signers']) and all(
        s.get('trustChainValidated') is True and s.get('certificateWithinValidity') is True and
        s.get('revocationStatus') == 0 and s.get('chainRevocationStatus') == 0
        for s in item['native']['signers']) for item in present)
report['allPresentSignaturesHistoricallyValid'] = bool(present) and all(
    bool(item['native']['signers']) and all(s.get('historicalStatus') == 'valid_at_timestamp' for s in item['native']['signers']) for item in present)
report['historyRequiredForSuccess'] = args.require_history
report['trustRequiredForSuccess'] = args.require_trust
args.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
raise SystemExit(0 if report['allRequestedFilesPresent'] and report['allPresentSignaturesValid'] and
    (not args.require_trust or report['allPresentCertificatesTrustedAndNotRevoked']) and
    (not args.require_history or report['allPresentSignaturesHistoricallyValid']) else 1)
