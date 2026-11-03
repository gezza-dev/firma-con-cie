#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Public product identity shared by the desktop packaging tools."""
import re
from pathlib import Path

DISPLAY_NAME = 'Firma con CIE'
PACKAGE_NAME = 'firma-con-cie'
ARTIFACT_STEM = PACKAGE_NAME


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


def linux_package_name(version, distribution, architecture, package_format):
    """Download filename; native package identities and release fields stay unchanged."""
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid application release version')
    supported = {
        ('ubuntu', 'deb'): ('amd64', 'arm64'),
        ('ubuntu', 'AppImage'): ('x86_64', 'aarch64'),
        ('fedora', 'rpm'): ('x86_64', 'aarch64'),
        ('arch', 'pkg.tar.zst'): ('x86_64',),
    }
    if architecture not in supported.get((distribution, package_format), ()):
        raise ValueError('Invalid Linux distribution, package format or architecture')
    destination = 'linux' if package_format == 'AppImage' else 'linux_' + distribution
    return f'{ARTIFACT_STEM}_{version}_{destination}_{architecture}.{package_format}'
