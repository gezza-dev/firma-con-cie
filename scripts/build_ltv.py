#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the shared local DSS worker and add private JVMs to a native runtime.

No installation, system trust modification, online validation or card/PIN access.
Dependencies and source JARs remain separate to preserve LGPL relinkability.
"""
import argparse, hashlib, json, os, shutil, subprocess, tarfile, urllib.request, zipfile
from pathlib import Path
from ltv_runtime import runtime_architecture
ROOT=Path(__file__).resolve().parents[1]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def run(*args,env=None): subprocess.run(list(map(str,args)),cwd=ROOT,env=env,check=True)
def extract(item,cache,name):
    archive=cache/item['archive']
    if not archive.exists():
        with urllib.request.urlopen(item['url'],timeout=60) as response,archive.open('wb') as output:
            shutil.copyfileobj(response,output)
    if digest(archive)!=item['sha256']: raise RuntimeError('JRE archive checksum mismatch: '+name)
    destination=cache/name
    if not destination.exists():
        destination.mkdir()
        if archive.suffix=='.zip':
            with zipfile.ZipFile(archive) as source:
                for member in source.namelist():
                    if not (destination/member).resolve().is_relative_to(destination.resolve()): raise RuntimeError('Unsafe ZIP path')
                source.extractall(destination)
        else:
            with tarfile.open(archive) as source:
                for member in source.getmembers():
                    if not (destination/member.name).resolve().is_relative_to(destination.resolve()): raise RuntimeError('Unsafe TAR path')
                source.extractall(destination)
    paths=list(destination.glob('*/Contents/Home')) if name.startswith('macos') else list(destination.glob('*'))
    return next(p for p in paths if (p/'bin'/('java.exe' if name.startswith('windows') else 'java')).exists())
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['java-home','maven','base-runtime','output']: parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--system',choices=['macos','windows','linux'],required=True)
    parser.add_argument('--tools-cache',type=Path,default=ROOT/'.build/ltv-tools')
    parser.add_argument('--skip-java-build',action='store_true')
    parser.add_argument('--refresh-dependency-lock',action='store_true',help='Explicitly accept the resolved JAR hashes after dependency review')
    a=parser.parse_args(); build=ROOT/'.build/ltv-java'; repo=ROOT/'.build/ltv-maven-repository'
    env=os.environ.copy(); env['JAVA_HOME']=str(a.java_home.resolve())
    maven=[str(a.maven.resolve()),'-B','-f',str(ROOT/'native/ltv/pom.xml'),'-Dmaven.repo.local='+str(repo)]
    if not a.skip_java_build:
        # Avoid stale Java ABI classes after source sync from a file provider.
        run(*maven,'clean','package',env=env)
        if (build/'lib').exists(): shutil.rmtree(build/'lib')
        run(*maven,'dependency:copy-dependencies','-DincludeScope=runtime','-DoutputDirectory='+str(build/'lib'),env=env)
        run(*maven,'dependency:copy-dependencies','-DincludeScope=runtime','-Dclassifier=sources',
            '-DfailOnMissingClassifierArtifact=false','-DoutputDirectory='+str(build/'dependency-sources'),env=env)
        run(a.java_home/'bin/jar','--create','--file',build/'cie-ltv-tests.jar','--date=2026-10-16T00:00:00Z',
            '-C',build/'test-classes','it/cieid/ltv/LtvSelfTest.class',env=env)
        # Include nested fixture helpers too; none of these classes are on the production classpath.
        run(a.java_home/'bin/jar','--update','--file',build/'cie-ltv-tests.jar','--date=2026-10-16T00:00:00Z',
            '-C',build/'test-classes','it/cieid/ltv/LtvSelfTest$Identity.class',env=env)
        run(a.java_home/'bin/jar','--update','--file',build/'cie-ltv-tests.jar','--date=2026-10-16T00:00:00Z',
            '-C',build/'test-classes','it/cieid/ltv/HistoricalCrlTest.class',env=env)
        run(a.java_home/'bin/jar','--update','--file',build/'cie-ltv-tests.jar','--date=2026-10-16T00:00:00Z',
            '-C',build/'test-classes','it/cieid/ltv/NetworkTransportTest.class',env=env)
    # File-provider conflict copies ("... 2.jar") are not Maven artifacts and
    # can be offloaded. Preserve them in the cache, never hydrate/ship/execute them.
    import re
    jars={p.name:digest(p) for p in sorted((build/'lib').glob('*.jar'))
        if not re.search(r' \d+\.jar$',p.name)}
    lockfile=ROOT/'native/ltv/dependencies.lock.json'
    if a.refresh_dependency_lock:
        lockfile.write_text(json.dumps({'dssVersion':'6.5.1','jars':jars},indent=2)+'\n')
    if not lockfile.exists() or jars!=json.loads(lockfile.read_text())['jars']: raise RuntimeError('JAR dependency lock mismatch')
    if a.output.exists(): raise RuntimeError('Choose a new output folder; existing runtimes are preserved')
    shutil.copytree(a.base_runtime,a.output)
    target=a.output/'ltv'; target.mkdir()
    fetcher = a.base_runtime/('cie_crl_fetch'+('.exe' if a.system == 'windows' else ''))
    if not fetcher.is_file(): raise RuntimeError('Rebuild native runtime: CRL transport missing')
    (target/'fetcher').mkdir()
    shutil.copy2(fetcher,target/'fetcher'/fetcher.name)
    if a.system == 'windows':
        for name in ['libwinpthread-1.dll','libgcc_s_seh-1.dll','libstdc++-6.dll']:
            shutil.copy2(a.base_runtime/name,target/'fetcher'/name)
    shutil.copyfile(build/'cie-ltv-worker.jar',target/'cie-ltv-worker.jar')
    (target/'lib').mkdir()
    for name in jars: shutil.copyfile(build/'lib'/name,target/'lib'/name)
    (target/'tests').mkdir()
    shutil.copyfile(build/'cie-ltv-tests.jar',target/'tests/cie-ltv-tests.jar')
    trust=target/'trust';trust.mkdir()
    for cert in ['root.pem','subca1.pem','subca002.pem','subca003.pem']:
        shutil.copyfile(ROOT/'native/backend/cie_sign_sdk/trust'/cert,trust/cert)
    difesa=ROOT/'native/backend/cie_sign_sdk/trust/difesa'
    for cert,expected in json.loads((difesa/'manifest.json').read_text())['pemSha256'].items():
        if digest(difesa/cert)!=expected: raise RuntimeError('PKI Difesa authority checksum mismatch: '+cert)
        shutil.copyfile(difesa/cert,trust/cert)
    shutil.copyfile(a.java_home/'lib/security/cacerts',trust/'cacerts')
    tools=json.loads((ROOT/'native/ltv/toolchain.lock.json').read_text());a.tools_cache.mkdir(exist_ok=True,parents=True)
    architectures=(['macos-arm64','macos-x86_64'] if a.system=='macos' else
                   ['windows-x86_64'] if a.system=='windows' else
                   [runtime_architecture('Linux')])
    for architecture in architectures:
        home=extract(tools['runtimes'][architecture],a.tools_cache,architecture)
        shutil.copytree(home,target/'jre'/architecture,symlinks=False)
    notices=a.output/'licenses/ltv'; notices.mkdir(parents=True)
    (notices/'dependency-sources').mkdir()
    for name in jars:
        source=build/'dependency-sources'/(Path(name).stem+'-sources.jar')
        if source.is_file(): shutil.copyfile(source,notices/'dependency-sources'/source.name)
    for jar in (target/'lib').glob('*.jar'):
        with zipfile.ZipFile(jar) as z:
            for n in z.namelist():
                if 'META-INF/' in n and any(s in n.upper() for s in ['LICENSE','NOTICE','COPYING']) and not n.endswith('/'):
                    out=notices/'jar-notices'/jar.stem/Path(n).name;out.parent.mkdir(exist_ok=True,parents=True);out.write_bytes(z.read(n))
    for filename in ['toolchain.lock.json','dependencies.lock.json','README.md']:
        shutil.copyfile(ROOT/'native/ltv'/filename,notices/filename)
    manifest=json.loads((a.output/'backend-manifest.json').read_text())
    manifest['native_base_manifest_sha256']=digest(a.base_runtime/'backend-manifest.json')
    manifest['ltv']={'engine':'EU DSS 6.5.1','java':'Eclipse Temurin 21.0.12.1+1','offline':False,
        'network':'bounded CRL GETs through private shared C++ helper; document processing local',
        'architectures':architectures,'trustStoreSha256':digest(trust/'cacerts'),'jarHashes':jars}
    manifest['source_files']={str(p.relative_to(ROOT)):digest(p) for folder in ['native','scripts']
        for p in sorted((ROOT/folder).rglob('*')) if p.is_file() and not any(v in ['runtime','__pycache__'] for v in p.relative_to(ROOT).parts)}
    manifest['files']={str(p.relative_to(a.output)):digest(p) for p in sorted(a.output.rglob('*')) if p.is_file() and p.name!='backend-manifest.json'}
    (a.output/'backend-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Private runtime with local DSS:',a.output)
if __name__=='__main__': main()
