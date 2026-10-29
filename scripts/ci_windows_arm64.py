#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the complete Windows ARM64 artifact on disposable GitHub runners.

Linux builds the pinned native dependencies/backend. Windows ARM64 executes
regressions and builds Flutter and Inno. Never installs the production component,
enumerates a reader, configures browsers, or requests a PIN.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

from build_portable_dependencies import unpack
from build_ltv import extract
from windows_architecture import check_pe_tree, check_release_architecture, pe_machine, MACHINES

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT/'.build/windows-arm64-ci'
TRANSFER = ROOT/'.build/windows-arm64-transfer'
REPORTS = ROOT/'reports/windows-arm64'
ENV = os.environ.copy()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download(item, cache):
    cache.mkdir(parents=True, exist_ok=True)
    path = cache/item['archive']
    algorithm = 'sha256' if 'sha256' in item else 'sha512'
    if not path.exists():
        part = path.with_name(path.name+'.part')
        with urllib.request.urlopen(item['url'], timeout=90) as response, part.open('wb') as output:
            shutil.copyfileobj(response, output)
        part.replace(path)
    if hashlib.new(algorithm, path.read_bytes()).hexdigest() != item[algorithm]:
        raise ValueError('Tool archive checksum mismatch: '+path.name)
    return path


def run(*args):
    print('+ '+str(args[0])+' '+ ' '.join(map(str,args[1:])), flush=True)
    subprocess.run(list(map(str,args)), cwd=ROOT, env=ENV, check=True)


def python(script, *args):
    run(sys.executable, ROOT/'scripts'/script, *args)


