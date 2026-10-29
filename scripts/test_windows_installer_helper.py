#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the isolated installer fake's Unicode CLI. No card, store or UAC."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def verify(helper):
    checks = 0
    with tempfile.TemporaryDirectory(prefix='cie-fake-cli-') as temporary:
        folder = Path(temporary)/'prova-\u00e8-\u6f22\u5b57'
        folder.mkdir()
        log = folder/'calls.txt'
        env = dict(os.environ, CIE_INSTALLER_TEST_LOG=str(log))
        # Do not inherit a failure injected by another isolated test.
        env.pop('CIE_INSTALLER_TEST_FAIL', None)
        calls = []

        def run(arguments, expected, extra=None):
            nonlocal checks
            result = subprocess.run([str(helper), *arguments], env=dict(env, **(extra or {})),
                                    capture_output=True, timeout=20)
            if result.returncode != expected:
                raise AssertionError('Installer fake CLI return code differs from its protocol')
            actual = log.read_text().splitlines() if log.exists() else []
            if actual != calls:
                raise AssertionError('Installer fake CLI log differs from its protocol')
            checks += 1

        for command in ('--plan-package','--install-package','--unregister-package','/install'):
            calls.append(command)
            run([command], 0)
        run([], 6)
        run(['--unsupported'], 6)
        run(['--\u00e8-\u6f22\u5b57'], 6)
        calls.append('--install-package')
        run(['--install-package'], 4, {'CIE_INSTALLER_TEST_FAIL':'--install-package'})
    return {'passed':True,'checks':checks,'unicodeLogPathVerified':True,
            'productionInstallations':0,'realCardOperations':0,'uacRequests':0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper',type=Path,required=True)
    parser.add_argument('--report',type=Path)
    args = parser.parse_args()
    result = verify(args.helper.resolve())
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
