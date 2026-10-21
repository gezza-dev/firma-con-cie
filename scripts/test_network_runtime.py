#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Test native+Java proxy routing on loopback only; no CIE, system settings or uploads."""
import argparse,hashlib,json,os,platform,subprocess
from pathlib import Path
from runtime_test_tools import test_tools_runtime
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--test-tools-runtime',type=Path);a=p.parse_args();runtime=a.runtime.resolve();manifest=json.loads((runtime/'backend-manifest.json').read_text())
test_tools=test_tools_runtime(runtime,a.test_tools_runtime)
for path,digest in manifest['files'].items():assert hashlib.sha256((runtime/path).read_bytes()).hexdigest()==digest,'Runtime hash mismatch: '+path
architecture='windows-x86_64' if os.name=='nt' else 'macos-arm64' if platform.machine()=='arm64' else 'macos-x86_64';suffix='.exe' if os.name=='nt' else '';ltv=runtime/'ltv';classpath=os.pathsep.join([str(ltv/'cie-ltv-worker.jar'),str(ltv/'lib/*'),str(test_tools/'ltv/tests/cie-ltv-tests.jar')])
command=[os.sys.executable,str(test_tools/'tests/test_network.py'),str(test_tools/('tests/cie_network_test_client'+suffix)),str(ltv/('jre/'+architecture+'/bin/java'+suffix)),classpath,str(ltv/('fetcher/cie_crl_fetch'+suffix))]
environment=os.environ.copy()
if os.name=='nt':environment['PATH']=str(runtime)+os.pathsep+environment.get('PATH','')
result=subprocess.run(command,capture_output=True,timeout=60,env=environment);assert result.returncode==0,result.stderr.decode(errors='replace')[-4000:]
value=json.loads(result.stdout.decode());value['nativeAndJavaPrivatePipeVerified']=True;value['runtimeHashesVerified']=True;a.report.parent.mkdir(exist_ok=True,parents=True);a.report.write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value,indent=2))
