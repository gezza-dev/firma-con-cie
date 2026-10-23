#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Test the private offline DSS runtime. Never signs with CIE or uses a PIN."""
import argparse,hashlib,json,os,platform,subprocess,tempfile
from pathlib import Path
from runtime_test_tools import test_tools_runtime
from ltv_runtime import runtime_architecture
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
p.add_argument('--test-tools-runtime',type=Path,help='External development harness; production JARs/JVM come from --runtime')
p.add_argument('--document',type=Path,action='append',default=[]);p.add_argument('--expect-no-lta',action='store_true')
a=p.parse_args();runtime=a.runtime.resolve();ltv=runtime/'ltv'
test_tools=test_tools_runtime(runtime,a.test_tools_runtime)
architecture=runtime_architecture()
java=ltv/'jre'/architecture/'bin'/('java.exe' if os.name=='nt' else 'java')
manifest=json.loads((runtime/'backend-manifest.json').read_text())
for name,digest in manifest['files'].items():
    assert hashlib.sha256((runtime/name).read_bytes()).hexdigest()==digest,'Runtime checksum mismatch: '+name
assert java.is_file(),'Private Java runtime missing'
environment={k:v for k,v in os.environ.items() if k.upper() in ['SYSTEMROOT','WINDIR','TEMP','TMP','HOME','LANG','LC_ALL']}
classpath=str(ltv/'cie-ltv-worker.jar')+os.pathsep+str(ltv/'lib/*')
def run(main,args,tests=False):
    cp=classpath+(os.pathsep+str(test_tools/'ltv/tests/cie-ltv-tests.jar') if tests else '')
    return subprocess.run([str(java),'-Xmx512m','-Djava.awt.headless=true','-Dfile.encoding=UTF-8','-cp',cp,main,*map(str,args)],
        env=environment,capture_output=True,timeout=90)
report={'engine':'EU DSS 6.5.1','offline':True,'runtimeHashesVerified':True,'testRootsInstalled':False,'newCieSignatures':0}
with tempfile.TemporaryDirectory(prefix='cie-lta-test-') as folder:
    result=run('it.cieid.ltv.LtvSelfTest',[folder],tests=True)
    lines=result.stdout.decode('utf-8',errors='replace').splitlines()
    report['selfTests']={'exitCode':result.returncode,'passedCases':sum(line.startswith('PASS ') for line in lines),
        'cases':[line[5:] for line in lines if line.startswith('PASS ')]}
    if result.returncode: report['selfTests']['diagnostic']=result.stderr.decode('utf-8',errors='replace')[-6000:]
    # The production policy must reject the same synthetic fixture root.
    negative=run('it.cieid.ltv.Worker',[Path(folder)/'renewed-lta.pdf',ltv/'trust'])
    native=json.loads(negative.stdout.decode('utf-8'))
    report['productionRejectsSyntheticRoot']=negative.returncode==0 and native.get('ok') is True and native.get('allSignaturesLtaValid') is False
report['existingDocuments']=[]
for document in a.document:
    result=run('it.cieid.ltv.Worker',[document.resolve(),ltv/'trust'])
    value=json.loads(result.stdout.decode('utf-8'))
    report['existingDocuments'].append(value)
report['passed']=report['selfTests']['exitCode']==0 and report['selfTests']['passedCases']>=14 and report['productionRejectsSyntheticRoot']
if a.expect_no_lta:
    report['passed'] &= all(r.get('ok') is True and r.get('allSignaturesLtaValid') is False for r in report['existingDocuments'])
a.report.parent.mkdir(exist_ok=True,parents=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
