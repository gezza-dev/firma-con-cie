#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Web provisioning boundaries with fake authentication/storage only."""
import ctypes as c,json,os,sys
import tempfile,os
_pairing_state=tempfile.TemporaryDirectory(prefix='cie-pairing-state-')
os.environ['CIE_PAIRING_TEST_STATE']=_pairing_state.name
from pathlib import Path
path=Path(sys.argv[1]).resolve();runtime=path.parent.parent if path.parent.name=='tests' else path.parent
cookie=os.add_dll_directory(str(runtime)) if os.name=='nt' else None
lib=c.CDLL(str(path));fake=c.CDLL(sys.argv[3]);lib.cie_bridge_free.argtypes=[c.c_void_p]
for name,size in [('load',2),('web_enroll',3),('web_forget',1),('pairings',0)]:
 f=getattr(lib,'cie_bridge_'+name);f.argtypes=[c.c_char_p]*size;f.restype=c.c_void_p
checks=0
def call(name,*args):
 global checks
 p=getattr(lib,'cie_bridge_'+name)(*args)
 try:
  value=c.string_at(p).decode();assert '12345678' not in value;checks+=1;return json.loads(value)
 finally:lib.cie_bridge_free(p)
def enroll(pin=b'12345678',card=b'TEST'):
 b=c.create_string_buffer(pin);r=call('web_enroll',b'Test reader',card,b);assert b.raw[:len(pin)]==bytes(len(pin));return r
assert call('load',sys.argv[2].encode(),sys.argv[3].encode())['canConfigureWeb']
assert call('pairings')['cards']==[]
assert enroll(b'1234')['code']=='invalid_pin';assert fake.fake_web_attempts()==0
assert not enroll(card=b'CHANGED')['ok'];assert fake.fake_web_attempts()==0
assert enroll(b'00000000')['code']=='pin_incorrect';assert fake.fake_web_attempts()==1
assert enroll(b'99999999')['code']=='pin_locked';assert fake.fake_web_attempts()==2
assert enroll()['certificateHex']=='300100';assert fake.fake_web_attempts()==3
assert call('pairings')['cards']==[] # Web setup never stores a PIN fragment.
assert call('web_forget',b'TEST')['ok'];assert not call('web_forget',b'../escape')['ok']
print(json.dumps(dict(passed=True,checks=checks,realCardOperations=0,realCredentialStoreOperations=0)))
