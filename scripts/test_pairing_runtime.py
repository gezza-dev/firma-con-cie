#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Pairing with synthetic signer/storage, optionally isolated file-cache tests. No card."""
import argparse,hashlib,json,os,platform,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
p.add_argument('--file-store-test','--protected-store-test',dest='file_store_test',action='store_true',help='Exercise only temporary synthetic cache files; no OS credential stores')
a=p.parse_args();r=a.runtime.resolve();win=os.name=='nt';suffix='.dll' if win else '.dylib' if platform.system()=='Darwin' else '.so';prefix='' if win else 'lib';exe='.exe' if win else ''
m=json.loads((r/'backend-manifest.json').read_text(encoding='utf-8'))
for name,digest in m['files'].items():assert hashlib.sha256((r/name).read_bytes()).hexdigest()==digest,name
env=os.environ.copy()
if win:env['PATH']=str(r)+os.pathsep+env.get('PATH','')
t=r/'tests';commands=[('pairing_boundaries',[sys.executable,str(t/'test_pairing.py'),str(t/(prefix+'cie_bridge_pairing_tests'+suffix)),str(t/(prefix+'fake_backend'+suffix)),str(t/(prefix+'fake_card_adapter'+suffix))])]
commands.append(('strict_sod_digests',[str(t/('cie_pairing_sod_tests'+exe))]))
if a.file_store_test:
 commands.append(('isolated_file_cache',[str(t/('cie_pairing_store_tests'+exe))]))
 commands.append(('file_cache_restart_and_faults',[sys.executable,str(t/'test_pairing_file_store.py'),str(t/('cie_pairing_store_tests'+exe))]))
 commands.append(('file_cache_crypto',[str(t/('cie_cache_crypto_tests'+exe))]))
 commands.append(('file_cache_enrollment_restart',[sys.executable,str(t/'test_file_cache_enrollment.py'),str(t/(prefix+'cie_bridge_file_cache_tests'+suffix)),str(t/(prefix+'fake_backend'+suffix)),str(t/(prefix+'fake_card_adapter'+suffix))]))
checks=[]
for name,cmd in commands:
 run=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=60)
 checks.append({'name':name,'exitCode':run.returncode,'output':run.stdout.strip()})
 if run.returncode:checks[-1]['error']=run.stderr[-3000:]
report={'passed':all(x['exitCode']==0 for x in checks),'checks':checks,'runtimeHashesVerified':True,'realCardOperations':0,'realPinPukOperations':0,'productionCredentialNamespaceAccessed':False}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
