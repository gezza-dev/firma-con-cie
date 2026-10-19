#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Tests synthetic backend boundaries, never accesses a card or a real PIN."""
import ctypes
import os
import json
import tempfile
import sys
import stat
import time
import tempfile,os
_pairing_state=tempfile.TemporaryDirectory(prefix='cie-pairing-state-')
os.environ['CIE_PAIRING_TEST_STATE']=_pairing_state.name
from pathlib import Path
bridge, backend, adapter = map(str, sys.argv[1:])
# Python 3.8+ does not use PATH for ctypes dependency lookup. Only the private
# runtime parent is admitted, and the directory cookie stays alive for this test.
_test_bridge_path = Path(sys.argv[1]).resolve()
_private_runtime = _test_bridge_path.parent.parent if _test_bridge_path.parent.name == 'tests' else _test_bridge_path.parent
_dll_scope = os.add_dll_directory(str(_private_runtime)) if os.name == 'nt' else None
lib = ctypes.CDLL(bridge)
lib.cie_bridge_free.argtypes = [ctypes.c_void_p]
for name, parameters in [('load', 2), ('verify', 1), ('sign', 6), ('change_pin',4),('unblock_pin',4)]:
    function = getattr(lib, 'cie_bridge_'+name)
    function.argtypes = [ctypes.c_char_p]*parameters
    function.restype = ctypes.c_void_p
def call(name, *arguments):
    pointer = getattr(lib, 'cie_bridge_'+name)(*arguments)
    assert pointer
    try:
        text = ctypes.string_at(pointer).decode('utf-8')
        assert '12345678' not in text, 'PIN leaked in result'
        return json.loads(text)
    finally: lib.cie_bridge_free(pointer)
with tempfile.TemporaryDirectory(dir=os.environ.get('CIE_VISIBILITY_TEST_PARENT')) as directory:
    source = Path(directory)/'document.pdf'
    output = Path(directory)/'signed.pdf'
    source.write_text('Synthetic fixture')
    assert call('load', b'/missing/backend', b'')['code'] == 'backend_missing'
    assert call('load', backend.encode(), adapter.encode())['canSign']
    assert call('verify', str(source).encode())['signers'][0]['commonName'] == 'Synthetic ABI test signer'
    assert call('verify', b'/missing/document')['code'] == 'input_missing'
    fake = ctypes.CDLL(adapter)
    fake.fake_attempts.restype = ctypes.c_int
    def sign(pin, destination=output, card=b'TEST'):
        buffer = ctypes.create_string_buffer(pin)
        response = call('sign', b'Test reader', card, str(source).encode(), str(destination).encode(), b'p7m', buffer)
        assert buffer.raw[:len(pin)] == b'\0'*len(pin), 'Native PIN buffer not wiped'
        return response
    assert sign(b'bad')['code'] == 'invalid_pin'
    assert fake.fake_attempts() == 0
    assert sign(b'12345678', card=b'CHANGED')['code'] == 'card_changed'
    assert fake.fake_attempts() == 0
    assert sign(b'00000000')['code'] == 'pin_incorrect'
    assert fake.fake_attempts() == 1, 'Unexpected retry'
    assert not output.exists()
    valid = sign(b'12345678')
    assert valid['ok'] and valid['verification']['signers'][0]['signatureValid']
    assert fake.fake_attempts() == 2
    content = output.read_bytes()
    if sys.platform == 'darwin':
        for delay in [0, .3]:
            time.sleep(delay)
            assert not output.stat().st_flags & stat.UF_HIDDEN, 'Final signed output is hidden'
            assert output.stat().st_flags & stat.UF_NODUMP, 'Unrelated flags removed'
            finder=(ctypes.c_ubyte*32)();getxattr=ctypes.CDLL(None).getxattr
            getxattr.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32,ctypes.c_int]
            getxattr.restype=ctypes.c_ssize_t
            assert getxattr(str(output).encode(),b'com.apple.FinderInfo',finder,32,0,0)==32
            assert not finder[8] & 0x40 and finder[9] == 1, 'Finder invisibility/other metadata not preserved'

    assert sign(b'12345678')['code'] == 'output_exists'
    assert output.read_bytes() == content and fake.fake_attempts() == 2
    assert not list(Path(directory).glob('CIE-ID-elaborazione-*'))
    assert call('verify', str(source).encode())['signatureCount'] == 1
    fake.fake_pin_attempts.restype=ctypes.c_int
    for operation in ['change_pin','unblock_pin']:
        def update(auth=b'10293847',replacement=b'86420975',card=b'TEST'):
            a,b=ctypes.create_string_buffer(auth),ctypes.create_string_buffer(replacement)
            value=call(operation,b'Test reader',card,a,b)
            assert a.raw[:len(auth)]==b'\0'*len(auth) and b.raw[:len(replacement)]==b'\0'*len(replacement)
            assert not any(secret.decode() in json.dumps(value) for secret in [auth,replacement])
            return value
        before=fake.fake_pin_attempts()
        assert update(replacement=b'123')['code']=='invalid_new_pin'
        assert update(card=b'OTHER')['code']=='card_changed'
        assert fake.fake_pin_attempts()==before
        bad=update(auth=b'00000000');assert bad['code']==('puk_incorrect' if operation=='unblock_pin' else 'pin_incorrect') and bad['attemptsRemaining']==2
        assert fake.fake_pin_attempts()==before+1
        locked=update(auth=b'99999999');assert locked['code']==('puk_locked' if operation=='unblock_pin' else 'pin_locked') and locked['attemptsRemaining']==0
        assert update()['ok']
        assert update(replacement=b'97531086')['code']=='pin_operation_indeterminate'
        assert fake.fake_pin_attempts()==before+4
        for replacement in [b'00000000',b'11111111',b'12345678',b'87654321',b'10293847']:
            count=fake.fake_pin_attempts()
            assert update(replacement=replacement)['ok']
            assert fake.fake_pin_attempts()==count+1
