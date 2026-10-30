#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Package locked Ubuntu corresponding sources for the Linux AppImages."""
import argparse
import json
from pathlib import Path

from prepare_release_sources import checked_file, member_name, write_archive

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock_path = ROOT/'packaging/release/linux-system-sources.lock.json'
    lock = json.loads(lock_path.read_text())
    inventory = checked_file(args.inventory, lock['inventorySha256'])
    mapping = json.loads(inventory.read_text())
    expected = {p['sourcePackage']+'@'+p['sourceVersion']
                for architecture in mapping['architectures'].values()
                for p in architecture['binaryPackages']}
    if expected != set(lock['ubuntuSourcePackages']):
        raise ValueError('Source package lock differs from bundled inventory')
    records = {}
    for key, package in sorted(lock['ubuntuSourcePackages'].items()):
        name = key.rsplit('@', 1)[0]
        folder = member_name(name+'_'+package['version'].replace(':', '_epoch_'))
        for filename, value in sorted(package['files'].items()):
            filename = member_name(filename)
            path = checked_file(args.cache/folder/filename, value['sha256'])
            if path.stat().st_size != value['bytes']:
                raise ValueError('Source archive size mismatch: '+filename)
            records['linux-system/'+folder+'/'+filename] = (path, value['url'])
    documents = {
        'linux-bundled-system-sources.json': inventory.read_bytes(),
        'packaging/release/linux-system-sources.lock.json': lock_path.read_bytes(),
        'docs/BUILDING.md': (ROOT/'docs/BUILDING.md').read_bytes(),
        'README.txt': (
            'Firma con CIE - supplemento sorgenti Linux\n\n'
            'Usare insieme ai sorgenti del progetto, alle dipendenze comuni e a\n'
            'linux-build-materials.zip della stessa release. linux-system/ contiene\n'
            'i file sorgente originali Ubuntu, descriptor e patch delle versioni\n'
            'esatte associate alle librerie AppImage. Conservare i testi di licenza\n'
            'originali. Componenti esterni del sistema non sono inclusi.\n'
            'Ricostruire i pacchetti con i normali strumenti Debian/Ubuntu e usare\n'
            'le ricette AppImage del progetto per assemblare la propria build.\n'
        ).encode(),
    }
    print(json.dumps(write_archive(args.output, records, documents), indent=2))


if __name__ == '__main__':
    main()
