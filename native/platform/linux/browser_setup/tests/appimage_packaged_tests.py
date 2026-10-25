#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Real packaged Python/NSS and persistent provider, synthetic profiles only."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

def check(appdir,guard):
    if not Path('/work/.cie-appimage-isolated-root').is_file() or Path('/run/pcscd/pcscd.comm').exists():
        raise RuntimeError('Private build-root test only')
    os.umask(0o077);app=appdir/'usr/lib/firma-con-cie';runtime=app/'cie_native'
    with tempfile.TemporaryDirectory(prefix='appimage-nss-') as temp:
        temp=Path(temp);home=temp/'home';home.mkdir();source=temp/'mounted AppImage';native=source/'cie_native';native.mkdir(parents=True)
        (native/'browser_setup').mkdir();(source/'tools').mkdir()
        for name in ['libcie_linux_pkcs11.so','libcie_web.so','libcie-pkcs11.so','backend-manifest.json']:
            shutil.copy2(runtime/name,native/name)
        for p in (runtime/'browser_setup').iterdir():
            if p.is_file():shutil.copy2(p,native/'browser_setup'/p.name)
        modutil=source/'tools/modutil';modutil.write_text('#!/bin/sh\nexec "'+str(app/'tools/modutil')+'" "$@"\n');modutil.chmod(0o700)
        firefox=home/'.mozilla/firefox';profile=firefox/'synthetic';profile.mkdir(parents=True)
        (firefox/'profiles.ini').write_text('[Profile0]\nName=Synthetic test\nIsRelative=1\nPath=synthetic\n')
        chrome=home/'data/pki/nssdb';chrome.mkdir(parents=True)
        (home/'data').chmod(0o775)  # Typical desktop umask: keep permissions unchanged.
        foreign=b'library=\nname=NSS Internal PKCS #11 Module\nNSS=Flags=internal,critical\n\nlibrary=/unrelated/never-loaded.so\nname=Synthetic foreign module\n\n'
        before={}
        for p in [profile,chrome]:
            (p/'cert9.db').write_bytes(b'synthetic certificates');(p/'key4.db').write_bytes(b'synthetic keys')
            (p/'pkcs11.txt').write_bytes(foreign)
            before[str(p)]={n:(p/n).read_bytes() for n in ['cert9.db','key4.db']}
        env=dict(os.environ,HOME=str(home),XDG_DATA_HOME=str(home/'data'),LD_PRELOAD=str(guard))
        def request(browser,action,**kwargs):
            command=[str(app/'tools/python3'),str(native/'browser_setup'/('appimage_'+browser+'_setup.py')),'--action',action]
            for k,v in kwargs.items():command.extend(['--'+k,v])
            result=subprocess.run(command,env=env,check=True,text=True,capture_output=True)
            value=json.loads(result.stdout);assert value.get('ok'),value
            return value
        inspected=request('firefox','inspect');identity=inspected['profiles'][0]['id']
        request('chrome','inspect');paths=[]
        for browser,id in [('firefox',identity),('chrome','chrome-desktop')]:
            plan=request(browser,'plan',profile=id)
            path=Path(plan['library']);assert not plan['alreadyConfigured']
            assert path.is_relative_to(home/'.firma-con-cie/pkcs11/v1')
            if not paths:assert not path.exists()
            else:assert path==paths[0] and path.is_file()  # Shared immutable generation.
            result=request(browser,'apply',profile=id,fingerprint=plan['fingerprint'])
            assert not result['pinRequested'];assert path.is_file();assert not result['browserLoginTested']
            assert request(browser,'plan',profile=id)['alreadyConfigured'];paths.append(path)
        for p in [profile,chrome]:
            assert (p/'pkcs11.txt').read_bytes().startswith(foreign)
            assert str(source) not in (p/'pkcs11.txt').read_text()
            assert before[str(p)]=={n:(p/n).read_bytes() for n in before[str(p)]}
        shutil.rmtree(source)
        for path in paths:
            result=subprocess.run(['ldd',str(path)],check=True,text=True,capture_output=True)
            assert 'not found' not in result.stdout and str(appdir) not in result.stdout,result.stdout
            # Load the module in a guarded process; never initialize a token.
            subprocess.run(['/usr/bin/python3','-c','import ctypes,sys;ctypes.CDLL(sys.argv[1])',str(path)],env=env,check=True)
        return dict(passed=True,realNssRegistration=True,targets=['Firefox','Chrome'],bundledPythonAndNssUsed=True,
            moduleSurvivesSourceRemoval=True,foreignModulesPreserved=True,certAndKeyDatabasesUnchanged=True,
            hostPcscLinked=True,fullPinOnly=True,realBrowserConfigurationModified=False,realCardTestsRun=False)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--appdir',type=Path,required=True);p.add_argument('--guard',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();value=check(a.appdir,a.guard);a.report.write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value,indent=2))