print('Synthetic ABI tests passed: result ownership, missing paths, identity check, PIN wiping, no retries, atomic no-overwrite output, recovery')

# Additive document ABI: malformed placement cannot reach the fake signer and
# every PIN buffer is wiped, including validation failures and wrong identity.
lib.cie_bridge_sign_pdf.argtypes=[ctypes.c_char_p]*6+[ctypes.c_int32]+[ctypes.c_double]*4
lib.cie_bridge_sign_pdf.restype=ctypes.c_void_p
lib.cie_bridge_extract.argtypes=[ctypes.c_char_p]*2;lib.cie_bridge_extract.restype=ctypes.c_void_p
lib.cie_bridge_pdf_info.argtypes=[ctypes.c_char_p,ctypes.c_int32];lib.cie_bridge_pdf_info.restype=ctypes.c_void_p
with tempfile.TemporaryDirectory(dir=os.environ.get('CIE_VISIBILITY_TEST_PARENT')) as directory:
    folder=Path(directory);source=folder/'document.pdf';source.write_bytes(b'Synthetic PDF');dest=folder/'graphic.pdf'
    before=fake.fake_attempts()
    def graphic(page=0,left=.1,width=.3,image=b'image.png',card=b'TEST'):
        pin=ctypes.create_string_buffer(b'12345678')
        result=call('sign_pdf',b'Test reader',card,str(source).encode(),str(dest).encode(),pin,image,page,left,.2,width,.1)
        assert pin.raw[:8]==b'\0'*8
        return result
    for arguments in [{'left':.9},{'width':float('nan')},{'page':-1},{'page':2},{'image':b'invalid.png'}]:
        assert graphic(**arguments)['code']=='invalid_appearance'
    assert fake.fake_attempts()==before
    assert graphic(card=b'OTHER')['code']=='card_changed' and fake.fake_attempts()==before
    assert graphic(page=1)['ok'] and fake.fake_attempts()==before+1
    fake.fake_appearance_page.restype=ctypes.c_int;assert fake.fake_appearance_page()==1
    assert graphic()['code']=='output_exists' and fake.fake_attempts()==before+1
    assert call('pdf_info',str(source).encode(),0)['pageCount']==2
    assert call('pdf_info',str(source).encode(),2)['code']=='pdf_invalid'
    p7m=folder/'source.p7m';p7m.write_bytes(b'Synthetic CMS');extracted=folder/'extracted.txt'
    result=call('extract',str(p7m).encode(),str(extracted).encode());assert result['ok'] and not result['integrityChecked']
    assert call('extract',str(p7m).encode(),str(extracted).encode())['code']=='output_exists'
    assert extracted.read_bytes()==b'Synthetic extracted content'
    bad=folder/'malformed.p7m';bad.write_bytes(b'bad');missing=folder/'missing.txt'
    assert call('extract',str(bad).encode(),str(missing).encode())['code']=='extraction_failed' and not missing.exists()
    assert call('extract',str(source).encode(),str(missing).encode())['code']=='invalid_format'
    assert not list(folder.glob('CIE-ID-elaborazione-*'))
