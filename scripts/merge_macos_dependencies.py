#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Combine matching ARM64/Intel static prefixes without changing either input."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--arm64', type=Path, required=True)
p.add_argument('--x86-64', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
arm, intel, output = a.arm64.resolve(), a.x86_64.resolve(), a.output.resolve()
if output.exists(): raise SystemExit('Output must be a new directory')
def headers(prefix):
    return {str(f.relative_to(prefix/'include')):hashlib.sha256(f.read_bytes()).hexdigest()
        for f in (prefix/'include').rglob('*') if f.is_file() and f.name != '.DS_Store'}
if headers(arm) != headers(intel): raise SystemExit('Headers differ: review platform-dependent configuration before merging')
archives = sorted(f.name for f in (arm/'lib').glob('*.a'))
if archives != sorted(f.name for f in (intel/'lib').glob('*.a')):
    raise SystemExit('Static archive inventories differ')
for name in archives:
    for prefix,arch in [(arm,'arm64'),(intel,'x86_64')]:
        if subprocess.check_output(['lipo','-archs',prefix/'lib'/name],text=True).split() != [arch]:
            raise SystemExit('Unexpected archive architecture: '+name)
output.mkdir(parents=True)
shutil.copytree(arm/'include',output/'include',ignore=shutil.ignore_patterns('.DS_Store'))
(output/'lib').mkdir()
for name in archives:
    subprocess.run(['lipo','-create',arm/'lib'/name,intel/'lib'/name,'-output',output/'lib'/name],check=True)
manifest = json.loads((arm/'cie-dependencies.json').read_text())
manifest.pop('arch',None)
manifest['architectures'] = ['arm64','x86_64']
manifest['archives'] = {name:hashlib.sha256((output/'lib'/name).read_bytes()).hexdigest() for name in archives}
(output/'cie-dependencies.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Verified Universal dependency prefix:',output)
