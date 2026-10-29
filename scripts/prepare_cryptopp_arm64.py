#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fix the case of Crypto++ 8.9's Windows ARM64 SDK include in extracted sources."""
from pathlib import Path


def prepare_windows_arm64(source):
    path = Path(source)/'cpu.cpp'
    original = path.read_bytes()
    before, after = b'# include <Windows.h>', b'# include <windows.h>'
    # The caller already verified the archive against dependencies.lock.json.
    # Fail closed if upstream changes; preserve every other byte and line ending.
    if original.count(before) != 1 or after in original:
        raise ValueError('Unexpected Crypto++ Windows ARM64 include; review the locked cpu.cpp')
    path.write_bytes(original.replace(before, after, 1))