print('Document ABI passed: graphic placement forwarding/preflight/PIN wiping/no retry, metadata, extraction/no overwrite/recovery')

with tempfile.TemporaryDirectory(dir=os.environ.get('CIE_VISIBILITY_TEST_PARENT')) as directory:
    root=Path(directory)
    for name,expected in [('malformed.p7m','cosign_input_invalid'),('detached.p7m','cosign_input_invalid'),('lost-signature.p7m','cosign_preservation_failed'),('original.p7m',None)]:
        source=root/name;source.write_bytes(b'Synthetic input');destination=root/(name+'.out.p7m')
        pin=ctypes.create_string_buffer(b'12345678')
        before=fake.fake_attempts()
        result=call('sign',b'reader',b'TEST',str(source).encode(),str(destination).encode(),b'cosign',pin)
        assert fake.fake_attempts()==before+(0 if expected=='cosign_input_invalid' else 1), 'Cofirma signer retried or preflight authenticated'
        assert not pin.value,'Cofirma PIN not wiped'
        if expected: assert result['code']==expected and not destination.exists(),result
        else:
            assert result['ok'] and destination.exists(),result
            existing=destination.read_bytes();again=ctypes.create_string_buffer(b'12345678')
            assert call('sign',b'reader',b'TEST',str(source).encode(),str(destination).encode(),b'cosign',again)['code']=='output_exists'
            assert not again.value and destination.read_bytes()==existing and fake.fake_attempts()==before+1
        assert not list(root.glob('CIE-ID-elaborazione-*'))
print('Cosign ABI passed: preflight, preservation and no-retry publication boundaries')

# Per-call network options: never inherit manual credentials in the old ABI,
# and reject invalid configuration before using a signer or invoking verification.
class Network(ctypes.Structure):
    _fields_=[('size',ctypes.c_uint32),('mode',ctypes.c_int32),('host',ctypes.c_char_p),('port',ctypes.c_int32),('username',ctypes.c_char_p),('password',ctypes.c_char_p)]
