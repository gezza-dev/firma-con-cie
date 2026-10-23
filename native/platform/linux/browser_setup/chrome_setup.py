#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""User-confirmed desktop Chrome setup, without opening a user's NSS database.

Reuse Firefox's guarded empty-database record generation and atomic merge.
Only desktop Chrome's selected NSS module file is changed; no certificates,
keys, Firefox profiles, Snap permissions, browser launch or card operations.
"""
import sys

# Inspection must not create __pycache__ in a writable portable bundle.
sys.dont_write_bytecode = True

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import stat

from firefox_setup import FirefoxSetup, SetupError, checked, digest


def default_database(home, data_home=None):
    # Same selection as configure_chrome_linux.py / desktop Chromium M146+.
    legacy = home / '.pki/nssdb'
    if legacy.is_dir():
        return legacy
    data = Path(data_home) if data_home and Path(data_home).is_absolute() else home / '.local/share'
    return data / 'pki/nssdb'


class ChromeSetup(FirefoxSetup):
    backup_name = 'cie-chrome-setup-backup.json'

    def __init__(self, home, runtime, *, data_home=None, chrome_paths=None, **kwargs):
        super().__init__(home, runtime, **kwargs)
        self.database = default_database(self.home, data_home)
        self.chrome_paths = chrome_paths if chrome_paths is not None else (
            Path('/usr/bin/google-chrome'), Path('/usr/bin/google-chrome-stable'),
            Path('/opt/google/chrome/chrome'))

    def processes_running(self):
        for process in self.proc.iterdir():
            if not process.name.isdigit():
                continue
            try:
                if process.stat().st_uid == os.getuid() and (process / 'comm').read_text().strip() in {
                        'chrome', 'google-chrome', 'chromium', 'chromium-browse'}:
                    return True
            except FileNotFoundError:
                continue
            except PermissionError:
                raise SetupError('browser_status_unknown')
        return False

    def profiles(self):
        if '..' in self.database.parts:
            raise SetupError('unsafe_path')
        if not self.database.exists():
            return []
        if self.database.is_relative_to(self.home / 'snap') or self.database.is_relative_to(self.home / '.var/app'):
            raise SetupError('database_unsupported')
        checked(self.database, directory=True)
        return [dict(id='chrome-desktop', label='Google Chrome', target='chrome', path=self.database)]

    def runtime_files(self):
        hashes = super().runtime_files()
        name = 'browser_setup/chrome_setup.py'
        path = self.runtime / name
        manifest = json.loads((self.runtime / 'backend-manifest.json').read_text())
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != manifest['files'].get(name):
            raise SetupError('runtime_invalid')
        return hashes | {name: manifest['files'][name]}

    def plan(self, identity='chrome-desktop'):
        try:
            return super().plan(identity)
        except SetupError as error:
            if str(error) in {'profile_missing', 'profile_uninitialized'}:
                raise SetupError('database_uninitialized') from None
            raise

    def inspect(self):
        detected = self.database.exists() or any(Path(p).is_file() for p in self.chrome_paths)
        if not detected:
            return dict(ok=True, detected=False, state='not_installed')
        try:
            plan = self.plan()
            return dict(ok=True, detected=True, state='configured' if plan['alreadyConfigured'] else 'needs_setup')
        except (SetupError, OSError, ValueError, KeyError) as error:
            return dict(ok=True, detected=True, state=str(error) if isinstance(error, SetupError) else 'configuration_unavailable')

    @contextlib.contextmanager
    def profile_lock(self, profile):
        # Serialize this app's writers. Chrome itself is checked separately;
        # this is not a claim to acquire Chrome's own profile/SQLite lock.
        descriptor = os.open(profile / '.cie-chrome-setup.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise SetupError('unsafe_path')
            try:
                fcntl.lockf(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                raise SetupError('configuration_busy')
            if self.processes_running():
                raise SetupError('browser_running')
            yield
        finally:
            os.close(descriptor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action', choices=['inspect', 'plan', 'apply'], default='inspect')
    parser.add_argument('--profile', choices=['chrome-desktop'], default='chrome-desktop')
    parser.add_argument('--fingerprint', default='')
    args = parser.parse_args()
    service = ChromeSetup(Path.home(), Path(__file__).resolve().parent.parent,
                          data_home=os.environ.get('XDG_DATA_HOME'))
    try:
        result = (service.inspect() if args.action == 'inspect' else service.plan(args.profile)
                  if args.action == 'plan' else service.apply(args.profile, args.fingerprint))
    except SetupError as error:
        result = dict(ok=False, code=str(error))
    except (OSError, ValueError, KeyError):
        result = dict(ok=False, code='configuration_unavailable')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
