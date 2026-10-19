#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""PIN/PUK synthetic and invalid-input tests only. Never authenticates to a card."""
import argparse,ctypes,hashlib,json,os,platform,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
r=a.runtime.resolve();win=os.name=='nt';suffix='.dll' if win else '.dylib' if platform.system()=='Darwin' else '.so';prefix='' if win else 'lib'
directory=os.add_dll_directory(str(r)) if win else None
manifest=json.loads((r/'backend-manifest.json').read_text(encoding='utf-8'))
for name,digest in manifest['files'].items():assert hashlib.sha256((r/name).read_bytes()).hexdigest()==digest,name
bridge=r/(prefix+'cie_bridge'+suffix);lib=ctypes.CDLL(str(bridge));lib.cie_bridge_free.argtypes=[ctypes.c_void_p]
def call(name,*args):
 f=getattr(lib,'cie_bridge_'+name);f.argtypes=[ctypes.c_char_p]*len(args);f.restype=ctypes.c_void_p;out=f(*args);assert out
 try:return json.loads(ctypes.string_at(out).decode('utf-8'))
 finally:lib.cie_bridge_free(out)
cap=call('load',str(r/(prefix+'cie-pkcs11'+suffix)).encode('utf-8'),str(r/(prefix+'cie_card_adapter'+suffix)).encode('utf-8'))
assert cap['ok'] and cap['canChangePin'] and cap['canUnblockPin']
for op in ['change_pin','unblock_pin']:
 # Rejected by bridge validation BEFORE any real adapter/card call.
 auth=ctypes.create_string_buffer(b'bad');new=ctypes.create_string_buffer(b'86420975')
 result=call(op,b'SYNTHETIC-NOT-A-READER',b'TEST',auth,new)
 assert result['code']==('invalid_pin' if op=='change_pin' else 'invalid_puk')
 assert auth.raw[:3]==b'\0'*3 and new.raw[:8]==b'\0'*8
tests=r/'tests';environment={k:v for k,v in os.environ.items() if k.upper() in ['SYSTEMROOT','WINDIR','TEMP','TMP','HOME','LANG','LC_ALL']}
if win:environment['PATH']=str(r)+os.pathsep+environment.get('SYSTEMROOT',environment.get('SystemRoot',r'C:\Windows'))+'\\System32'
checks=[]
for label,cmd in [('workflow',[str(tests/('cie_pin_tests'+('.exe' if win else '')))]),('bridge',[sys.executable,str(tests/'test_bridge.py'),str(tests/(prefix+'cie_bridge_pairing_tests'+suffix)),str(tests/(prefix+'fake_backend'+suffix)),str(tests/(prefix+'fake_card_adapter'+suffix))]),('pairing_invalidation',[sys.executable,str(tests/'test_pin_invalidation.py'),str(tests/(prefix+'cie_bridge_pairing_tests'+suffix)),str(tests/(prefix+'fake_backend'+suffix)),str(tests/(prefix+'fake_card_adapter'+suffix))])]:
 run=subprocess.run(cmd,env=environment,capture_output=True,timeout=45)
 checks.append({'test':label,'exitCode':run.returncode,'output':run.stdout.decode('utf-8',errors='replace')})
 if run.returncode:checks[-1]['diagnostic']=run.stderr.decode('utf-8',errors='replace')[-4000:]
report={'passed':all(c['exitCode']==0 for c in checks),'runtimeHashesVerified':True,'changePinAvailable':True,'unblockPinAvailable':True,'realCardAuthenticationAttempts':0,'pinOrPukChanged':False,'invalidInputBuffersWiped':True,'tests':checks}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
