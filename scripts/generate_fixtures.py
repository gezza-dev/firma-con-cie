#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Generate fresh PDF/CMS fixtures using the existing SDK test executable."""
import argparse
import subprocess
from pathlib import Path
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('sdk_tests', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = root/'output/verification-fixtures'
output.mkdir(parents=True, exist_ok=True)
subprocess.run([str(args.sdk_tests.resolve()), str(output)], cwd=root, check=True)
print('Fixtures:', output)
print('Synthetic certificates expire after one hour; regenerate before later test runs.')
