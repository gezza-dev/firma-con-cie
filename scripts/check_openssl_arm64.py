#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Reject an OpenSSL ARM64 build graph missing the Windows argv initializer."""
from pathlib import Path
import re


def validate_configuration(build):
    build = Path(build)
    config = (build/'configdata.pm').read_text(encoding='utf-8')
    makefile = (build/'Makefile').read_text(encoding='utf-8')
    # Inspect OpenSSL's generated graph, rather than assuming that inheritance
    # selects Windows sources. build.info also branches on the target's name.
    if 'apps/lib/win32_init.c' not in config.replace('\\','/'):
        raise ValueError('OpenSSL ARM64 configuration omits win32_init.c (win32_utf8argv)')
    if not re.search(r'win32_init\.obj\b', makefile) or 'win32_init.c' not in makefile:
        raise ValueError('OpenSSL ARM64 Makefile omits the win32_init object (win32_utf8argv)')
