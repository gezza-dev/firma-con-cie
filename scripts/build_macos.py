#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build and assemble a local prototype, separate from the CIE ID release."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
from pathlib import Path
from build_paths import build_root
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--flutter', default='flutter')
parser.add_argument('--identity', default='-', help='Optional Apple Development identity; default ad hoc')
parser.add_argument('--destination', type=Path,
    help='Override the local/default bundle destination')
parser.add_argument('--build-workspace', type=Path,
    help='Override the local/default non-cloud build workspace')
parser.add_argument('--runtime', type=Path, default=ROOT/'native/runtime/macos', help='Private runtime to embed, including the shared-source backend')
parser.add_argument('--skip-build', action='store_true', help='Reassemble the existing prototype build only')
parser.add_argument('--web-extension',type=Path,help='Optional separately built prototype CryptoTokenKit appex')
args = parser.parse_args()
if args.destination is None or args.build_workspace is None:
    local_root = build_root(ROOT)
    args.destination = args.destination or local_root / 'firma-con-cie'
    args.build_workspace = args.build_workspace or local_root / 'workspace-macos'
if args.web_extension:
    extension = args.web_extension.resolve()
    extension_info = plistlib.loads((extension/'Contents/Info.plist').read_bytes())
    executable_name = extension_info.get('CFBundleExecutable', '')
    if not executable_name or Path(executable_name).name != executable_name:
        raise SystemExit('Invalid CryptoTokenKit executable name')
    executable = extension/'Contents/MacOS'/executable_name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit('CryptoTokenKit executable is missing or not executable; preserve file permissions when copying the component')
runtime = args.runtime.resolve()
manifest = json.loads((runtime/'backend-manifest.json').read_text())
for name, digest in manifest['files'].items():
    if hashlib.sha256((runtime/name).read_bytes()).hexdigest() != digest:
        raise SystemExit('Runtime checksum mismatch: '+name)
workspace = args.build_workspace or args.destination.parent/'workspace'
workspace = workspace.resolve()
if workspace == ROOT or ROOT in workspace.parents:
    raise SystemExit('Build workspace must be outside the source directory')
if not args.skip_build:
    # Discard only generated files owned by this build workspace. Otherwise
    # Flutter may retain absolute paths to the source/iCloud checkout.
    for relative in ['.dart_tool', 'macos/Flutter/ephemeral']:
        generated = workspace/relative
        if generated.is_symlink(): generated.unlink()
        elif generated.exists(): shutil.rmtree(generated)
shutil.copytree(ROOT, workspace, dirs_exist_ok=True, copy_function=shutil.copyfile,
    ignore=shutil.ignore_patterns('build', '.dart_tool', '.git', 'dist', 'reports', 'output',
        'runtime', '.build', '__pycache__', '.idea', 'ephemeral', '.plugin_symlinks', 'Pods',
        'local-build.json', 'LOCAL_SETUP.md', 'local-backend.json'))