def configure(source, build, *options):
    run('cmake', '-S', ROOT/source, '-B', build, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', *options)
    run('cmake', '--build', build, '--parallel', '4')


def manifest_refresh(runtime):
    path = runtime/'backend-manifest.json'
    data = json.loads(path.read_text())
    data['files'] = {p.relative_to(runtime).as_posix():sha(p) for p in sorted(runtime.rglob('*'))
                     if p.is_file() and p != path}
    path.write_text(json.dumps(data, indent=2)+'\n')


def native():
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise ValueError('The native phase requires the Ubuntu x64 CI runner')
    if TRANSFER.exists():
        raise ValueError('Use a fresh CI checkout; transfer output already exists')
    tools = json.loads((ROOT/'packaging/windows/arm64-toolchain.lock.json').read_text())
    llvm = WORK/'llvm'
    llvm.mkdir(parents=True, exist_ok=True)
    home = unpack(download(tools['llvm-mingw'], WORK/'downloads'), llvm)
    ENV['PATH'] = str(home/'bin')+os.pathsep+ENV['PATH']
    python('build_portable_dependencies.py', '--target', 'windows-arm64', '--arch', 'arm64')
    deps = ROOT/'.build/dependencies/windows-arm64'
    toolchain = '-DCMAKE_TOOLCHAIN_FILE='+str(deps/'mingw.cmake')
    runtime = WORK/'native-base'
    python('build_native.py', '--system', 'windows', '--windows-architecture', 'arm64',
           '--dependency-prefix', deps/'prefix', '--toolchain', deps/'mingw.cmake',
           '--build-dir', WORK/'native-build', '--output', runtime)
    # Static LLVM/libc++ and MinGW runtime attribution travels with the app.
    notices = runtime/'licenses/llvm-mingw'
    notices.mkdir(parents=True)
    count = 0
    for p in home.rglob('*'):
        if p.is_file() and any(s in p.name.lower() for s in ('license', 'copying', 'copyright', 'notice')):
            target = notices/p.relative_to(home)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)
            count += 1
    if not count:
        raise ValueError('LLVM-MinGW runtime license material missing')
    (notices/'toolchain.json').write_text(json.dumps(tools['llvm-mingw'],indent=2)+'\n')
    manifest_refresh(runtime)
    ltv = json.loads((ROOT/'native/ltv/toolchain.lock.json').read_text())
    cache = WORK/'java-tools'
    cache.mkdir(parents=True, exist_ok=True)
    java_item = ltv['runtimes']['build-linux-x86_64']
    download(java_item, cache)
    java = extract(java_item, cache, 'build-linux-x86_64')
    maven_root = WORK/'maven'
    maven_root.mkdir()
    maven = unpack(download(ltv['maven'], cache), maven_root)/'bin/mvn'
    TRANSFER.mkdir(parents=True)
    full_runtime = TRANSFER/'runtime'
    python('build_ltv.py', '--system', 'windows', '--architecture', 'arm64',
           '--java-home', java, '--maven', maven, '--base-runtime', runtime,
           '--output', full_runtime, '--tools-cache', cache)
    # Reuse the same OpenSSL headers, archives and C ABI throughout this build.
    python('prepare_cpdk.py', '--output', WORK/'cpdk')
    provider = WORK/'provider'
    configure('native/platform/windows/web', provider, toolchain,
              '-DCIE_CARDMOD_INCLUDE='+str(WORK/'cpdk/include'))
    pkcs = WORK/'pkcs11'
    configure('native/platform/windows/pkcs11', pkcs, toolchain,
              '-DCIE_OPENSSL_INCLUDE='+str(deps/'prefix/include'),
              '-DCIE_BACKEND_IMPORT='+str(WORK/'native-build/backend/libcie-pkcs11.dll.a'),
              '-DCIE_WEB_IMPORT='+str(WORK/'native-build/libcie_web.dll.a'),
              '-DCIE_BACKEND_RUNTIME='+str(full_runtime))
    web = TRANSFER/'web-component'
    python('package_web_windows.py', '--runtime', full_runtime,
           '--provider', provider/'cie_prototype_minidriver.dll',
           '--pkcs11', pkcs/'cie_pkcs11.dll', '--output', web)
    configure('native/platform/windows/web', provider, toolchain,
              '-DCIE_CARDMOD_INCLUDE='+str(WORK/'cpdk/include'),
              '-DCIE_WEB_SETUP_MANIFEST='+str(web/'setup_payload.h'))
    shutil.copy2(provider/'CIE-Web-Setup.exe', web/'CIE-Web-Setup.exe')
    # Regression binaries are CI-only; never merge these into the system payload.
    test_tools = TRANSFER/'test-tools'
    shutil.copytree(provider/'tests', test_tools/'provider-fixtures')
    for build, target in ((provider,test_tools/'web'), (pkcs,test_tools/'pkcs11')):
        target.mkdir(parents=True)
        for p in build.iterdir():
            if p.is_file() and p.suffix in ('.exe','.dll'):
                shutil.copy2(p,target/p.name)
    check_pe_tree(TRANSFER,'arm64')
    files = {p.relative_to(TRANSFER).as_posix():sha(p) for p in sorted(TRANSFER.rglob('*')) if p.is_file()}
    (TRANSFER/'transfer-manifest.json').write_text(json.dumps({'architecture':'arm64','files':files},indent=2)+'\n')


