#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""NSS in memory + synthetic module only. No Firefox/profile/PCSC/network."""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

module = Path(sys.argv[1]).resolve()
# Refuse accidental testing of the real provider against a connected reader.
assert module.name == 'libcie_linux_pkcs11_fake.so'
with_cache = '--with-cache' in sys.argv[2:]
with_snap = '--snap-public' in sys.argv[2:]
if with_snap:
    os.environ['SNAP_NAME'] = os.environ['SNAP_INSTANCE_NAME'] = 'firefox'
with tempfile.TemporaryDirectory(prefix='cie-linux-nss-software-') as folder:
    root = Path(folder)
    os.environ['CIE_PAIRING_TEST_CACHE'] = str(root)
    fake = C.CDLL(str(module), mode=C.RTLD_LOCAL)
    fake.CieTestMetric.argtypes = [C.c_uint]
    fake.CieTestMetric.restype = C.c_uint
    fake.CieTestCertificate.argtypes = [C.c_void_p, C.c_uint]
    fake.CieTestCertificate.restype = C.c_uint
    der = C.create_string_buffer(fake.CieTestCertificate(None, 0))
    assert fake.CieTestCertificate(der, len(der)) == len(der)
    label = 'CIE ID ' + hashlib.sha256(der.raw).hexdigest()[:16]
    if with_snap:
        fake.CieTestSeedSnapPublic()
    elif with_cache:
        fake.CieTestSeedPublic()
    def saved_files():
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for folder in [root/'cache-v3', root/'snap']
                for p in folder.rglob('*') if p.is_file()}
    before = saved_files()
    nss = C.CDLL('libnss3.so')
    def api(name, result, *args):
        fn = getattr(nss, name); fn.restype = result; fn.argtypes = list(args); return fn
    no_db = api('NSS_NoDB_Init', C.c_int, C.c_void_p)
    version = api('NSS_GetVersion', C.c_char_p)
    nss_version = version().decode()
    shutdown = api('NSS_Shutdown', C.c_int)
    load = api('SECMOD_LoadUserModule', C.c_void_p, C.c_char_p, C.c_void_p, C.c_int)
    unload = api('SECMOD_UnloadUserModule', C.c_int, C.c_void_p)
    destroy_module = api('SECMOD_DestroyModule', None, C.c_void_p)
    find_slot = api('PK11_FindSlotByName', C.c_void_p, C.c_char_p)
    free_slot = api('PK11_FreeSlot', None, C.c_void_p)
    authenticate = api('PK11_Authenticate', C.c_int, C.c_void_p, C.c_int, C.c_void_p)
    check_password = api('PK11_CheckUserPassword', C.c_int, C.c_void_p, C.c_char_p)
    password_type = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_int, C.c_void_p)
    set_password = api('PK11_SetPasswordFunc', None, password_type)
    duplicate = api('PORT_Strdup', C.c_void_p, C.c_char_p)
    find_cert = api('PK11_FindCertFromNickname', C.c_void_p, C.c_char_p, C.c_void_p)
    free_cert = api('CERT_DestroyCertificate', None, C.c_void_p)
    find_key = api('PK11_FindKeyByAnyCert', C.c_void_p, C.c_void_p, C.c_void_p)
    free_key = api('SECKEY_DestroyPrivateKey', None, C.c_void_p)
    class Item(C.Structure):
        _fields_ = [('type', C.c_int), ('data', C.c_void_p), ('len', C.c_uint)]
    sign = api('PK11_SignWithMechanism', C.c_int, C.c_void_p, C.c_ulong, C.c_void_p, C.POINTER(Item), C.POINTER(Item))
    pin_prompts = []
    @password_type
    def password(slot, retry, context):
        pin_prompts.append(bool(retry))
        return None if retry else duplicate(b'12345678')  # synthetic only
    assert no_db(None) == 0, 'NSS in-memory initialization'
    handle = slot = cert = key = None
    try:
        specification = f'name="CIE Linux Software Test" library="{module}"'
        handle = load(specification.encode(), None, 0)
        assert handle, 'NSS module load'
        slot = find_slot(label.encode())
        assert slot, 'NSS token discovery'
        assert fake.CieTestMetric(2) == fake.CieTestMetric(3) == 0, 'discovery must not authenticate/sign'
        if with_snap:
            assert check_password(slot, b'5678') != 0, 'Snap must reject partial PIN'
            assert fake.CieTestMetric(2) == 0, 'partial PIN must not reach even the simulated card'
        set_password(password)
        assert authenticate(slot, 1, None) == 0, 'NSS full-PIN login'
        assert pin_prompts == [False] and fake.CieTestMetric(2) == 1, 'one synthetic PIN request/VERIFY'
        cert = find_cert((label + ':' + label).encode(), None)
        assert cert, 'NSS certificate selection'
        key = find_key(cert, None)
        assert key, 'NSS certificate/private-key association'
        digest = bytes.fromhex('3031300d060960864801650304020105000420') + hashlib.sha256(b'Synthetic Firefox TLS request').digest()
        data = C.create_string_buffer(digest)
        signature = C.create_string_buffer(256)
        input_item, output_item = Item(0, C.addressof(data), len(digest)), Item(0, C.addressof(signature), 256)
        assert sign(key, 1, None, C.byref(output_item), C.byref(input_item)) == 0, 'NSS RSA PKCS1 signing'
        assert output_item.len == 256 and fake.CieTestMetric(3) == 1
        assert fake.CieTestMetric(2) == 1 and pin_prompts == [False], 'signing must not resend PIN'
        public = subprocess.run(['openssl','x509','-inform','DER','-pubkey','-noout'], input=der.raw, capture_output=True, check=True).stdout
        (root/'public.pem').write_bytes(public); (root/'signature').write_bytes(signature.raw); (root/'digest').write_bytes(digest)
        subprocess.run(['openssl','pkeyutl','-verify','-pubin','-inkey',str(root/'public.pem'),'-sigfile',str(root/'signature'),'-in',str(root/'digest')],capture_output=True,check=True)
    finally:
        if key: free_key(key)
        if cert: free_cert(cert)
        if slot: free_slot(slot)
        if handle:
            assert unload(handle) == 0
            destroy_module(handle)
        assert shutdown() == 0
    assert fake.CieTestMetric(7) == fake.CieTestMetric(8), 'all PCSC transactions released'
    after = saved_files()
    assert before == after, 'provider must not alter cache or save PIN data'
    if with_cache or with_snap:
        assert fake.CieTestMetric(12) >= 2, 'cached certificate checked on discovery and authentication'
    else:
        assert not (root/'cache-v3').exists(), 'no persistent cache created'
print(json.dumps(dict(passed=True, nssInMemory=True, certificateSelected=True,
                     nssVersion=nss_version,
                     fullPinPrompts=1, signaturesVerified=1, publicCacheExercised=with_cache,
                     snapPublicCertificateExercised=with_snap,
                     partialPinRejectedWithoutVerify=with_snap,
                     pinPairingCacheIgnored=True, realCardOperations=0,
                     firefoxStarted=False, browserConfigurationChanged=False)))
