#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Audit a Windows payload or an Inno installer without executing the installer.

Read raw files, UTF-16/URI/JSON path encodings, ZIP/JAR members and compressed
notices. Explicit profile roots also cover builds made on other operating
systems. Reports contain relative filenames, never the private root values.
"""
import argparse
import gzip
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile
import zlib

from build_privacy import local_path_markers
from windows_file_safety import is_link_or_junction


class DistributionAudit:
    def __init__(self, roots=None):
        self.roots = roots
        self.files = self.objects = self.archives = self.expanded = 0
        self.findings, self.errors = [], []

    def blob(self, data, name, depth=0):
        self.objects += 1
        if local_path_markers(data, self.roots):
            self.findings.append(name)
        if depth > 3:
            self.errors.append(name + ': archive depth exceeded')
            return
        try:
            if data[:4] == b'PK\x03\x04':
                self.archives += 1
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    for entry in archive.infolist():
                        if entry.is_dir():
                            continue
                        if entry.file_size > 256 * 1024**2 or self.expanded + entry.file_size > 4 * 1024**3:
                            raise ValueError('archive expansion limit exceeded')
                        self.expanded += entry.file_size
                        self.blob(archive.read(entry), name + '!' + entry.filename, depth + 1)
            elif name.lower().endswith(('.z', '.gz')):
                expanded = gzip.decompress(data) if data[:2] == b'\x1f\x8b' else zlib.decompress(data)
                if len(expanded) > 256 * 1024**2 or self.expanded + len(expanded) > 4 * 1024**3:
                    raise ValueError('compressed object limit exceeded')
                self.expanded += len(expanded)
                self.archives += 1
                self.blob(expanded, name + '!decompressed', depth + 1)
        except (ValueError, OSError, EOFError, zipfile.BadZipFile, zlib.error) as error:
            self.errors.append(name + ': ' + type(error).__name__)

    def directory(self, directory):
        directory = Path(directory)
        if is_link_or_junction(directory):
            self.errors.append('$payload-root: unexpected link')
            return
        # Prune links/junctions before descent, not after entering their targets.
        for folder, directories, files in os.walk(directory, followlinks=False):
            keep = []
            for name in sorted(directories):
                child = Path(folder) / name
                if is_link_or_junction(child):
                    self.errors.append(child.relative_to(directory).as_posix() + ': unexpected link')
                else:
                    keep.append(name)
            directories[:] = keep
            for name in sorted(files):
                file = Path(folder) / name
                if is_link_or_junction(file):
                    self.errors.append(file.relative_to(directory).as_posix() + ': unexpected link')
                elif file.is_file():
                    self.files += 1
                    self.blob(file.read_bytes(), file.relative_to(directory).as_posix())

    def result(self):
        return {'passed': not self.findings and not self.errors, 'filesChecked': self.files,
                'objectsChecked': self.objects, 'archivesChecked': self.archives,
                'expandedArchiveBytes': self.expanded, 'additionalProfileRoots': len(self.roots or []),
                'findings': self.findings, 'errors': self.errors,
                'archiveFormats': ['ZIP/JAR', 'gzip/zlib'], 'installerExecuted': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('payload', type=Path)
    parser.add_argument('--profile-root', action='append', type=Path, help='Repeat for old Windows/macOS build profiles; values are not logged')
    parser.add_argument('--innex', type=Path, help='innex 0.7.2 or later, required for an installer')
    parser.add_argument('--temporary-root', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    audit = DistributionAudit(args.profile_root)
    if args.payload.is_dir():
        audit.directory(args.payload)
    elif args.payload.is_file() and args.innex:
        audit.blob(args.payload.read_bytes(), '$installer-header')
        metadata = subprocess.run([str(args.innex.resolve()), str(args.payload.resolve()), '--debug'],
                                  capture_output=True, check=True, timeout=60)
        audit.blob(metadata.stdout + metadata.stderr, '$installer-metadata')
        with tempfile.TemporaryDirectory(prefix='firma-cie-installer-audit-', dir=args.temporary_root) as temporary:
            subprocess.run([str(args.innex.resolve()), str(args.payload.resolve()), '--extract', temporary],
                           capture_output=True, check=True, timeout=180)
            audit.directory(Path(temporary))
    else:
        parser.error('Choose a payload directory or supply --innex for an installer')
    result = audit.result()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
