#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Resolve build destinations without embedding a developer's local paths."""
import json
from pathlib import Path


def build_root(project_root):
    """Read the optional, Git-ignored local-build.json; never create folders."""
    config = Path(project_root) / 'local-build.json'
    if not config.exists():
        return Path.home() / 'Developer/Builds/firma-con-cie'
    settings = json.loads(config.read_text(encoding='utf-8'))
    if not isinstance(settings, dict) or set(settings) != {'build_root'}:
        raise ValueError('local-build.json must contain only build_root')
    value = settings['build_root']
    if not isinstance(value, str) or not value.strip():
        raise ValueError('build_root must be a nonempty path')
    root = Path(value).expanduser()
    if not root.is_absolute():
        raise ValueError('build_root must be an absolute path or start with ~/')
    return root
