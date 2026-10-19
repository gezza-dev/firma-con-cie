#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Synthetic authentication and in-memory store only; never PC/SC or OS credentials."""
import ctypes as c,json,sys,tempfile,os
import tempfile,os
_pairing_state=tempfile.TemporaryDirectory(prefix='cie-pairing-state-')
os.environ['CIE_PAIRING_TEST_STATE']=_pairing_state.name
from pathlib import Path
# Python 3.8+ does not use PATH for ctypes dependency lookup. Only the private
# runtime parent is admitted, and the directory cookie stays alive for this test.
_test_bridge_path = Path(sys.argv[1]).resolve()
_private_runtime = _test_bridge_path.parent.parent if _test_bridge_path.parent.name == 'tests' else _test_bridge_path.parent
_dll_scope = os.add_dll_directory(str(_private_runtime)) if os.name == 'nt' else None
lib=c.CDLL(sys.argv[1]); fake=c.CDLL(sys.argv[3]);lib.cie_bridge_free.argtypes=[c.c_void_p]
for name,n in [('load',2),('pair',3),('pairings',0),('unpair',1)]:
 f=getattr(lib,'cie_bridge_'+name);f.argtypes=[c.c_char_p]*n;f.restype=c.c_void_p
f=lib.cie_bridge_sign_paired_network;f.argtypes=[c.c_char_p]*6+[c.c_void_p];f.restype=c.c_void_p
lib.fake_store_fail.argtypes=[c.c_int]
checks=0
def call(name,*args):
 global checks
 p=getattr(lib,'cie_bridge_'+name)(*args)
 try:
  raw=c.string_at(p).decode();assert '12345678' not in raw and '5678' not in raw and '1234' not in raw
  checks+=1;return json.loads(raw)
 finally:lib.cie_bridge_free(p)
def pair(pin=b'12345678',card=b'TEST'):
 b=c.create_string_buffer(pin);r=call('pair',b'Test reader',card,b);assert b.raw[:len(pin)]==bytes(len(pin));return r
assert call('load',sys.argv[2].encode(),sys.argv[3].encode())['canPair']
assert call('pairings')['cards']==[]
assert not pair(b'1234')['ok'];assert fake.fake_pair_attempts()==0
assert pair(card=b'CHANGED')['code']=='card_changed';assert fake.fake_pair_attempts()==0
assert pair(b'00000000')['code']=='pin_incorrect';assert fake.fake_pair_attempts()==1
assert call('pairings')['cards']==[]
assert pair(b'99999999')['code']=='pin_locked';assert fake.fake_pair_attempts()==2
lib.fake_store_fail(1);assert pair()['code']=='pairing_store_unavailable';assert fake.fake_pair_attempts()==2
lib.fake_store_fail(0);assert pair()['ok'];assert fake.fake_pair_attempts()==3
assert call('pairings')['cards']==['TEST']
with tempfile.TemporaryDirectory() as d:
 source=Path(d)/'input';source.write_text('fixture');out=Path(d)/'signed'
 def sign(pin=b'5678',card=b'TEST'):
  b=c.create_string_buffer(pin);r=call('sign_paired_network',b'Reader',card,str(source).encode(),str(out).encode(),b'p7m',b,None);assert b.raw[:len(pin)]==bytes(len(pin));return r
 assert sign(b'567')['code']=='invalid_pin';assert fake.fake_attempts()==0
 assert sign(card=b'OTHER')['code']=='pairing_required';assert fake.fake_attempts()==0
 lib.fake_store_fail(1);assert not sign()['ok'];assert fake.fake_attempts()==0
 lib.fake_store_fail(0);assert sign(b'0000')['code']=='pin_incorrect';assert fake.fake_attempts()==1
 assert sign()['ok'] and out.exists();assert fake.fake_attempts()==2
 assert call('unpair',b'TEST')['ok'];assert call('pairings')['cards']==[]
 out.unlink();assert sign()['code']=='pairing_required';assert fake.fake_attempts()==2
assert pair()['ok'];assert call('unpair',b'')['ok'];assert call('pairings')['cards']==[]
assert not call('unpair',b'../escape')['ok']
before=fake.fake_pair_attempts();res=pair(b'88888888');assert res['code']=='pairing_preparation_failed' and res['nativeCode']==-37;assert fake.fake_pair_attempts()==before
res=pair(b'77777777');assert res['code']=='pairing_sod_failed' and res['nativeCode']==-44;assert fake.fake_pair_attempts()==before+1
assert call('pairings')['cards']==[]
print(json.dumps({'passed':True,'checks':checks,'realCardOperations':0,'realCredentialStoreOperations':0}))

assert pair()['ok']
for symbol,graphic in [('sign_paired_network_replace',False),('sign_pdf_paired_network_replace',True)]:
 f=getattr(lib,'cie_bridge_'+symbol)
 f.argtypes=([c.c_char_p]*6+[c.c_int32]+[c.c_double]*4+[c.c_void_p]) if graphic else ([c.c_char_p]*6+[c.c_void_p])
 f.restype=c.c_void_p
 with tempfile.TemporaryDirectory() as d:
  source=Path(d)/'document.pdf';source.write_bytes(b'Synthetic paired input')
  output=Path(d)/'firmato.pdf';output.write_bytes(b'Previous signed bytes')
  pin=c.create_string_buffer(b'5678');before=fake.fake_attempts()
  args=[b'Reader',b'TEST',str(source).encode(),str(output).encode()]
  result=call(symbol,*args,pin,b'image.png',0,.1,.1,.3,.1,None) if graphic else call(symbol,*args,b'p7m',pin,None)
  assert result['ok'] and not pin.value and fake.fake_attempts()==before+1
  assert output.read_bytes()!=b'Previous signed bytes'
assert call('unpair',b'TEST')['ok']
print('Explicit paired PDF/P7M replacement passed; synthetic storage only')
