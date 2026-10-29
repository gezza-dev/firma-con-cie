# SPDX-License-Identifier: BSD-3-Clause
"""Explicit local Apple Development or Developer ID code signing."""
import re
import subprocess


class MacCodeSigner:
    def __init__(self, identity, developer_id=False):
        self.identity = identity
        self.developer_id = developer_id
        if developer_id:
            available = subprocess.check_output(
                ['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
            identities = re.findall(r'\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"', available)
            matches = [name for digest, name in identities
                       if digest.lower() == identity.lower() or name == identity]
            if len(matches) != 1 or not matches[0].startswith('Developer ID Application:'):
                raise ValueError('--developer-id requires an available Developer ID Application identity')

    def sign(self, path, entitlements=None, disk_image=False, identifier=None):
        command = ['codesign', '--force', '--sign', self.identity]
        if self.developer_id:
            command += ['--timestamp']
            if not disk_image:
                command += ['--options', 'runtime']
        if entitlements is not None:
            command += ['--entitlements', str(entitlements)]
        if identifier is not None:
            command += ['--identifier', identifier]
        subprocess.run([*command, str(path)], check=True)

    def verify(self, path, disk_image=False):
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
        if self.developer_id:
            result = subprocess.run(['codesign', '-dvvv', str(path)],
                                    capture_output=True, text=True, check=True)
            metadata = result.stderr
            if ('Authority=Developer ID Application:' not in metadata or
                    'Timestamp=' not in metadata or
                    (not disk_image and 'runtime)' not in metadata)):
                raise ValueError('Developer ID, secure timestamp and hardened code are required: ' + str(path))
