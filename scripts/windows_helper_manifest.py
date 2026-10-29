#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the embedded UAC manifest without loading/executing the Windows helper.

Works on Linux and Windows, for both x64 and ARM64 PE32+ binaries. Checking the
actual RT_MANIFEST resource also catches a missing resource-compiler build step.
"""
from pathlib import Path
import struct
import xml.etree.ElementTree as ET


def embedded_manifests(path):
    data = Path(path).read_bytes()

    def take(offset, count):
        if offset < 0 or count < 0 or offset + count > len(data):
            raise ValueError('Truncated PE resource')
        return data[offset:offset + count]

    def number(offset, fmt='<I'):
        return struct.unpack(fmt, take(offset, struct.calcsize(fmt)))[0]

    if take(0, 2) != b'MZ':
        raise ValueError('Invalid helper DOS header')
    pe = number(60)
    if take(pe, 4) != b'PE\0\0' or number(pe + 4, '<H') not in (0x8664, 0xAA64):
        raise ValueError('Expected x64 or ARM64 helper PE')
    sections, optional_size = number(pe + 6, '<H'), number(pe + 20, '<H')
    optional = pe + 24
    if (number(optional, '<H') != 0x20b or optional_size < 136
            or number(optional + 108) < 3 or not 0 < sections <= 96):
        raise ValueError('Invalid helper PE32+ directory table')
    resource_rva, resource_size = struct.unpack('<II', take(optional + 128, 8))
    if not resource_rva or resource_size < 16:
        raise ValueError('Missing embedded helper manifest')
    table = optional + optional_size

    def rva_offset(rva, count):
        for index in range(sections):
            entry = table + 40 * index
            virtual = number(entry + 12)
            size, raw = number(entry + 16), number(entry + 20)
            delta = rva - virtual
            if 0 <= delta and delta + count <= size:
                take(raw + delta, count)
                return raw + delta
        raise ValueError('Unmapped PE resource RVA')

    base = rva_offset(resource_rva, resource_size)

    def relative(offset, count):
        if offset < 0 or offset + count > resource_size:
            raise ValueError('Invalid PE resource directory offset')
        return base + offset

    def entries(offset):
        directory = relative(offset, 16)
        count = number(directory + 12, '<H') + number(directory + 14, '<H')
        if count > 256:
            raise ValueError('Oversized PE resource directory')
        start = relative(offset + 16, count * 8)
        return [struct.unpack('<II', take(start + i * 8, 8)) for i in range(count)]

    def child(offset, identifier):
        values = [target for name, target in entries(offset) if name == identifier]
        if len(values) != 1 or not values[0] & 0x80000000:
            raise ValueError('Missing embedded helper manifest resource #1')
        return values[0] & 0x7fffffff

    # RT_MANIFEST=24, CREATEPROCESS_MANIFEST_RESOURCE_ID=1, then languages.
    languages = entries(child(child(0, 24), 1))
    if not languages:
        raise ValueError('Missing embedded helper manifest language')
    manifests = []
    for language, target in languages:
        if language & 0x80000000 or target & 0x80000000:
            raise ValueError('Invalid helper manifest language')
        entry = relative(target, 16)
        rva, size = struct.unpack('<II', take(entry, 8))
        if not 0 < size <= 65536:
            raise ValueError('Invalid helper manifest size')
        manifests.append(take(rva_offset(rva, size), size))
    return manifests


def check_helper_manifest(path):
    manifests = embedded_manifests(path)
    for manifest in manifests:
        try:
            root = ET.fromstring(manifest)
        except ET.ParseError as error:
            raise ValueError('Invalid helper manifest XML') from error
        if (root.tag != '{urn:schemas-microsoft-com:asm.v1}assembly'
                or root.get('manifestVersion') != '1.0'):
            raise ValueError('Invalid helper manifest assembly')
        ns = '{urn:schemas-microsoft-com:asm.v3}'
        levels = root.findall('/'.join(ns + part for part in
                              ('trustInfo', 'security', 'requestedPrivileges', 'requestedExecutionLevel')))
        if (len(levels) != 1 or len(root.findall('.//' + ns + 'requestedExecutionLevel')) != 1
                or levels[0].get('level') != 'asInvoker'
                or levels[0].get('uiAccess') != 'false'):
            raise ValueError('Helper must embed asInvoker with uiAccess=false')
    return {'executionLevel': 'asInvoker', 'uiAccess': False, 'languages': len(manifests)}
