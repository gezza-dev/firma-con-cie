#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the actual Git index before exporting/uploading this source snapshot.

Read-only: no network, certificate stores, reader, PIN/PUK or git mutations.
This detects selected mistakes; it is not a legal or complete secret audit.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def indexed_sources():
    entries = subprocess.check_output(
        ['git', 'ls-files', '--stage', '-z'], cwd=ROOT).split(b'\0')
    records = []
    for entry in filter(None, entries):
        metadata, path = entry.split(b'\t', 1)
        mode, digest, stage = metadata.split()
        if stage != b'0' or mode not in (b'100644', b'100755'):
            raise ValueError('Unresolved index entry or unsupported mode: ' + path.decode())
        name = path.decode('utf-8')
        parts = PurePosixPath(name)
        if parts.is_absolute() or '..' in parts.parts or '\\' in name:
            raise ValueError('Unsafe index path: ' + name)
        records.append((name, digest, mode))
    if not records:
        raise ValueError('Empty Git index: stage the intended sources first')
    result = subprocess.run(['git', 'cat-file', '--batch'], cwd=ROOT,
                            input=b'\n'.join(row[1] for row in records) + b'\n',
                            capture_output=True, check=True).stdout
    position = 0
    sources, modes = {}, {}
    for name, digest, mode in records:
        end = result.index(b'\n', position)
        returned, kind, size = result[position:end].split()
        if returned != digest or kind != b'blob':
            raise ValueError('Unexpected Git object: ' + name)
        position = end + 1
        length = int(size)
        sources[name] = result[position:position + length]
        modes[name] = int(mode, 8)
        position += length + 1
    return sources, modes


def check(sources):
    errors = []
    forbidden = {'.git', '.build', '.dart_tool', '.tools', '.venv', 'build',
                 'dist', 'reports', 'output', '__pycache__', '.pub-cache'}
    suffixes = {'.p12', '.pfx', '.key', '.keychain', '.keychain-db', '.mobileprovision',
                '.provisionprofile', '.exe', '.dll', '.dylib', '.so', '.a', '.jar',
                '.dmg', '.zip', '.p7m', '.p7s', '.crl', '.pyc', '.log'}
    secrets = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----|'
                         rb'(?<![A-Za-z0-9_/+])gh[pousr]_[A-Za-z0-9]{30,255}(?![A-Za-z0-9])')
    for name, content in sources.items():
        p = PurePosixPath(name)
        if forbidden.intersection(p.parts) or name.startswith('native/runtime/'):
            errors.append('Generated/private directory in index: ' + name)
        if p.suffix.lower() in suffixes or any(x.endswith(('.app', '.appex')) for x in p.parts):
            errors.append('Binary artifact or credential/document type in index: ' + name)
        if p.suffix.lower() == '.pdf' and name != 'assets/prova.pdf':
            errors.append('Unapproved document in index: ' + name)
        if p.name.startswith('.env') or p.name in {'LOCAL_SETUP.md', 'local-backend.json', 'local-build.json', 'install_manifest.txt'}:
            errors.append('Local configuration in index: ' + name)
        if len(content) >= 50 * 1024 * 1024:
            errors.append('Unexpectedly large source file: ' + name)
        if secrets.search(content):
            errors.append('Possible credential in index (content omitted): ' + name)

    def read(name):
        if name not in sources:
            errors.append('Required source/notice missing: ' + name)
            return b''
        return sources[name]

    if read('LICENSE') != read('native/backend/LICENSE.txt'):
        errors.append('Main upstream BSD license text differs')
    for name in ['README.md', 'NOTICE.md', 'docs/BUILDING.md', 'docs/LICENSING.md',
                 'docs/STATUS.md', 'docs/REPOSITORY.md', 'LICENSES/flutter/LICENSE',
                 'native/backend/LICENSES/gnu/COPYING.LIB',
                 'native/backend/LICENSES/podofo/COPYING.MPL',
                 'native/backend/LICENSES/openssl/LICENSE.txt',
                 'native/preview/pdfium.lock.json', 'native/ltv/toolchain.lock.json']:
        read(name)
    packages = re.findall(r'^  ([A-Za-z0-9_]+):$', read('pubspec.lock').decode(), re.M)
    sdk = {'flutter', 'flutter_test', 'flutter_localizations', 'flutter_web_plugins', 'sky_engine'}
    for name in packages:
        if name not in sdk:
            read('LICENSES/preview/dart/' + name + '/LICENSE')

    ltv = json.loads(read('LICENSES/ltv/manifest.json'))
    jars = json.loads(read('native/ltv/dependencies.lock.json'))['jars']
    if set(ltv['jars']) != set(jars):
        errors.append('Java license inventory differs from dependency lock')
    for name, digest in jars.items():
        item = ltv['jars'].get(name, {})
        if item.get('sha256') != digest or not item.get('licenseFiles'):
            errors.append('Missing/mismatched Java license entry: ' + name)
        for notice in item.get('licenseFiles', []):
            read('LICENSES/ltv/' + notice)
    for name, digest in ltv['noticeSha256'].items():
        if hashlib.sha256(read('LICENSES/ltv/' + name)).hexdigest() != digest:
            errors.append('Original Java notice checksum differs: ' + name)

    preview = json.loads(read('LICENSES/preview/manifest.json'))
    darwin = preview.get('darwin-universal', {})
    notice_lock = json.loads(read('native/preview/darwin-notices.lock.json'))
    if darwin.get('supplementalNoticeSources') != notice_lock:
        errors.append('Darwin PDFium notice provenance differs from its lock')
    supplemental = darwin.get('supplementalNotices', {})
    if not supplemental or not all(any(p.startswith(arch + '/') for p in supplemental)
                                   for arch in notice_lock['archives']):
        errors.append('Darwin PDFium notices missing for one or more architectures')
    for name, digest in supplemental.items():
        if hashlib.sha256(read('LICENSES/preview/darwin-universal/' + name)).hexdigest() != digest:
            errors.append('Original Darwin PDFium notice checksum differs: ' + name)

    for name in ['README.md', 'docs/BUILDING.md', 'docs/LICENSING.md', 'docs/STATUS.md',
                 'docs/REPOSITORY.md', 'LICENSES/README.md', 'LICENSES/ltv/README.md']:
        for target in re.findall(r'\]\(([^)]+)\)', read(name).decode()):
            if '://' in target or target.startswith('#'):
                continue
            target = target.split('#', 1)[0]
            # Repository links may point to a directory; normalize without reading the disk.
            parts = list(PurePosixPath(name).parent.parts)
            for part in PurePosixPath(target).parts:
                if part == '..':
                    if parts:
                        parts.pop()
                elif part != '.':
                    parts.append(part)
            path = '/'.join(parts)
            if path not in sources and not any(x.startswith(path.rstrip('/') + '/') for x in sources):
                errors.append('Broken repository documentation link: ' + name + ' -> ' + target)
    return {'passed': not errors, 'sourceFiles': len(sources),
            'sourceBytes': sum(map(len, sources.values())), 'dartPackagesCovered': len(packages),
            'javaArtifactsCovered': len(jars), 'javaNoticeTextsVerified': len(ltv['noticeSha256']),
            'errors': errors, 'scope': 'staged source snapshot; no binary-release legal certification'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    sources, _ = indexed_sources()
    result = check(sources)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