# Only generated/copy-owned build files are cleaned, never original sources or
# existing CIE ID bundles. File-provider FinderInfo prevents codesign in iCloud.
for key in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
    subprocess.run(['xattr', '-dr', key, str(workspace)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if not args.skip_build:
    subprocess.run([args.flutter, 'pub', 'get', '--enforce-lockfile'], cwd=workspace, check=True)
    subprocess.run([args.flutter, 'build', 'macos', '--release', '--no-pub'], cwd=workspace, check=True)
source = workspace/'build/macos/Build/Products/Release/Firma con CIE.app'
args.destination.mkdir(parents=True, exist_ok=True)
target = args.destination/'Firma con CIE.app'
if target.exists():
    # This script owns only its prototype bundle, never the existing CIE ID app.
    if target.is_symlink() or target.name != 'Firma con CIE.app':
        raise SystemExit('Unexpected destination')
    shutil.rmtree(target)
shutil.copytree(source, target, symlinks=True)
embedded = target/'Contents/Frameworks/CIEPrototype'
embedded.mkdir(parents=True)
for library in runtime.glob('*.dylib'):
    shutil.copyfile(library, embedded/library.name)
observer = runtime/'cie_card_observer'
if not observer.is_file(): raise SystemExit('Rebuild the runtime: missing private card observer')
shutil.copy2(observer, embedded/observer.name)
notices = target/'Contents/Resources/CIEPrototype'
shutil.copytree(runtime/'licenses', notices/'backend')
shutil.copytree(ROOT/'LICENSES', notices/'flutter-dependencies')
shutil.copyfile(ROOT/'LICENSE', notices/'prototype-LICENSE')
if (runtime/'ltv').exists():
    shutil.copytree(runtime/'ltv', notices/'ltv')
shutil.copyfile(runtime/'backend-manifest.json', notices/'source-runtime-manifest.json')
for key in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
    subprocess.run(['xattr', '-dr', key, str(target)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for library in embedded.glob('*.dylib'):
    subprocess.run(['codesign', '--force', '--sign', args.identity, str(library)], check=True)
subprocess.run(['codesign', '--force', '--sign', args.identity, str(embedded/observer.name)], check=True)
# JVM launchers and native libraries stay private in Resources. Sign each
# Mach-O for its own architecture; Dart chooses the matching JVM at runtime.
if (notices/'ltv').exists():
    mach_o_magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    for binary in sorted((notices/'ltv').rglob('*')):
        if binary.is_file():
            with binary.open('rb') as handle: magic=handle.read(4)
            if magic in mach_o_magic:
                subprocess.run(['codesign','--force','--sign',args.identity,str(binary)],check=True)
    ltv_hashes={str(p.relative_to(notices/'ltv')):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((notices/'ltv').rglob('*')) if p.is_file()}
    (notices/'ltv-signed-manifest.json').write_text(json.dumps(ltv_hashes,indent=2)+'\n')
# Signing changes Mach-O bytes. Record the hashes of the libraries actually
# embedded, retaining the original build manifest separately for provenance.
bundled_manifest = dict(manifest)
bundled_manifest['runtime_layout'] = 'signed-macos-app'
bundled_manifest['runtime_path_from_bundle'] = 'Contents/Frameworks/CIEPrototype'
bundled_manifest['source_runtime_manifest_sha256'] = hashlib.sha256(
    (runtime/'backend-manifest.json').read_bytes()).hexdigest()
bundled_manifest['files'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted(embedded.iterdir()) if p.is_file()}
manifest_text = json.dumps(bundled_manifest, indent=2)+'\n'
(notices/'backend-manifest.json').write_text(manifest_text)
for framework in (target/'Contents/Frameworks').glob('*.framework'):
    subprocess.run(['codesign', '--force', '--sign', args.identity, str(framework)], check=True)
if args.web_extension:
    extension=args.web_extension.resolve()
    if extension.name!='CIEPrototypeToken.appex':raise SystemExit('Unexpected CryptoTokenKit bundle')
    subprocess.run(['codesign','--verify','--deep','--strict',str(extension)],check=True)
    plugins=target/'Contents/PlugIns';plugins.mkdir(exist_ok=True)
    shutil.copytree(extension,plugins/extension.name)
host_entitlements=ROOT/'macos/Runner/Release.entitlements'
if args.web_extension:
    group=plistlib.loads((extension/'Contents/Info.plist').read_bytes()).get('CIEWebPublicAppGroup','')
    if not re.fullmatch(r'[A-Z0-9]{10}\.it\.giancarloezza\.CIEID\.FlutterPrototype\.web-public',group):raise SystemExit('Invalid public certificate App Group')
    entitlements=plistlib.loads(host_entitlements.read_bytes())
    entitlements['com.apple.security.application-groups']=[group]
    host_entitlements=args.destination/'WebHost.entitlements'
    host_entitlements.write_bytes(plistlib.dumps(entitlements))
subprocess.run(['codesign', '--force', '--sign', args.identity, '--entitlements',
    str(host_entitlements), str(target)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)
print('Local prototype (not notarized):', target)
