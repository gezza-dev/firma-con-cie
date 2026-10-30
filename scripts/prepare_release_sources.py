#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Package verified dependency sources without private paths or build outputs."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def checked_file(path, expected):
    if not path.is_file() or digest(path) != expected:
        raise ValueError('Missing or mismatched source archive: ' + path.name)
    return path


def member_name(name):
    if not name or Path(name).name != name or '\\' in name or name in {'.', '..'}:
        raise ValueError('Unsafe source archive name')
    return name


def inputs(root, native_cache, jdk_archive, java_sources, toolchain_cache):
    lock = json.loads((root/'packaging/release/dependency-sources.lock.json').read_text())
    native = json.loads((root/lock['nativeLock']).read_text())
    records = {}
    for value in native.values():
        name = member_name(value['archive'])
        records['native/'+name] = (checked_file(native_cache/name, value['sha256']), value['url'])
    value = lock['openjdk']; name = member_name(value['archive'])
    records['openjdk/'+name] = (checked_file(jdk_archive, value['sha256']), value['url'])
    binaries = json.loads((root/'native/ltv/dependencies.lock.json').read_text())['jars']
    if {v['binary'] for v in lock['javaSources'].values()} != set(binaries):
        raise ValueError('Source JAR inventory differs from production dependencies')
    for name, value in lock['javaSources'].items():
        name = member_name(name)
        records['java/'+name] = (checked_file(java_sources/name, value['sha256']), value['url'])
    toolchains = json.loads((root/'packaging/release/windows-runtime-sources.lock.json').read_text())
    for package in toolchains['ubuntuSourcePackages'].values():
        for name, value in package['files'].items():
            name = member_name(name)
            records['windows-toolchain/'+name] = (
                checked_file(toolchain_cache/name, value['sha256']), value['url'])
    return records


def write_archive(output, records, documents):
    if output.exists() or output.is_symlink():
        raise FileExistsError('Existing release material is preserved: ' + output.name)
    # Verify all inputs before opening an output file. Archive metadata contains
    # only relative public names, never the location of the developer's cache.
    manifest = {name: {'sha256': digest(path), 'bytes': path.stat().st_size, 'url': url}
                for name, (path, url) in sorted(records.items())}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.sources-', dir=output.parent) as temporary:
        candidate = Path(temporary)/output.name
        with zipfile.ZipFile(candidate, 'w', compression=zipfile.ZIP_STORED) as archive:
            for name, (path, _) in sorted(records.items()):
                item = zipfile.ZipInfo('firma-con-cie-dependency-sources/'+name,
                                       date_time=(2026, 1, 1, 0, 0, 0))
                item.create_system = 3; item.external_attr = 0o100644 << 16
                archive.writestr(item, path.read_bytes())
            for name, content in sorted({**documents,
                    'SOURCE-SHA256.json': (json.dumps(manifest, indent=2)+'\n').encode()}.items()):
                item = zipfile.ZipInfo('firma-con-cie-dependency-sources/'+name,
                                       date_time=(2026, 1, 1, 0, 0, 0))
                item.create_system = 3; item.external_attr = 0o100644 << 16
                archive.writestr(item, content)
        with zipfile.ZipFile(candidate) as archive:
            if archive.testzip() is not None:
                raise ValueError('Source archive CRC verification failed')
            for name, value in manifest.items():
                if hashlib.sha256(archive.read('firma-con-cie-dependency-sources/'+name)).hexdigest() != value['sha256']:
                    raise ValueError('Packaged source checksum mismatch')
        if output.exists():
            raise FileExistsError(output)
        candidate.rename(output)
    return {'files': len(records), 'bytes': output.stat().st_size, 'sha256': digest(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-cache', type=Path, required=True)
    parser.add_argument('--jdk-archive', type=Path, required=True)
    parser.add_argument('--java-sources', type=Path, required=True)
    parser.add_argument('--toolchain-cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    records = inputs(ROOT, args.native_cache, args.jdk_archive, args.java_sources, args.toolchain_cache)
    documents = {name: (ROOT/name).read_bytes() for name in [
        'packaging/release/dependency-sources.lock.json',
        'packaging/release/windows-runtime-sources.lock.json',
        'native/backend/scripts/dependencies.lock.json',
        'docs/BUILDING.md', 'docs/LICENSING.md', 'docs/RELEASE.md']}
    documents['README.txt'] = (
        'Firma con CIE 1.0.0 - sorgenti delle dipendenze\n\n'
        'Usare insieme all\'archivio sorgente del progetto della stessa release.\n'
        'native/: i dodici archivi originali fissati; copiarli nella cartella\n'
        '.build/dependencies/downloads del progetto prima della compilazione.\n'
        'java/: source JAR delle cinquanta dipendenze Java distribuite.\n'
        'openjdk/: sorgenti completi Temurin/OpenJDK 21.0.12.1+1.\n'
        'windows-toolchain/: sorgenti Ubuntu e patch delle versioni GCC/MinGW\n'
        'registrate per il runtime Windows x64. Non contiene SDK Microsoft.\n'
        'I testi delle licenze sono nei sorgenti e nelle cartelle LICENSES del\n'
        'progetto e dei pacchetti. Le ricette permettono di ricompilare/ricollegare\n'
        'le librerie; rigenerare i manifest e firmare la propria build modificata.\n'
        'Non occorrono chiavi o configurazioni del distributore.\n'
    ).encode()
    print(json.dumps(write_archive(args.output, records, documents), indent=2))


if __name__ == '__main__':
    main()
