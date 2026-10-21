#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the optional Windows PKCS#11 module in a VS x64 developer shell.

Uses only the unchanged backend's exported OpenSSL C ABI and the existing Web
core. No C++ objects cross DLL boundaries; each crypto object is freed by the
same backend that allocated it. Does not install, register or access a card.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--openssl-include', type=Path, required=True)
    p.add_argument('--build-dir', type=Path, required=True)
    a = p.parse_args()
    runtime, build = a.runtime.resolve(), a.build_dir.resolve()
    manifest = json.loads((runtime/'backend-manifest.json').read_text(encoding='utf-8'))
    for name, digest in manifest['files'].items():
        if hashlib.sha256((runtime/name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Runtime checksum mismatch: '+name)
    expected = json.loads((ROOT/'native/backend/scripts/dependencies.lock.json').read_text(encoding='utf-8'))['openssl']['version']
    if ('OpenSSL '+expected+' ') not in (a.openssl_include/'openssl/opensslv.h').read_text(encoding='utf-8'):
        raise SystemExit('OpenSSL header version does not match the locked backend')
    build.mkdir(parents=True, exist_ok=True)
    dumpbin, librarian = shutil.which('dumpbin.exe'), shutil.which('lib.exe')
    if not dumpbin or not librarian:
        raise SystemExit('Use the Visual Studio x64 developer environment')
    for name in ('cie-pkcs11', 'cie_web'):
        text = subprocess.check_output([dumpbin, '/nologo', '/exports', str(runtime/(name+'.dll'))], text=True)
        symbols = re.findall(r'^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+([A-Za-z_][A-Za-z_0-9]*)\s*$', text, re.M)
        if not symbols: raise SystemExit('No C exports found: '+name)
        definition = build/(name+'.def')
        definition.write_text('LIBRARY '+name+'.dll\nEXPORTS\n'+'\n'.join(symbols)+'\n', encoding='utf-8')
        subprocess.run([librarian, '/nologo', '/machine:x64', '/def:'+str(definition), '/out:'+str(build/(name+'.lib'))], check=True)
    subprocess.run(['cmake','-S',str(ROOT/'native/platform/windows/pkcs11'),'-B',str(build),'-G','Ninja',
        '-DCMAKE_BUILD_TYPE=Release','-DCMAKE_CXX_COMPILER=cl',
        '-DCIE_OPENSSL_INCLUDE='+str(a.openssl_include.resolve()),
        '-DCIE_BACKEND_IMPORT='+str(build/'cie-pkcs11.lib'),
        '-DCIE_WEB_IMPORT='+str(build/'cie_web.lib'),
        '-DCIE_BACKEND_RUNTIME='+str(runtime)], check=True)
    subprocess.run(['cmake','--build',str(build),'--parallel','4'], check=True)
    subprocess.run(['ctest','--test-dir',str(build),'--output-on-failure'], check=True)

if __name__ == '__main__': main()