lib.cie_bridge_verify_network.argtypes=[ctypes.c_char_p,ctypes.POINTER(Network)];lib.cie_bridge_verify_network.restype=ctypes.c_void_p
lib.cie_bridge_network_probe.argtypes=[ctypes.POINTER(Network)];lib.cie_bridge_network_probe.restype=ctypes.c_void_p
lib.cie_bridge_sign_network.argtypes=[ctypes.c_char_p]*6+[ctypes.POINTER(Network)];lib.cie_bridge_sign_network.restype=ctypes.c_void_p
backendFake=ctypes.CDLL(backend);backendFake.fake_network_calls.restype=ctypes.c_int;backendFake.fake_network_bits.restype=ctypes.c_int
with tempfile.TemporaryDirectory(dir=os.environ.get('CIE_VISIBILITY_TEST_PARENT')) as directory:
    source=Path(directory)/'network.pdf';source.write_bytes(b'Synthetic network ABI')
    password=ctypes.create_string_buffer(b'proxy-secret')
    n=Network(ctypes.sizeof(Network),2,b'proxy.test',8443,b'proxy-user',ctypes.cast(password,ctypes.c_char_p))
    assert call('verify_network',str(source).encode(),ctypes.byref(n))['ok']
    assert password.raw[:12]==b'\0'*12 and backendFake.fake_network_bits()==7
    assert call('verify',str(source).encode())['ok'] and backendFake.fake_network_bits()==0
    assert call('network_probe',ctypes.byref(n))['ok']
    before=backendFake.fake_network_calls();authentications=fake.fake_attempts()
    for mode,host,port in [(1,b'http://proxy.test',8080),(2,b'[:::]',443),(1,b'proxy.test',0),(9,b'proxy.test',8080),(0,b'proxy.test',8080)]:
        password=ctypes.create_string_buffer(b'proxy-secret');n=Network(ctypes.sizeof(Network),mode,host,port,b'proxy-user',ctypes.cast(password,ctypes.c_char_p))
        assert call('verify_network',str(source).encode(),ctypes.byref(n))['code']=='network_config_invalid'
        assert password.raw[:12]==b'\0'*12
        pin=ctypes.create_string_buffer(b'12345678')
        assert call('sign_network',b'Test reader',b'TEST',str(source).encode(),str(Path(directory)/'never.p7m').encode(),b'p7m',pin,ctypes.byref(n))['code']=='network_config_invalid'
        assert pin.raw[:8]==b'\0'*8
    assert backendFake.fake_network_calls()==before and fake.fake_attempts()==authentications
    assert not (Path(directory)/'never.p7m').exists()
print('Network ABI passed: scoped proxy, credential wiping, invalid configuration rejected before authentication, direct reset')

# Explicit replacement is additive: the original ABI still refuses overwrite.
# A failed PIN or post-signature integrity check preserves the previous bytes.
lib.cie_bridge_sign_network_replace.argtypes=[ctypes.c_char_p]*6+[ctypes.c_void_p]
lib.cie_bridge_sign_network_replace.restype=ctypes.c_void_p
lib.cie_bridge_sign_pdf_network_replace.argtypes=[ctypes.c_char_p]*6+[ctypes.c_int32]+[ctypes.c_double]*4+[ctypes.c_void_p]
lib.cie_bridge_sign_pdf_network_replace.restype=ctypes.c_void_p
backendFake.fake_reject_signature.argtypes=[ctypes.c_int]
with tempfile.TemporaryDirectory(dir=os.environ.get('CIE_VISIBILITY_TEST_PARENT')) as directory:
    source=Path(directory)/'document.pdf';source.write_bytes(b'Synthetic replacement input')
    output=Path(directory)/'firmato.p7m';previous=b'Previously signed document: preserve on failure'
    output.write_bytes(previous)
    def replace(secret=b'12345678', graphic=False):
        pin=ctypes.create_string_buffer(secret);before=fake.fake_attempts()
        args=[b'Test reader',b'TEST',str(source).encode(),str(output).encode()]
        response=call('sign_pdf_network_replace',*args,pin,b'image.png',0,.1,.1,.3,.1,None) if graphic else call('sign_network_replace',*args,b'p7m',pin,None)
        assert not pin.value and fake.fake_attempts()==before+1
        return response
    assert replace(b'00000000')['code']=='pin_incorrect' and output.read_bytes()==previous
    backendFake.fake_reject_signature(1)
    assert replace()['code']=='post_sign_verification_failed' and output.read_bytes()==previous
    backendFake.fake_reject_signature(0)
    assert replace()['ok'] and output.read_bytes()!=previous
    output.write_bytes(previous)
    assert replace(graphic=True)['ok'] and output.read_bytes()!=previous
    if sys.platform=='darwin':
        assert not output.stat().st_flags & stat.UF_HIDDEN
    assert not list(Path(directory).glob('CIE-ID-elaborazione-*'))
print('Explicit replacement passed: one attempt, old bytes retained on PIN/verification failure, PDF/P7M publication and visible output')
