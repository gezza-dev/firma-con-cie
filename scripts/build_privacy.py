#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Keep compiler paths out of distributed code; leave author/signing names intact."""
from pathlib import Path
import os
import re
import shlex
from urllib.parse import unquote_to_bytes


def compiler_path_flags(source, build=None, dependencies=None):
    mappings = {}
    for path, destination in [(Path.home(), '/home/build'),
                              (source, '/src/firma-con-cie'),
                              (build, '/build/firma-con-cie'),
                              (dependencies, '/build/dependencies')]:
        if path is not None:
            # macOS accepts /var and /private/var spellings of the same tree.
            for spelling in {str(Path(path).absolute()), str(Path(path).resolve())}:
                mappings[spelling] = destination
    # A more specific mapping follows its parent: GCC applies the last match.
    return [f'-{option}={old}={new}'
            for old, new in sorted(mappings.items(), key=lambda item: len(item[0]))
            for option in ['ffile-prefix-map', 'fdebug-prefix-map']]


def compiler_flags_text(existing, source, build=None, dependencies=None):
    return ' '.join(filter(None, [existing,
        shlex.join(compiler_path_flags(source, build, dependencies))]))


def local_path_markers(data, roots=None):
    if roots is None:
        home = Path.home()
        generic_ci_home = str(home).replace('\\', '/').lower() in {
            '/home/runner', '/root', 'c:/users/runneradmin'}
        roots = [] if os.environ.get('GITHUB_ACTIONS') == 'true' and generic_ci_home else [home]
    # Profile paths can occur in URI form, escaped JSON or UTF-16 strings.
    normalized = unquote_to_bytes(data.replace(b'\0', b''))
    normalized = normalized.replace(b'\\\\', b'\\').replace(b'\\', b'/').lower()
    normalized = re.sub(rb'/+', b'/', normalized)
    return [str(root) for root in roots
            if str(root).replace('\\', '/').rstrip('/').encode().lower() in normalized]


def check_public_paths(directory, roots=None):
    directory = Path(directory)
    files = 0
    findings = []
    for file in sorted(directory.rglob('*')):
        if not file.is_file() or file.is_symlink():
            continue
        files += 1
        if local_path_markers(file.read_bytes(), roots):
            findings.append(str(file.relative_to(directory)))
    if findings:
        raise ValueError('Local profile path embedded in release files: ' + ', '.join(findings))
    return {'filesChecked': files, 'localProfilePathsFound': False}
