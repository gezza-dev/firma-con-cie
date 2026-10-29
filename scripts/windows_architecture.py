#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Inspect Windows binary architecture without loading or executing any code."""
import json
from pathlib import Path
import struct

MACHINES = {'x64': 0x8664, 'arm64': 0xAA64}


def pe_machine(path):
    with Path(path).open('rb') as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise ValueError('Invalid PE header: ' + str(path))
        offset = struct.unpack_from('<I', header, 60)[0]
        if offset < 64 or offset > Path(path).stat().st_size - 24:
            raise ValueError('Invalid PE offset: ' + str(path))
        stream.seek(offset)
        signature = stream.read(6)
        if signature[:4] != b'PE\0\0':
            raise ValueError('Invalid PE signature: ' + str(path))
        return struct.unpack_from('<H', signature, 4)[0]


def check_pe_tree(root, architecture):
    """Reject mixed architectures, including the Flutter AOT library and JVM."""
    expected = MACHINES[architecture]
    found = {}
    for path in sorted(Path(root).rglob('*')):
        if path.is_file() and (path.suffix.lower() in ('.dll', '.exe') or path.name == 'app.so'):
            machine = pe_machine(path)
            if machine != expected:
                raise ValueError(f'Expected {architecture} PE, found 0x{machine:04x}: {path}')
            found[path.relative_to(root).as_posix()] = machine
    if not found:
        raise ValueError('No Windows binaries found: ' + str(root))
    return found


def check_release_architecture(release, architecture):
    binaries = check_pe_tree(release, architecture)
    manifest = json.loads((release/'cie_native/backend-manifest.json').read_text(encoding='utf-8'))
    native_arch = 'arm64' if architecture == 'arm64' else 'x86_64'
    if manifest.get('system') != 'windows' or manifest.get('architectures') != [native_arch]:
        raise ValueError('Native Windows architecture manifest mismatch')
    if manifest.get('ltv', {}).get('architectures') != ['windows-' + native_arch]:
        raise ValueError('Private DSS JVM architecture mismatch')
    if not (release/'cie_native/ltv/jre'/('windows-'+native_arch)/'bin/java.exe').is_file():
        raise ValueError('Missing private Windows JVM')
    return binaries
