#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Assemble corresponding CI sources from checked-in SHA-256 locks."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

from prepare_release_sources import member_name, write_archive


def source_inputs(root):
    common = json.loads((root/'packaging/release/dependency-sources.lock.json').read_text())
    native = json.loads((root/common['nativeLock']).read_text())
    toolchains = json.loads((root/'packaging/release/windows-runtime-sources.lock.json').read_text())
    linux = json.loads((root/'packaging/release/linux-system-sources.lock.json').read_text())
    records = {}
    for item in native.values():
        records['native/' + member_name(item['archive'])] = item
    records['openjdk/' + member_name(common['openjdk']['archive'])] = common['openjdk']
    for name,item in common['javaSources'].items():
        records['java/' + member_name(name)] = item
    for package in toolchains['ubuntuSourcePackages'].values():
        for name,item in package['files'].items():
            key = 'windows-toolchain/' + member_name(name)
            if key in records and records[key]['sha256'] != item['sha256']:
                raise ValueError('Conflicting source file locks')
            records[key] = item
    supplemental = {}
    for key,package in linux['ubuntuSourcePackages'].items():
        name = key.rsplit('@', 1)[0]
        folder = member_name(name + '_' + package['version'].replace(':', '_epoch_'))
        for filename,item in package['files'].items():
            supplemental['linux-system/' + folder + '/' + member_name(filename)] = item
    return records, supplemental


def fetch(item, destination):
    if not item['url'].startswith(('https://', 'http://')):
        raise ValueError('Invalid locked source URL')
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            digest = hashlib.sha256()
            size = 0
            with urllib.request.urlopen(item['url'], timeout=60) as source, destination.open('wb') as output:
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    size += len(block)
                    if size > 1024**3:
                        raise ValueError('Unexpected source archive size')
                    digest.update(block)
                    output.write(block)
            if digest.hexdigest() != item['sha256'] or ('bytes' in item and size != item['bytes']):
                raise ValueError('Locked corresponding source checksum/size mismatch')
            return destination, item['url']
        except (OSError, TimeoutError):
            destination.unlink(missing_ok=True)
            if attempt == 3:
                raise
            time.sleep(2**attempt)


def prepare(root, output, version):
    project = output/f'firma-con-cie_{version}_sources.zip'
    subprocess.run([sys.executable, str(root/'scripts/prepare_repository.py'), '--output', str(project)],
                   cwd=root, check=True)
    groups = source_inputs(root)
    documents = {name:(root/name).read_bytes() for name in (
        'packaging/release/dependency-sources.lock.json',
        'packaging/release/windows-runtime-sources.lock.json',
        'packaging/release/linux-system-sources.lock.json',
        'native/backend/scripts/dependencies.lock.json', 'docs/BUILDING.md',
        'docs/LICENSING.md', 'docs/RELEASE.md')}
    documents['README.txt'] = (
        f'Firma con CIE {version} - corresponding dependency sources\n\n'
        'Use with the project source archive from this release. Original source\n'
        'archives are verified against the included SHA-256 locks; preserve\n'
        'upstream notices. Follow docs/BUILDING.md to rebuild and relink.\n'
        'Common archive: native/, java/, openjdk/, windows-toolchain/.\n'
        'Linux supplement: linux-system/ contains Ubuntu originals, .dsc and\n'
        'patches for the versions locked for AppImage payloads on both CPUs.\n'
        'Compare package manifests with these locks before publishing.\n'
        'No signing keys or personal build settings are required to rebuild.\n').encode()
    paths = [project]
    for items,suffix in zip(groups, ('dependency-sources', 'linux-system-sources')):
        names = sorted(items)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda name:fetch(items[name], output/'inputs'/name), names))
        archive = output/f'firma-con-cie_{version}_{suffix}.zip'
        write_archive(archive, dict(zip(names, results)), documents)
        paths.append(archive)
    return paths
