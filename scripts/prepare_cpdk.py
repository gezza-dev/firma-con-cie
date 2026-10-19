#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Extract the pinned Microsoft CPDK header for cross compilation on Linux.

Requires 7z and msiextract (p7zip-full, msitools). No installer is executed.
The SDK stays in .build; it is not redistributed in source/test packages.
"""
import argparse,hashlib,json,subprocess,urllib.parse,urllib.request,xml.etree.ElementTree as ET
from pathlib import Path
BASE='https://download.microsoft.com/download/1/7/6/176909b0-50f2-4df3-b29b-830a17ea7e38/CPDK_RELEASE_UPDATE/'
BOOTSTRAP='76d6f7580fce9bb1045b5f0871718342443ec5d99c316489ef8c7bc83d4dd6ed'
HEADER='a6222ef5ac63d0db989a85810d5b73d96990122db371c9f0cc50a36d4dcdb598'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=Path('.build/cpdk'))
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
bootstrap=out/'cpdksetup.exe'
if not bootstrap.exists():bootstrap.write_bytes(urllib.request.urlopen(BASE+'cpdksetup.exe').read())
if hashlib.sha256(bootstrap.read_bytes()).hexdigest()!=BOOTSTRAP:raise SystemExit('CPDK bootstrap checksum mismatch')
setup=out/'setup';subprocess.run(['7z','x',str(bootstrap),'-o'+str(setup),'-y'],check=True,stdout=subprocess.DEVNULL)
manifest=ET.fromstring((setup/'0').read_text(encoding='utf-8-sig'));payload=out/'payload';payload.mkdir(exist_ok=True)
files={}
for node in manifest:
 name=node.get('FilePath','')
 if not node.tag.endswith('Payload') or not (name.endswith('.cab') or 'Windows Cryptographic Provider Development Kit' in name):continue
 path=name.replace('\\','/');target=payload/Path(path).name
 if not target.exists():target.write_bytes(urllib.request.urlopen(BASE+urllib.parse.quote(path)).read())
 data=target.read_bytes()
 if hashlib.sha1(data).hexdigest().upper()!=node.get('Hash'):raise SystemExit('CPDK payload checksum mismatch')
 files[target.name]=hashlib.sha256(data).hexdigest()
extracted=out/'extracted';extracted.mkdir(exist_ok=True)
subprocess.run(['msiextract','-C',str(extracted),str(payload/'Windows Cryptographic Provider Development Kit-x86_en-us.msi')],check=True,stdout=subprocess.DEVNULL)
header=extracted/'Program Files/Windows Kits/10/Cryptographic Provider Development Kit/Include/cardmod.h'
data=header.read_bytes()
if hashlib.sha256(data).hexdigest()!=HEADER:raise SystemExit('CPDK header checksum mismatch')
include=out/'include';include.mkdir(exist_ok=True);(include/'cardmod.h').write_bytes(data)
(out/'provenance.json').write_text(json.dumps(dict(source=BASE+'cpdksetup.exe',bootstrap_sha256=BOOTSTRAP,header_sha256=HEADER,payload_sha256=files,installed=False),indent=2)+'\n')
print(include)
