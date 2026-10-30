#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Windows GUI build from neutral source/SDK/cache trees, with MSVC path maps."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from build_privacy import check_public_paths, local_path_markers
from windows_architecture import check_release_architecture, pe_machine, MACHINES


def msvc_path_options(source, cache, sdk):
    # MSVC requires deterministic compilation before accepting /pathmap. GCC
    # prefix-map flags are intentionally not passed to the Microsoft compiler.
    maps = [(Path(source).resolve(), r'C:\src\firma-con-cie'),
            (Path(cache).resolve(), r'C:\deps\pub-cache'),
            (Path(sdk).resolve(), r'C:\tools\flutter')]
    return ['/experimental:deterministic', *[f'/pathmap:{old}={new}' for old, new in maps]]


def neutral_directory(path):
    path = Path(path).resolve(strict=True)
    if not path.is_dir() or local_path_markers(str(path).encode(), roots=[Path.home()]):
        raise ValueError('Build source, SDK and cache must be outside the personal profile')
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk', type=Path, required=True)
    parser.add_argument('--pub-cache', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='Analyze and run the isolated Flutter regression suite')
    parser.add_argument('--private-path-root', action='append', type=Path, default=[], help='Additional old profile root to reject')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('This recipe requires a native Windows host matching the target CPU')
    root = neutral_directory(Path(__file__).resolve().parents[1])
    sdk, cache = neutral_directory(args.flutter_sdk), neutral_directory(args.pub_cache)
    flutter = sdk / 'bin/flutter.bat'
    if not flutter.is_file():
        raise ValueError('Flutter SDK is incomplete')
    expected = json.loads((root / 'toolchain.lock.json').read_text())['flutter']['hash']
    actual = subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != expected:
        raise ValueError('Flutter SDK differs from the pinned source revision')
    env = os.environ.copy()
    env['PUB_CACHE'] = str(cache)
    env['CL'] = ' '.join(filter(None, [env.get('CL'), subprocess.list2cmdline(msvc_path_options(root, cache, sdk))]))
    # Record only the PDB filename in PE debug metadata. PDBs are not shipped.
    env['_LINK_'] = ' '.join(filter(None, [env.get('_LINK_'), '/PDBALTPATH:%_PDB%']))

    def run(*arguments):
        subprocess.run([str(flutter), '--suppress-analytics', *arguments], cwd=root, env=env, check=True)

    run('pub', 'get', '--enforce-lockfile')
    if args.check:
        run('analyze', '--no-pub')
        run('test', '--no-pub')
    run('build', 'windows', '--release', '--no-pub')
    machine = pe_machine(sdk / 'bin/cache/dart-sdk/bin/dart.exe')
    architecture = next((name for name, value in MACHINES.items() if value == machine), None)
    if architecture is None:
        raise ValueError('Unsupported Dart SDK architecture')
    release = root / ('build/windows/' + architecture + '/runner/Release')
    check_release_architecture(release, architecture)
    check_public_paths(release)
    if args.private_path_root:
        check_public_paths(release, roots=args.private_path_root)
    print('Windows build privacy check passed:', release)


if __name__ == '__main__':
    main()
