#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check browser-style KSP key opening without authentication or signing.

Reads only our marked MY certificates and uses ONLY_NCRYPT | SILENT |
NO_HEALING. May read public card metadata; never signs, prompts for a PIN,
resets the card, changes certificates, or prints personal identifiers.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path


def probe():
    crypt = c.WinDLL('crypt32', use_last_error=True)
    nc = c.WinDLL('ncrypt')
    crypt.CertOpenSystemStoreW.argtypes = [c.c_size_t, w.LPCWSTR]
    crypt.CertOpenSystemStoreW.restype = c.c_void_p
    crypt.CertEnumCertificatesInStore.argtypes = [c.c_void_p, c.c_void_p]
    crypt.CertEnumCertificatesInStore.restype = c.c_void_p
    crypt.CertGetCertificateContextProperty.argtypes = [c.c_void_p, w.DWORD, c.c_void_p, c.POINTER(w.DWORD)]
    crypt.CertGetCertificateContextProperty.restype = w.BOOL
    crypt.CryptAcquireCertificatePrivateKey.argtypes = [c.c_void_p, w.DWORD, c.c_void_p, c.POINTER(c.c_size_t), c.POINTER(w.DWORD), c.POINTER(w.BOOL)]
    crypt.CryptAcquireCertificatePrivateKey.restype = w.BOOL
    crypt.CertCloseStore.argtypes = [c.c_void_p, w.DWORD]
    nc.NCryptFreeObject.argtypes = [c.c_size_t]

    class ProviderInfo(c.Structure):
        _fields_ = [('container', w.LPWSTR), ('provider', w.LPWSTR),
                    ('type', w.DWORD), ('flags', w.DWORD),
                    ('paramsCount', w.DWORD), ('params', c.c_void_p), ('spec', w.DWORD)]

    def prop(ctx, key):
        size = w.DWORD()
        if not crypt.CertGetCertificateContextProperty(ctx, key, None, c.byref(size)) or not 0 < size.value <= 16384:
            return None
        buffer = c.create_string_buffer(size.value)
        return buffer if crypt.CertGetCertificateContextProperty(ctx, key, buffer, c.byref(size)) else None

    store = crypt.CertOpenSystemStoreW(0, 'MY')
    if not store:
        raise RuntimeError('Cannot open the current-user MY store')
    results = []
    try:
        ctx = None
        while True:
            ctx = crypt.CertEnumCertificatesInStore(store, ctx)
            if not ctx:
                break
            marker = prop(ctx, 0x8000 + 71)
            if marker is None or not marker.raw.startswith(b'it.giancarloezza.CIEID.FlutterPrototype.pairing.v1.web/'):
                continue
            info = prop(ctx, 2)
            item = {'ownCertificate': True, 'hasProviderInfo': info is not None}
            expected = False
            if info is not None and len(info) >= c.sizeof(ProviderInfo):
                value = c.cast(info, c.POINTER(ProviderInfo)).contents
                expected = value.provider == 'Microsoft Smart Card Key Storage Provider' and value.spec == 0xffffffff
                item.update(expectedKsp=expected, keySpec=hex(value.spec))
            if expected:
                key = c.c_size_t()
                spec = w.DWORD()
                must_free = w.BOOL()
                c.set_last_error(0)
                ok = crypt.CryptAcquireCertificatePrivateKey(ctx, 0x40000 | 0x40 | 0x8, None, c.byref(key), c.byref(spec), c.byref(must_free))
                error = c.get_last_error()
                item.update(silentAcquireSucceeded=bool(ok), error=f'0x{error & 0xffffffff:08x}' if not ok else '0x00000000', returnedKeySpec=hex(spec.value))
                if ok and must_free.value:
                    nc.NCryptFreeObject(key)
            results.append(item)
    finally:
        crypt.CertCloseStore(store, 0)
    return {'operation': 'CryptAcquireCertificatePrivateKey ONLY_NCRYPT|SILENT|NO_HEALING',
            'pinOperations': 0, 'signOperations': 0, 'systemWrites': 0,
            'certificates': results,
            'passed': bool(results) and all(item.get('silentAcquireSucceeded') for item in results)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--expect-open', action='store_true')
    args = parser.parse_args()
    if os.name != 'nt':
        raise SystemExit('Windows only')
    result = probe()
    encoded = json.dumps(result, indent=2) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded, encoding='utf-8')
    print(encoded, end='')
    raise SystemExit(0 if not args.expect_open or result['passed'] else 1)


if __name__ == '__main__':
    main()
