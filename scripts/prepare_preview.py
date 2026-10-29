#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify pinned PDFium preview artifacts and retain their license notices.

No native code is executed. Cached archives are immutable checksum inputs;
Flutter packages keep their normal pubspec.lock and generated NOTICES.Z.
"""
import argparse,hashlib,json,shutil,tarfile,urllib.request,zipfile
from pathlib import Path
from urllib.parse import urlparse,unquote
ROOT=Path(__file__).resolve().parents[1]
cache=ROOT/'.build/preview-downloads';cache.mkdir(parents=True,exist_ok=True)
lock=json.loads((ROOT/'native/preview/pdfium.lock.json').read_text())
notices=ROOT/'LICENSES/preview';notices.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--platform',action='append',choices=sorted(lock['artifacts']))
args=parser.parse_args()
inventory=json.loads((notices/'manifest.json').read_text()) if (notices/'manifest.json').exists() else {}
for platform,item in lock['artifacts'].items():
    if args.platform and platform not in args.platform:continue
    archive=cache/item['archive']
    if not archive.exists():
        with urllib.request.urlopen(item['url'],timeout=60) as source,archive.open('wb') as dest:shutil.copyfileobj(source,dest)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('PDFium archive checksum mismatch: '+platform)
    if archive.suffix=='.zip':
        source=zipfile.ZipFile(archive);members=[(n,lambda n=n:source.read(n)) for n in source.namelist() if not n.endswith('/')]
    else:
        source=tarfile.open(archive);members=[(m.name,lambda m=m:source.extractfile(m).read()) for m in source.getmembers() if m.isfile()]
    entry={'archiveSha256':item['sha256'],'notices':{},'libraries':{}}
    for name,read in members:
        path=Path(name)
        if any(p in ['..',''] for p in path.parts) or path.is_absolute():raise RuntimeError('Unsafe archive member')
        upper=name.upper()
        if any(n in upper for n in ['LICENSE','COPYING','NOTICE','AUTHORS']):
            content=read();target=notices/platform/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
            entry['notices'][name]=hashlib.sha256(content).hexdigest()
        if path.name in ['pdfium.dll','libpdfium.so','PDFium']:
            entry['libraries'][name]=hashlib.sha256(read()).hexdigest()
    source.close();inventory[platform]=entry
# Keep direct and transitive package notices; Flutter also emits its actual
# bundled package inventory. Do not replace any component's own license.
config=ROOT/'.dart_tool/package_config.json';packages={}
if config.exists() and not args.platform:
    for item in json.loads(config.read_text())['packages']:
        uri=item['rootUri'];folder=Path(urllib.request.url2pathname(urlparse(uri).path)) if uri.startswith('file:') else (config.parent/uri).resolve()
        if folder==ROOT:continue
        for name in ['LICENSE','LICENSE.txt','COPYING','NOTICE','NOTICE.txt']:
            p=folder/name
            if p.is_file():
                target=notices/'dart'/item['name']/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
                packages[item['name']+'/'+name]=hashlib.sha256(p.read_bytes()).hexdigest()
if not args.platform:inventory['dartNotices']=packages
(notices/'manifest.json').write_text(json.dumps(inventory,indent=2)+'\n')
print('Pinned preview artifacts verified:',', '.join(lock['artifacts']))
print('Native notice files:',sum(len(i['notices']) for p,i in inventory.items() if p!='dartNotices'),'Dart notices:',len(packages))
