#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Export the checked Git index as a reviewable source-only ZIP; never pushes."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from check_repository import check, indexed_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sources, modes = indexed_sources()
    report = check(sources)
    if not report['passed']:
        print(json.dumps(report, indent=2))
        raise SystemExit(1)
    if args.output.exists():
        raise SystemExit('Choose a new output file: existing packages are preserved')
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(sources.items())}
    sources['SOURCE-SHA256.json'] = (json.dumps(hashes, indent=2) + '\n').encode()
    sources['SOURCE-CHECK.json'] = (json.dumps(report, indent=2) + '\n').encode()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, data in sorted(sources.items()):
            item = zipfile.ZipInfo('cie-id-desktop/' + name, date_time=(2026, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = modes.get(name, 0o100644) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, data)
    print(json.dumps({'output': str(args.output.resolve()), 'sourceFiles': len(hashes),
                      'bytes': args.output.stat().st_size,
                      'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest()}, indent=2))


if __name__ == '__main__':
    main()
