#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Resolve build destinations without embedding a developer's local paths."""
import json
from pathlib import Path


def _settings(project_root):
    config = Path(project_root) / 'local-build.json'
    if not config.exists():
        return {}
    settings = json.loads(config.read_text(encoding='utf-8'))
    if (not isinstance(settings, dict) or 'build_root' not in settings or
            set(settings) - {'build_root', 'macos_output'}):
        raise ValueError('local-build.json requires build_root and optionally macos_output')
    for key, value in settings.items():
        if not isinstance(value, str) or not value.strip():
            raise ValueError(key + ' must be a nonempty path')
    return settings


def _build_root(settings):
    if not settings:
        return Path.home() / 'Developer/Builds/firma-con-cie'
    value = settings['build_root']
    root = Path(value).expanduser()
    if not root.is_absolute():
        raise ValueError('build_root must be an absolute path or start with ~/')
    return root


def build_root(project_root):
    """Read the optional, Git-ignored local-build.json; never create folders."""
    return _build_root(_settings(project_root))


def macos_paths(project_root):
    """Optionally place both the app and DMG in one local output directory."""
    settings = _settings(project_root)
    root = _build_root(settings)
    output = Path(settings.get('macos_output', 'firma-con-cie')).expanduser()
    if not output.is_absolute():
        output = root / output
    return dict(destination=output, workspace=root / 'workspace-macos',
                dmg=(output if 'macos_output' in settings else root) / 'Firma con CIE.dmg')
