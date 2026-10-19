#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fault-injected PIN/PUK workflow. No real card or system credential operations."""
import ctypes as c, json, os, sys, tempfile, subprocess
from pathlib import Path
state=tempfile.TemporaryDirectory(prefix='cie-pin-invalidation-')
os.environ['CIE_PAIRING_TEST_STATE']=state.name
path=Path(sys.argv[1]).resolve()
_runtime=path.parent.parent if path.parent.name=='tests' else path.parent
_dll=os.add_dll_directory(str(_runtime)) if os.name=='nt' else None
lib=c.CDLL(str(path));fake=c.CDLL(sys.argv[3]);lib.cie_bridge_free.argtypes=[c.c_void_p]
def call(name,*args):
 fn=getattr(lib,'cie_bridge_'+name);fn.argtypes=[c.c_char_p]*len(args);fn.restype=c.c_void_p
 ptr=fn(*args)
 try: return json.loads(c.string_at(ptr))
 finally: lib.cie_bridge_free(ptr)
def pair():
 pin=c.create_string_buffer(b'12345678');result=call('pair',b'Reader',b'TEST',pin);assert not pin.value;return result
def change(op,auth=b'10293847',replacement=b'86420975'):
 a=c.create_string_buffer(auth);b=c.create_string_buffer(replacement)
 result=call(op,b'Reader',b'TEST',a,b);assert not a.value and not b.value;return result
assert call('load',sys.argv[2].encode(),sys.argv[3].encode())['canChangePin']
for op in ['change_pin','unblock_pin']:
 for auth,replacement,code in [(b'10293847',b'86420975',None),(b'00000000',b'86420975','pin_incorrect' if op=='change_pin' else 'puk_incorrect'),(b'10293847',b'97531086','pin_operation_indeterminate')]:
  assert pair()['ok']
  lib.fake_store_erase_fail(1)
  before=fake.fake_pin_attempts();deletions=lib.fake_store_erase_calls()
  result=change(op,auth,replacement)
  assert fake.fake_pin_attempts()==before+1 and lib.fake_store_erase_calls()==deletions+1
  assert result['pairingInvalidated'] and result['cleanupCode']=='pairing_store_cleanup_failed'
  assert result['cleanupNativeCode']==-25308
  if code: assert not result['ok'] and result['code']==code
  else: assert result['ok'] and 'Home' in result['message']
  assert call('pairings')['cards']==[]
  assert call('enrollments')['invalidatedCards']==['TEST']
  assert call('enrollments')['records']==[]
  assert call('complete_enrollment',b'TEST')['code']=='enrollment_read_required'
  # A leftover credential must not reach the signer, even after cleanup failed.
  with tempfile.TemporaryDirectory() as d:
   source=Path(d)/'input';source.write_bytes(b'Synthetic fixture');out=Path(d)/'output'
   suffix=c.create_string_buffer(b'5678');calls=fake.fake_attempts()
   fn=lib.cie_bridge_sign_paired_network;fn.argtypes=[c.c_char_p]*6+[c.c_void_p];fn.restype=c.c_void_p
   p=fn(b'Reader',b'TEST',os.fsencode(source),os.fsencode(out),b'p7m',suffix,None)
   try: assert json.loads(c.string_at(p))['code']=='pairing_required'
   finally:lib.cie_bridge_free(p)
   assert fake.fake_attempts()==calls and not suffix.value and not out.exists()
  # Restart: marker survives even when an in-memory credential store does not.
  child='''import ctypes as c,json,sys,os
from pathlib import Path
p=Path(sys.argv[1]).resolve();root=p.parent.parent if p.parent.name=='tests' else p.parent
scope=os.add_dll_directory(str(root)) if os.name=='nt' else None
lib=c.CDLL(str(p));lib.cie_bridge_enrollments.restype=c.c_void_p;lib.cie_bridge_free.argtypes=[c.c_void_p]
p=lib.cie_bridge_enrollments()
try: assert json.loads(c.string_at(p))['invalidatedCards']==['TEST']
finally:lib.cie_bridge_free(p)
'''
  subprocess.run([sys.executable,'-c',child,str(path)],check=True,env=os.environ.copy())
  lib.fake_store_erase_fail(0)
  # Only a fresh successful authentication restores pairing.
  a=c.create_string_buffer(b'00000000');assert not call('pair',b'Reader',b'TEST',a)['ok']
  assert call('pairings')['cards']==[]
  assert pair()['ok'] and call('pairings')['cards']==['TEST']
# An entirely locked protected store also cannot block the card operation.
lib.fake_store_fail(1);before=fake.fake_pin_attempts();result=change('change_pin')
assert result['ok'] and result['cleanupWarning'] and fake.fake_pin_attempts()==before+1
assert call('enrollments')['invalidatedCards']==['TEST']
lib.fake_store_fail(0)
# Failure to persist invalidation must stop BEFORE any authentication.
root=os.environ['CIE_PAIRING_TEST_STATE'];bad=Path(root)/'unusable';bad.write_text('file')
os.environ['CIE_PAIRING_TEST_STATE']=str(bad);before=fake.fake_pin_attempts()
result=change('change_pin');assert result['code']=='pairing_invalidation_unavailable'
assert fake.fake_pin_attempts()==before and 'nessun PIN' in result['message']
os.environ['CIE_PAIRING_TEST_STATE']=root
print('PIN_INVALIDATION: PIN/PUK success/error/uncertain, locked store, persistent restart, stale suffix rejected, no retries; real card operations=0')
