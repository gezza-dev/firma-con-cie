#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Shared, checksum-locked tools for disposable desktop CI runners."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

from build_ltv import extract
from build_portable_dependencies import unpack
from ci_windows_arm64 import download
from product_identity import application_version

ROOT = Path(__file__).resolve().parents[1]


def run(*args, env=None):
    # Never use this logging wrapper for credentials or keychain passwords.
    print('+ ' + ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, env=env, check=True)


def python(script, *args):
    run(sys.executable, ROOT/'scripts'/script, *args)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def java_tools(system, architecture, work):
    lock = json.loads((ROOT/'native/ltv/toolchain.lock.json').read_text())
    key = 'build-' + system + '-' + architecture
    item = lock['runtimes'][key]
    cache = work/'downloads'
    download(item, cache)
    # extract() resolves Contents/Home for names starting with macos.
    name = 'macos-build-' + architecture if system == 'macos' else key
    java = extract(item, cache, name)
    directory = work/'maven'
    directory.mkdir(parents=True)
    maven = unpack(download(lock['maven'], cache), directory)/'bin/mvn'
    return java, maven, cache


def flutter_checks():
    run('flutter', '--suppress-analytics', 'pub', 'get', '--enforce-lockfile')
    run('flutter', '--suppress-analytics', 'analyze', '--no-pub')
    run('flutter', '--suppress-analytics', 'test', '--no-pub')


def host_architecture():
    value = platform.machine().lower()
    if value in ('arm64', 'aarch64'):
        return 'arm64'
    if value in ('x86_64', 'amd64'):
        return 'x64'
    raise ValueError('Unsupported CI architecture')


def source_commit():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def receipt(path, system, architecture, artifacts, **extra):
    result = dict(version=application_version(), sourceCommit=source_commit(),
                  system=system, architecture=architecture,
                  artifacts={p.relative_to(ROOT).as_posix():sha(p) for p in artifacts},
                  realCardOperations=0, hardwareValidated=False, releasePublished=False,
                  **extra)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2)+'\n')
    return result


def install_flutter(destination):
    lock = json.loads((ROOT/'toolchain.lock.json').read_text())['flutter']
    if destination.exists():
        raise ValueError('Use a fresh Flutter SDK directory')
    run('git', 'clone', '--depth', '1', '--branch', lock['version'],
        'https://github.com/flutter/flutter.git', destination)
    actual = subprocess.check_output(['git', '-C', destination, 'rev-parse', 'HEAD'], text=True).strip()
    if actual != lock['hash']:
        raise ValueError('Flutter revision differs from toolchain.lock.json')
    with Path(os.environ['GITHUB_PATH']).open('a') as output:
        output.write(str(destination/'bin')+'\n')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-flutter', type=Path, required=True)
    install_flutter(parser.parse_args().install_flutter)
