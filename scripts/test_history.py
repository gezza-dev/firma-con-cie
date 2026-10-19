#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Shared historical CRL tests and optional production document verification. No PIN."""
import argparse,hashlib,json,os,platform,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
p.add_argument('--document',type=Path,action='append',default=[])
a=p.parse_args();runtime=a.runtime.resolve();ltv=runtime/'ltv'
manifest=json.loads((runtime/'backend-manifest.json').read_text())
for name,digest in manifest['files'].items():
    assert hashlib.sha256((runtime/name).read_bytes()).hexdigest()==digest,'Runtime checksum mismatch: '+name
architecture='windows-x86_64' if os.name=='nt' else 'macos-arm64' if platform.machine()=='arm64' else 'macos-x86_64'
java=ltv/'jre'/architecture/'bin'/('java.exe' if os.name=='nt' else 'java')
helper=ltv/'fetcher'/('cie_crl_fetch.exe' if os.name=='nt' else 'cie_crl_fetch')
environment={k:v for k,v in os.environ.items() if k.upper() in ['SYSTEMROOT','WINDIR','TEMP','TMP','HOME','LANG','LC_ALL']}
lock=json.loads((runtime/'licenses/ltv/dependencies.lock.json').read_text())['jars']
cp=os.pathsep.join(map(str,[ltv/'cie-ltv-worker.jar',*[ltv/'lib'/n for n in lock]]))
report={'runtimeHashesVerified':True,'engine':'EU DSS 6.5.1','productionCodeShared':True,'newCieSignatures':0,'documents':[]}
result=subprocess.run([str(java),'-Xmx512m','-Djava.awt.headless=true','-cp',cp+os.pathsep+str(ltv/'tests/cie-ltv-tests.jar'),
    'it.cieid.ltv.HistoricalCrlTest'],env=environment,capture_output=True,timeout=120)
lines=result.stdout.decode('utf-8',errors='replace').splitlines()
report['selfTests']={'exitCode':result.returncode,'passedCases':sum(s.startswith('PASS ') for s in lines),'cases':[s[5:] for s in lines if s.startswith('PASS ')]}
a.report.parent.mkdir(exist_ok=True,parents=True)
a.report.with_suffix('.selftest.log').write_bytes(result.stdout+b'\n'+result.stderr)
blocked=[]
for url in ['file:///etc/passwd','http://127.0.0.1:9/','http://[::1]:9/','http://169.254.169.254/latest/meta-data/']:
    r=subprocess.run([str(helper),url,'1000'],env=environment,capture_output=True,timeout=4)
    blocked.append(r.returncode!=0 and not r.stdout)
report['transportRejectsLocalAndNonHttp']=all(blocked)
for document in a.document:
    before=hashlib.sha256(document.read_bytes()).hexdigest()
    r=subprocess.run([str(java),'-Xmx512m','-Djava.awt.headless=true','-Dfile.encoding=UTF-8','-cp',cp,
        'it.cieid.ltv.Worker',str(document.resolve()),str(ltv/'trust'),str(helper)],
        env=environment,capture_output=True,timeout=90)
    a.report.with_name(a.report.stem+'-document-'+str(len(report['documents']))+'.log').write_bytes(r.stderr)
    value=json.loads(r.stdout);value['originalUnchanged']=hashlib.sha256(document.read_bytes()).hexdigest()==before
    value['inputSha256']=before;report['documents'].append(value)
report['passed']=result.returncode==0 and report['selfTests']['passedCases']>=19 and report['transportRejectsLocalAndNonHttp'] and all(d.get('ok') is True and d['originalUnchanged'] for d in report['documents'])
a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'selfTests':report['selfTests']['passedCases'],
    'transportRejectsLocalAndNonHttp':report['transportRejectsLocalAndNonHttp'],
    'documents':[[{'status':s['historicalStatus'],'reason':s['historicalReason'],'reference':s['historicalReferenceTime']} for s in d.get('signatures',[])] for d in report['documents']]},indent=2))
raise SystemExit(0 if report['passed'] else 1)
