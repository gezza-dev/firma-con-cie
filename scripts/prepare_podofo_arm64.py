#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Avoid PoDoFo 1.1.2's GCC/MinGW charconv fallback when using libc++."""
from pathlib import Path


def prepare_windows_arm64(source):
    path = Path(source)/'src/podofo/private/charconv_compat.h'
    original = path.read_bytes()
    before = b'(defined(__MINGW32__) &&  __GNUC__ < 12)'
    after = b'(defined(__MINGW32__) && !defined(_LIBCPP_VERSION) && __GNUC__ < 12)'
    # Both from_chars and to_chars need the library-aware check. Clang's
    # __GNUC__ compatibility macro does not describe libc++ feature support.
    if original.count(before) != 2 or after in original:
        raise ValueError('Unexpected PoDoFo charconv guards; review the locked header')
    path.write_bytes(original.replace(before, after))
