#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""AppImage runtime checks inside a marked rootless container, synthetic data only."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
from linux_package_common import sha
from package_linux_appimage import NSS_FILES


def check(appdir,manifest,tools,guard,report):
    mapping=Path('/proc/self/uid_map').read_text().split()
    if (not Path('/work/.cie-appimage-isolated-root').is_file() or len(mapping)!=3 or mapping[2]!='1'
            or Path('/run/pcscd/pcscd.comm').exists() or Path('/dev/bus/usb').exists()):
        raise RuntimeError('Run only in the marked private root, without card interfaces')
    value=json.loads(manifest.read_text());report.mkdir(parents=True,exist_ok=True)
    for name,digest in value['files'].items():
        assert sha(appdir/name)==digest,name
    runtime=appdir/'usr/lib/firma-con-cie/cie_native';app=runtime.parent
    elfs=0
    for name in value['files']:
        p=appdir/name
        with p.open('rb') as f:
            if f.read(4)!=b'\x7fELF':continue
        elfs+=1;link_env=dict(os.environ)
        if p.name in NSS_FILES:
            link_env['LD_LIBRARY_PATH']=str(appdir/'usr/lib')
        if '/ltv/jre/' in str(p):
            jre=runtime/'ltv/jre/linux-x86_64/lib'
            link_env['LD_LIBRARY_PATH']=str(jre)+':'+str(jre/'server')
        command=['ldd',str(p)]
        if p.name in NSS_FILES:
            # Avoid giving the destination's shell our older readline/tinfo.
            # This models modutil's own loader, after its wrapper has exec'd it.
            link_env.pop('LD_LIBRARY_PATH',None)
            command=['/lib64/ld-linux-x86-64.so.2','--library-path',str(appdir/'usr/lib'),'--list',str(p)]
        result=subprocess.run(command,check=True,text=True,capture_output=True,env=link_env)
        assert 'not found' not in result.stdout,(name,result.stdout)
        # Every link to PC/SC must use the destination system's client.
        for line in result.stdout.splitlines():
            if 'libpcsclite.so.1 =>' in line:assert str(appdir) not in line,line
    assert elfs==value['elfFilesChecked']
    with tempfile.TemporaryDirectory(prefix='appimage-software-') as home:
        env=dict(os.environ,HOME=home,XDG_CONFIG_HOME=home+'/config',XDG_DATA_HOME=home+'/data',
                 XDG_CACHE_HOME=home+'/cache',LD_PRELOAD=str(guard))
        for script in ['appimage_firefox_setup.py','appimage_chrome_setup.py']:
            result=subprocess.run([str(app/'tools/python3'),str(runtime/'browser_setup'/script),'--action','inspect'],
                check=True,capture_output=True,text=True,env=env)
            inspected=json.loads(result.stdout);assert inspected['ok'],inspected
        assert not list(Path(home).rglob('pkcs11.txt'))
        for script,out in [('smoke_native.py','smoke.json'),('test_ltv.py','dss.json')]:
            result=subprocess.run([sys.executable,str(Path(__file__).parent/script),'--runtime',str(runtime),
                '--test-tools-runtime',str(tools),'--report',str(report/out)],env=env,capture_output=True,text=True)
            (report/(script+'.log')).write_text(result.stdout+result.stderr)
            assert result.returncode==0,(script,result.stdout[-3000:],result.stderr[-3000:])
        smoke=json.loads((report/'smoke.json').read_text());assert smoke['backendLoaded'] and 'cardDetection' not in smoke
        dss=json.loads((report/'dss.json').read_text());assert dss['passed'] and dss['selfTests']['passedCases']>=14
        # This helper runs in its own process so GTK/host libraries cannot
        # accidentally satisfy missing private PDFium/Python dependencies.
        source='''import ctypes,sys
p=ctypes.CDLL(sys.argv[1]);p.FPDF_InitLibrary();p.FPDF_LoadDocument.argtypes=[ctypes.c_char_p,ctypes.c_char_p];p.FPDF_LoadDocument.restype=ctypes.c_void_p
d=p.FPDF_LoadDocument(sys.argv[2].encode(),None);assert d;p.FPDF_GetPageCount.argtypes=[ctypes.c_void_p];assert p.FPDF_GetPageCount(d)>0
p.FPDF_CloseDocument.argtypes=[ctypes.c_void_p];p.FPDF_CloseDocument(d);p.FPDF_DestroyLibrary()
'''
        subprocess.run([str(app/'tools/python3'),'-c',source,str(app/'lib/libpdfium.so'),str(app/'data/flutter_assets/assets/prova.pdf')],env=env,check=True)
    result=dict(passed=True,artifactSha256=value['sha256'],distribution=Path('/etc/os-release').read_text(),payloadFilesVerified=len(value['files']),
        elfFilesResolved=elfs,bundledPythonAndNssInspectionPassed=True,publicBrowserConfigurationModified=False,
        nativeSmokeWithoutDetectPassed=True,dssCasesPassed=dss['selfTests']['passedCases'],
        syntheticRootRejected=dss['productionRejectsSyntheticRoot'],pdfiumLoaded=True,pcscFromHost=True,
        realCardTestsRun=False,hostInstallationPerformed=False)
    (report/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--appdir',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True)
    p.add_argument('--test-tools',type=Path,required=True);p.add_argument('--guard',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();check(a.appdir,a.manifest,a.test_tools,a.guard,a.report)
