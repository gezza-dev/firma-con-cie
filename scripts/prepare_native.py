#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build the bridge and copy (never modify) an existing macOS CIE backend."""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True, help='v1.5.2 middleware checkout')
parser.add_argument('--middleware', type=Path, required=True, help='Original Universal libcie-pkcs11.dylib')
parser.add_argument('--dependency-include', type=Path, required=True)
parser.add_argument('--architectures', default='arm64;x86_64')
args = parser.parse_args()
if platform.system() != 'Darwin':
    parser.error('This preparation script currently supports the pinned macOS backend only')
source = args.source.resolve()
middleware = args.middleware.resolve()
runtime = ROOT / 'native/runtime/macos'
runtime.mkdir(parents=True, exist_ok=True)
build = ROOT / 'build/native'
def run(*command):
    subprocess.run(list(map(str, command)), cwd=ROOT, check=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
original_hash = sha(middleware)
lock = json.loads((ROOT/'toolchain.lock.json').read_text())['backend']
if original_hash != lock['macos_middleware_sha256']:
    raise SystemExit('Backend hash differs from the pinned release. Review compatibility and update the lock explicitly.')
reference = subprocess.check_output(['git', '-C', str(source), 'rev-parse', lock['ref']+'^{commit}'], text=True).strip()
if reference != lock['commit']:
    raise SystemExit('Backend source reference differs from the pinned commit')
subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', reference, '--',
    'cie-pkcs11', 'cie_sign_sdk', 'native'], check=True, stdout=subprocess.DEVNULL)
run('cmake', '-S', ROOT/'native', '-B', build, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Debug',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0', '-DCMAKE_OSX_ARCHITECTURES='+args.architectures,
    '-DCIE_MIDDLEWARE_SOURCE='+str(source), '-DCIE_MIDDLEWARE_LIBRARY='+str(middleware),
    '-DCIE_DEPENDENCY_INCLUDE='+str(args.dependency_include.resolve()))
run('cmake', '--build', build)
for name in ['libcie_bridge.dylib', 'libcie_card_adapter.dylib', 'cie_card_observer']:
    shutil.copy2(build/name, runtime/name)
shutil.copy2(middleware, runtime/middleware.name)
# Preserve all backend license notices in the local distributable runtime.
licenses = runtime/'licenses'
licenses.mkdir(exist_ok=True)
for name in ['LICENSE.txt', 'THIRD_PARTY_NOTICES.md', 'LICENSE_AUDIT.md']:
    shutil.copy2(source/name, licenses/name)
shutil.copytree(source/'LICENSES', licenses/'LICENSES', dirs_exist_ok=True)
revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
manifest = dict(backend_release='v1.5.2', header_checkout=revision,
    original_middleware_sha256=original_hash, architectures=args.architectures.split(';'),
    bridge_abi=1, full_pin_signing=True, enrollment=False, enrollment_cache_access=False,
    card_observation_process=True, card_observation_protocol=1,
    files={p.name:sha(p) for p in sorted(runtime.iterdir())
           if p.is_file() and (p.suffix == '.dylib' or p.name == 'cie_card_observer')})
(runtime/'backend-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
assert sha(middleware) == original_hash, 'Original middleware unexpectedly changed'
print('Runtime prepared:', runtime)
