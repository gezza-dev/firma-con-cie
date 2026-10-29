#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Run only production helper metadata queries, without UAC, PC/SC or writes."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess

from windows_helper_manifest import check_helper_manifest
from windows_architecture import pe_machine


def verify(helper):
    if os.name != 'nt':
        raise ValueError('Helper execution requires Windows')
    manifest = check_helper_manifest(helper)
    results = {}
    for command, expected in (('--validate-package', {0}),
                              ('--status-package', {0, 3, 7, 8, 9, 10, 11})):
        # subprocess uses CreateProcess, never ShellExecute/runas. Failure 740
        # must fail the regression rather than open a UAC prompt or be code 6.
        result = subprocess.run([str(helper), command], cwd=helper.parent,
                                capture_output=True, timeout=35,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode not in expected:
            raise AssertionError(f'{command} failed: {result.returncode}')
        results[command] = result.returncode
    return {'passed': True, 'manifest': manifest, 'peMachine': pe_machine(helper),
            'processElevated': bool(ctypes.windll.shell32.IsUserAnAdmin()),
            'metadataExitCodes': results, 'productionInstallations': 0,
            'realCardOperations': 0, 'systemWrites': 0, 'uacRequests': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.helper.resolve())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