def windows():
    # Native Python is essential: ctypes cannot load ARM64 DLLs into x64 Python.
    if platform.system() != 'Windows' or pe_machine(Path(sys.executable)) != MACHINES['arm64']:
        raise ValueError('The app phase requires native ARM64 Windows and Python')
    receipt = json.loads((TRANSFER/'transfer-manifest.json').read_text())
    if receipt['architecture'] != 'arm64':
        raise ValueError('Wrong transfer architecture')
    for name,digest in receipt['files'].items():
        path = (TRANSFER/name).resolve()
        if not path.is_relative_to(TRANSFER.resolve()) or sha(path)!=digest:
            raise ValueError('Transfer checksum mismatch: '+name)
    check_pe_tree(TRANSFER,'arm64')
    runtime = ROOT/'native/runtime/windows'
    web = ROOT/'native/runtime/windows-web-component'
    shutil.copytree(TRANSFER/'runtime',runtime)
    shutil.copytree(TRANSFER/'web-component',web)
    ENV['PATH'] = str(runtime)+os.pathsep+ENV['PATH']
    REPORTS.mkdir(parents=True,exist_ok=True)
    python('smoke_native.py','--runtime',runtime,'--report',REPORTS/'native.json')
    python('test_ltv.py','--runtime',runtime,'--report',REPORTS/'ltv.json')
    test_tools = TRANSFER/'test-tools'
    for name in ('cie_web_package_status_tests','cie_web_catalog_tests','cie_web_setup_policy_tests'):
        run(test_tools/'web'/(name+'.exe'))
    run(test_tools/'web/cie_minidriver_tests.exe',test_tools/'provider-fixtures/provider/cie_prototype_minidriver.dll')
    run(test_tools/'pkcs11/cie_windows_pkcs11_tests.exe',test_tools/'pkcs11/cie_windows_pkcs11_fake.dll')
    run(web/'CIE-Web-Setup.exe','--validate-package')
    flutter = shutil.which('flutter.bat')
    if not flutter:
        raise ValueError('Pinned Flutter SDK missing from PATH')
    dart = Path(flutter).parent/'cache/dart-sdk/bin/dart.exe'
    run(flutter,'--suppress-analytics','pub','get','--enforce-lockfile')
    if pe_machine(dart) != MACHINES['arm64']:
        raise ValueError('Flutter selected an x64 Dart SDK; ARM64 fallback is forbidden')
    run(flutter,'--suppress-analytics','analyze','--no-pub')
    run(flutter,'--suppress-analytics','test','--no-pub')
    # Uses the native host architecture. Flutter 3.47.7 has no --target-platform
    # option for build windows; a native ARM64 Dart SDK selects windows-arm64.
    run(flutter,'--suppress-analytics','build','windows','--release','--no-pub')
    release = ROOT/'build/windows/arm64/runner/Release'
    check_release_architecture(release,'arm64')
    # The package's native-assets hook downloads PDFium; compare its bytes to
    # the independently checksum-locked publisher archive before packaging.
    preview = json.loads((ROOT/'native/preview/pdfium.lock.json').read_text())['artifacts']['windows-arm64']
    with tarfile.open(download(preview, WORK/'downloads')) as archive:
        member = next(m for m in archive.getmembers() if m.name.lstrip('./')=='bin/pdfium.dll')
        if hashlib.sha256(archive.extractfile(member).read()).hexdigest()!=sha(release/'pdfium.dll'):
            raise ValueError('Bundled PDFium does not match the locked ARM64 archive')
    # Compile the portable bridge and all its fake-backed tests with MSVC ARM64.
    bridge = WORK/'bridge-tests'
    configure('native', bridge, '-DCMAKE_CXX_COMPILER=cl', '-DCMAKE_C_COMPILER=cl')
    run('ctest','--test-dir',bridge,'--output-on-failure','--timeout','120')
    runner = WORK/'runner-tests'
    configure('windows/runner/tests',runner,'-DCMAKE_CXX_COMPILER=cl')
    run('ctest','--test-dir',runner,'--output-on-failure','--timeout','120')
    tool = json.loads((ROOT/'packaging/windows/arm64-toolchain.lock.json').read_text())['inno']
    installer = download(tool, WORK/'downloads')
    inno = WORK/'inno'
    run(installer,'/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/CURRENTUSER','/DIR='+str(inno))
    # This installs only the compiler on the disposable runner, never the app.
    vc = Path(os.environ['CIE_CI_VC_REDIST_ARM64'])
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+', (ROOT/'pubspec.yaml').read_text(),re.M).group(1)
    python('package_windows_installer.py','--release',release,'--output',ROOT/'dist/windows-arm64/Setup',
           '--iscc',inno/'ISCC.exe','--vc-redist',vc,'--version',version,'--architecture','arm64')
    # Same real Inno engine; synthetic payload and fake helper only. No UAC.
    python('test_windows_installer.py','--iscc',inno/'ISCC.exe',
           '--fake-helper',test_tools/'web/cie_installer_fake.exe','--architecture','arm64',
           '--output',REPORTS/'isolated-installer')
    (REPORTS/'result.json').write_text(json.dumps({'softwareChecksPassed':True,
        'architecture':'arm64','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'realCardOperations':0,'productionInstallations':0,'hardwareValidated':False},indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=['native','windows'])
    args = parser.parse_args()
    WORK.mkdir(parents=True,exist_ok=True)
    {'native':native,'windows':windows}[args.phase]()
