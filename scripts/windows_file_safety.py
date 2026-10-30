# SPDX-License-Identifier: BSD-3-Clause
"""Keep junction checks strict on Windows and portable on POSIX inspectors."""
import os
import sys


def is_link_or_junction(path):
    if os.name == 'nt' and sys.version_info < (3, 12):
        raise RuntimeError('Windows packaging and auditing require Python 3.12 or later')
    return path.is_symlink() or (os.name == 'nt' and path.is_junction())
