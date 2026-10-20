#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Read-only ELF ABI gate for the Firefox core24 provider dependency closure."""
import argparse
import json
from pathlib import Path
import re
import subprocess

LIMITS = {'GLIBC': (2, 39), 'GLIBCXX': (3, 4, 33), 'CXXABI': (1, 3, 15)}
LIBRARIES = ('libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so')


def check(paths):
    result = []
    for path in paths:
        versions = subprocess.check_output(['readelf', '--version-info', str(path)], text=True)
        required = sorted(set(re.findall(r'Name: ((?:GLIBCXX|GLIBC|CXXABI)_[0-9.]+)', versions)))
        for item in required:
            family, version = item.split('_', 1)
            if tuple(map(int, version.split('.'))) > LIMITS[family]:
                raise ValueError(f'{path.name} requires {item}; rebuild with a core24/Ubuntu 24.04 compatible toolchain and dependencies')
        dynamic = subprocess.check_output(['readelf', '-d', str(path)], text=True)
        needed = re.findall(r'\(NEEDED\).*\[([^]]+)\]', dynamic)
        allowed = {*LIBRARIES, 'libpcsclite.so.1', 'libstdc++.so.6', 'libgcc_s.so.1',
                   'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1',
                   'ld-linux-x86-64.so.2', 'ld-linux-aarch64.so.1'}
        if set(needed) - allowed:
            raise ValueError(f'{path.name}: unaudited dynamic dependencies: {set(needed) - allowed}')
        rpaths = re.findall(r'\((?:RUNPATH|RPATH)\).*\[([^]]*)\]', dynamic)
        if any(part and part not in ('$ORIGIN', '$ORIGIN/backend')
               for value in rpaths for part in value.split(':')):
            raise ValueError(f'{path.name}: nonportable RPATH')
        result.append(dict(file=path.name, required=required, needed=needed, rpaths=rpaths))
    if {path.name for path in paths} != set(LIBRARIES):
        raise ValueError('Check all three provider libraries together')
    return dict(passed=True, target='Firefox Snap core24',
                maximumVersions={key: '.'.join(map(str, value)) for key, value in LIMITS.items()},
                libraries=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('libraries', nargs=3, type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = check(args.libraries)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
