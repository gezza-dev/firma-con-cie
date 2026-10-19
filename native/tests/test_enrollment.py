#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Isolated enrollment v2 ABI boundaries. Synthetic adapter/in-memory stores only."""
import ctypes as c,json,sys
import tempfile,os
_pairing_state=tempfile.TemporaryDirectory(prefix='cie-pairing-state-')
os.environ['CIE_PAIRING_TEST_STATE']=_pairing_state.name
from pathlib import Path
_bridge_path=Path(sys.argv[1]).resolve()
_runtime=_bridge_path.parent.parent if _bridge_path.parent.name=='tests' else _bridge_path.parent
_dll_scope=os.add_dll_directory(str(_runtime)) if os.name=='nt' else None
bridge=c.CDLL(str(_bridge_path));adapter=c.CDLL(sys.argv[3]);checks=0
bridge.cie_bridge_free.argtypes=[c.c_void_p]
def call(name,*args):
 global checks
 fn=getattr(bridge,'cie_bridge_'+name);fn.restype=c.c_void_p
 values=[x.encode() if isinstance(x,str) else x for x in args]
 ptr=fn(*values)
 try:result=json.loads(c.string_at(ptr))
 finally:bridge.cie_bridge_free(ptr)
 checks+=1
 return result
def pin(value='12345678'):return c.create_string_buffer(value.encode())
def enroll(value='12345678',card='TEST'):
 p=pin(value);result=call('enroll','READER',card,p);assert p.raw==b'\0'*len(p);return result
assert call('load',sys.argv[2],sys.argv[3])['enrollmentVersion']==2
legacy=pin();assert call('pair','READER','TEST',legacy)['ok']
assert call('enrollments')['records'][0]['version']==1
before=adapter.fake_pair_attempts();web=adapter.fake_web_attempts()
assert enroll('00000000')['code']=='pin_incorrect'
assert enroll('99999999')['code']=='pin_locked'
assert enroll(card='OTHER')['code']=='card_changed'
assert adapter.fake_enrollment_attempts()==2
bridge.fake_store_fail(1);attempts=adapter.fake_enrollment_attempts();assert enroll()['code']=='pairing_store_unavailable';assert adapter.fake_enrollment_attempts()==attempts;bridge.fake_store_fail(0)
bridge.fake_enrollment_store_fail(1);assert enroll()['code']=='enrollment_public_store_failed';assert call('enrollments')['records'][0]['version']==1
bridge.fake_enrollment_store_fail(2);failed=enroll();assert not failed['ok'] and failed['publicDataSaved'];assert call('enrollments')['records'][0]['fullName']=='Nome Cognome'
bridge.fake_enrollment_store_fail(0);success=enroll();assert success['ok'] and success['readyForSigning'] and success['version']==2
assert adapter.fake_pair_attempts()==before and adapter.fake_web_attempts()==web
count=adapter.fake_enrollment_attempts()
for _ in range(3):assert call('complete_enrollment','TEST')['ok']
assert adapter.fake_enrollment_attempts()==count
encoded=json.dumps(success);assert '1234' not in encoded and '5678' not in encoded
bridge.fake_enrollment_store_fail(3);assert call('forget_enrollment','TEST')['code']=='enrollment_removal_incomplete';assert 'TEST' in call('pairings')['cards']
bridge.fake_enrollment_store_fail(0);assert call('forget_enrollment','TEST')['ok'];assert not call('enrollments')['records'];assert call('forget_enrollment','TEST')['ok']
assert call('complete_enrollment','TEST')['code']=='enrollment_read_required';assert adapter.fake_enrollment_attempts()==count
print('ENROLLMENT_ABI_CHECKS='+str(checks)+'; one authentication, recovery without PIN, partial failures and existing prefix preservation')
