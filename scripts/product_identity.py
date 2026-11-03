#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Public product identity shared by the desktop packaging tools."""
import re
from pathlib import Path

DISPLAY_NAME = 'Firma con CIE'
PACKAGE_NAME = 'firma-con-cie'
ARTIFACT_STEM = PACKAGE_NAME
LINUX_ARTIFACT_STEM = ARTIFACT_STEM + '-linux'


def application_version(root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$',
                      (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    if not match:
        raise ValueError('Missing application release version in pubspec.yaml')
    return match.group(1)


def windows_installer_name(version, architecture='x64'):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:\.\d+)?', version):
        raise ValueError('Invalid installer version')
    if architecture not in ('x64', 'arm64'):
        raise ValueError('Invalid Windows architecture')
    return f'{ARTIFACT_STEM}_{version}_windows_{architecture}_setup'


def macos_image_name(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid application release version')
    return f'{ARTIFACT_STEM}_{version}_macOS_universal.dmg'
