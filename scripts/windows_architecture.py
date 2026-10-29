#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Inspect Windows binary architecture without loading or executing any code."""
import json
from pathlib import Path
import struct

MACHINES = {'x64': 0x8664, 'arm64': 0xAA64}
ELF_MACHINES = {'x64': 62, 'arm64': 183}


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


def elf_machine(path):
    """Inspect the ELF64 snapshot used by Dart's AOT loader on Windows too."""
    path = Path(path)
    with path.open('rb') as stream:
        header = stream.read(64)
    if len(header) != 64 or header[:7] != b'\x7fELF\x02\x01\x01':
        raise ValueError('Invalid ELF64 little-endian header: ' + str(path))
    kind, machine, version = struct.unpack_from('<HHI', header, 16)
    if kind != 3 or version != 1 or struct.unpack_from('<H',header,52)[0] != 64:
        raise ValueError('Invalid ELF64 shared-object header: ' + str(path))
    size = path.stat().st_size
    # Check that both tables fit within the snapshot. Read metadata only;
    # never load the ELF or treat a malformed/truncated file as a valid CPU.
    for offset_field, size_field, count_field, entry_size in ((32,54,56,56),(40,58,60,64)):
        offset = struct.unpack_from('<Q',header,offset_field)[0]
        stride = struct.unpack_from('<H',header,size_field)[0]
        count = struct.unpack_from('<H',header,count_field)[0]
        if offset < 64 or stride != entry_size or count == 0 or offset + stride*count > size:
            raise ValueError('Invalid ELF64 header table: ' + str(path))
    return machine


def check_pe_tree(root, architecture):
    """Reject mixed architectures in Windows EXE/DLL files, including the JVM."""
    expected = MACHINES[architecture]
    found = {}
    for path in sorted(Path(root).rglob('*')):
        if path.is_file() and path.suffix.lower() in ('.dll', '.exe'):
            machine = pe_machine(path)
            if machine != expected:
                raise ValueError(f'Expected {architecture} PE, found 0x{machine:04x}: {path}')
            found[path.relative_to(root).as_posix()] = machine
    if not found:
        raise ValueError('No Windows binaries found: ' + str(root))
    return found


def check_release_architecture(release, architecture):
    release = Path(release)
    binaries = check_pe_tree(release, architecture)
    snapshot = release/'data/app.so'
    machine = elf_machine(snapshot)
    if machine != ELF_MACHINES[architecture]:
        raise ValueError(f'Expected {architecture} ELF AOT, found {machine}: {snapshot}')
    binaries['data/app.so'] = machine
    manifest = json.loads((release/'cie_native/backend-manifest.json').read_text(encoding='utf-8'))
    native_arch = 'arm64' if architecture == 'arm64' else 'x86_64'
    if manifest.get('system') != 'windows' or manifest.get('architectures') != [native_arch]:
        raise ValueError('Native Windows architecture manifest mismatch')
    if manifest.get('ltv', {}).get('architectures') != ['windows-' + native_arch]:
        raise ValueError('Private DSS JVM architecture mismatch')
    if not (release/'cie_native/ltv/jre'/('windows-'+native_arch)/'bin/java.exe').is_file():
        raise ValueError('Missing private Windows JVM')
    return binaries
