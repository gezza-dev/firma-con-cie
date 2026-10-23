#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Explicit per-profile Firefox setup. Inspection never loads NSS or a module.

On apply NSS generates the CIE record in an empty temporary module database.
Only that record is merged atomically into the chosen profile. Other modules
and cert/key databases are never initialized. A verified private PC/SC guard
also blocks the CIE transport. No browser, PIN, certificate publication or login.
"""
import argparse
import configparser
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

NAME = 'Firma con CIE Linux'
LIBRARIES = ('libcie_linux_pkcs11.so', 'libcie_web.so', 'libcie-pkcs11.so')


class SetupError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def records(data):
    try:
        text = data.decode('utf-8')
    except UnicodeError:
        raise SetupError('profile_invalid')
    result = []
    for block in re.split(r'\n\s*\n', text.replace('\r\n', '\n')):
        fields = {}
        for line in block.splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            key, sep, value = line.partition('=')
            if not sep or key in fields:
                raise SetupError('profile_invalid')
            fields[key] = value
        if fields:
            if 'name' not in fields or 'library' not in fields:
                raise SetupError('profile_invalid')
            result.append(fields)
    return result


def checked(path, *, directory=False, profile_index=False):
    for ancestor in [path, *path.parents]:
        if ancestor.is_symlink():
            raise SetupError('unsafe_path')
    info = path.stat()
    valid = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    # Firefox creates profiles.ini with 0666 & umask (often 0664 on Ubuntu).
    # This is only an untrusted discovery index, never a write destination.
    # Selected profile directories and NSS files retain the stricter checks.
    forbidden = 0o002 if profile_index and not directory else 0o022
    if not valid or info.st_uid != os.getuid() or info.st_mode & forbidden or (not directory and info.st_nlink != 1):
        raise SetupError('unsafe_path')
    return path


def read_private(path, maximum=1024 * 1024, *, profile_index=False):
    checked(path, profile_index=profile_index)
    if path.stat().st_size > maximum:
        raise SetupError('profile_invalid')
    return path.read_bytes()


def atomic_write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.cie-setup-', delete=False) as file:
        temporary = Path(file.name)
        try:
            os.chmod(temporary, 0o600)
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def merge_record(original, name, replacement):
    # Preserve every unrelated byte, including comments and unknown NSS fields.
    parts = re.split(rb'(\r?\n[ \t]*\r?\n)', original)
    replaced = False
    body = replacement.rstrip(b'\r\n')
    if b'\r\n' in original:
        body = body.replace(b'\n', b'\r\n')
    for index in range(0, len(parts), 2):
        parsed = records(parts[index])
        if parsed and parsed[0]['name'] == name:
            parts[index] = body
            replaced = True
    result = b''.join(parts)
    if not replaced:
        result += (b'' if result.endswith(b'\n\n') else b'\n\n') + body + b'\n\n'
    return result


class FirefoxSetup:
    def __init__(self, home, runtime, *, proc=Path('/proc'), modutil='/usr/bin/modutil', run=subprocess.run):
        self.home, self.runtime, self.proc = Path(home), Path(runtime), Path(proc)
        self.modutil, self.run = modutil, run

    def processes_running(self):
        for process in self.proc.iterdir():
            if not process.name.isdigit():
                continue
            try:
                if process.stat().st_uid == os.getuid() and (process / 'comm').read_text().strip() in {'firefox', 'firefox-bin'}:
                    return True
            except FileNotFoundError:
                continue
            except PermissionError:
                raise SetupError('browser_status_unknown')
        return False

    def profiles(self):
        found = []
        config = Path(os.environ.get('XDG_CONFIG_HOME') or self.home / '.config')
        if not config.is_absolute() or '..' in config.parts or not config.is_relative_to(self.home):
            config = self.home / '.config'
        roots = [('firefox', self.home / '.mozilla/firefox'),
                 ('firefox', self.home / '.config/mozilla/firefox'),
                 ('firefox', config / 'mozilla/firefox'),
                 ('snap', self.home / 'snap/firefox/common/.mozilla/firefox'),
                 ('snap', self.home / 'snap/firefox/common/.config/mozilla/firefox')]
        seen, visited = set(), set()
        for target, root in roots:
            if root in visited:
                continue
            visited.add(root)
            ini = root / 'profiles.ini'
            if not ini.exists():
                continue
            data = configparser.ConfigParser(interpolation=None)
            try:
                data.read_string(read_private(ini, profile_index=True).decode('utf-8'))
            except (UnicodeError, configparser.Error):
                raise SetupError('profiles_invalid')
            for section in data.sections():
                if not re.fullmatch(r'Profile\d+', section):
                    continue
                item = data[section]
                value = item.get('Path', '')
                path = root / value if item.get('IsRelative') == '1' else Path(value)
                if not value or not path.is_absolute() or '..' in path.parts:
                    raise SetupError('unsafe_path')
                allowed = self.home / 'snap/firefox/common' if target == 'snap' else self.home
                if not path.is_relative_to(allowed) or (target, path) in seen:
                    continue
                checked(path, directory=True)
                seen.add((target, path))
                identity = digest((target + '\0' + str(path)).encode())
                found.append(dict(id=identity, label=item.get('Name', path.name)[:100], target=target, path=path))
        return found

    def runtime_files(self):
        manifest_path = self.runtime / 'backend-manifest.json'
        manifest = json.loads(manifest_path.read_text())
        if (manifest.get('system') != 'linux' or not manifest.get('linux_web_full_pin_only')
                or not manifest.get('linux_firefox_snap_core24_abi_verified')):
            raise SetupError('runtime_invalid')
        names = [*LIBRARIES, 'browser_setup/firefox_setup.py', 'browser_setup/libcie_browser_setup_guard.so']
        hashes = {}
        for name in names:
            path = self.runtime / name
            if path.is_symlink() or not path.is_file():
                raise SetupError('runtime_invalid')
            hashes[name] = digest(path.read_bytes())
            if hashes[name] != manifest['files'].get(name):
                raise SetupError('runtime_invalid')
        return hashes

    def permission(self):
        try:
            completed = self.run(['/usr/bin/snap', 'connections', 'firefox'], capture_output=True,
                                 text=True, timeout=5, env=dict(os.environ, LC_ALL='C'))
            if completed.returncode:
                return 'unknown'
            for line in completed.stdout.splitlines():
                fields = line.split()
                if len(fields) >= 3 and fields[0] == 'pcscd' and fields[1] == 'firefox:pcscd':
                    return 'disconnected' if fields[2] == '-' else 'connected'
        except (OSError, subprocess.TimeoutExpired):
            pass
        return 'unknown'

    def inspect(self):
        items = []
        for profile in self.profiles():
            try:
                plan = self.plan(profile['id'])
                state = 'configured' if plan['alreadyConfigured'] else 'needs_setup'
            except (SetupError, OSError, ValueError, KeyError) as error:
                state = str(error) if isinstance(error, SetupError) else 'profile_invalid'
            if state == 'profile_uninitialized':
                continue
            items.append({k: profile[k] for k in ['id', 'label', 'target']} | {'state': state})
        return dict(ok=True, profiles=items, snapPermission=self.permission() if any(p['target'] == 'snap' for p in items) else 'unknown')

    def plan(self, identity):
        profile = next((p for p in self.profiles() if p['id'] == identity), None)
        if not profile:
            raise SetupError('profile_missing')
        path = profile['path']
        try:
            for name in ['cert9.db', 'key4.db']:
                checked(path / name)
            raw = read_private(path / 'pkcs11.txt')
        except FileNotFoundError:
            raise SetupError('profile_uninitialized')
        hashes = self.runtime_files()
        modules = records(raw)
        if any(Path(m['library']).name == 'p11-kit-proxy.so' for m in modules):
            # Avoid an unverified second exposure through a system proxy. Do
            # not initialize that proxy just to discover its smart-card slots.
            raise SetupError('module_conflict')
        candidates = [m for m in modules if m['name'] == NAME or Path(m['library']).name == LIBRARIES[0]]
        if len(candidates) > 1:
            raise SetupError('module_conflict')
        if candidates and not self.owned_module(Path(candidates[0]['library'])):
            raise SetupError('module_conflict')
        generation = digest(json.dumps({n: hashes[n] for n in LIBRARIES}, sort_keys=True).encode())
        directory = (self.home / 'snap/firefox/common/firma-con-cie-module-v1' / generation
                     if profile['target'] == 'snap' else self.runtime)
        library = directory / LIBRARIES[0]
        if any(c in str(library) for c in '\r\n\\"'):
            raise SetupError('unsafe_path')
        name = candidates[0]['name'] if candidates else NAME
        if any(c in name for c in '\r\n'):
            raise SetupError('profile_invalid')
        identical = bool(candidates and candidates[0]['library'] == str(library))
        if profile['target'] == 'snap' and directory.exists():
            self.verify_generation(directory, {n: hashes[n] for n in LIBRARIES})
        fingerprint = digest(json.dumps([identity, digest(raw), str(library), name, hashes], sort_keys=True).encode())
        return dict(ok=True, id=identity, target=profile['target'], label=profile['label'],
                    fingerprint=fingerprint, alreadyConfigured=identical,
                    library=str(library), moduleName=name)

    def owned_module(self, path):
        if not path.is_absolute() or path.name != LIBRARIES[0] or path.is_symlink():
            return False
        try:
            parent = path.parent
            current = self.runtime_files()
            if all(not (parent / n).is_symlink() and digest((parent / n).read_bytes()) == current[n] for n in LIBRARIES):
                return True
            if parent.is_relative_to(self.home / 'snap/firefox/common/firma-con-cie-module-v1'):
                marker = json.loads(read_private(parent / 'cie-module.json'))
                self.verify_generation(parent, marker['files'])
                return marker.get('owner') == 'Firma con CIE' and set(marker['files']) == set(LIBRARIES)
            manifest = json.loads((parent / 'backend-manifest.json').read_text())
            return bool(manifest.get('linux_firefox_pkcs11') and
                        digest(path.read_bytes()) == manifest['files'].get(path.name))
        except (OSError, ValueError, KeyError, SetupError):
            return False

    def verify_generation(self, directory, hashes):
        checked(directory, directory=True)
        if set(p.name for p in directory.iterdir()) != {*LIBRARIES, 'cie-module.json'}:
            raise SetupError('snap_copy_conflict')
        marker = json.loads(read_private(directory / 'cie-module.json'))
        if marker != {'owner': 'Firma con CIE', 'schema': 1, 'files': hashes}:
            raise SetupError('snap_copy_conflict')
        for name in LIBRARIES:
            if digest(read_private(directory / name, maximum=64 * 1024 * 1024)) != hashes[name]:
                raise SetupError('snap_copy_conflict')

    def copy_snap(self, directory, hashes):
        common = self.home / 'snap/firefox/common'
        checked(common, directory=True)
        base = directory.parent
        if not base.exists():
            base.mkdir(mode=0o700)
        checked(base, directory=True)
        if directory.exists():
            self.verify_generation(directory, hashes)
            return
        temporary = Path(tempfile.mkdtemp(prefix='.cie-', dir=base))
        try:
            for name in LIBRARIES:
                data = (self.runtime / name).read_bytes()
                if digest(data) != hashes[name]:
                    raise SetupError('runtime_invalid')
                atomic_write(temporary / name, data)
            atomic_write(temporary / 'cie-module.json', json.dumps(
                {'owner': 'Firma con CIE', 'schema': 1, 'files': hashes}, sort_keys=True).encode())
            os.rename(temporary, directory)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
        self.verify_generation(directory, hashes)

    @contextlib.contextmanager
    def profile_lock(self, profile):
        # Firefox uses POSIX fcntl locks on .parentlock on Linux. Keep the lock
        # across registration, in addition to refusing all live Firefox processes.
        lock = profile / '.parentlock'
        descriptor = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            # Firefox creates this empty lock file with mode 0666 filtered by
            # the user's umask. Its mode is not a credential-file permission.
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise SetupError('unsafe_path')
            try:
                fcntl.lockf(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                raise SetupError('browser_running')
            yield
        finally:
            os.close(descriptor)

    def apply(self, identity, expected):
        if os.geteuid() == 0:
            raise SetupError('run_as_user')
        if self.processes_running():
            raise SetupError('browser_running')
        profile = next((p for p in self.profiles() if p['id'] == identity), None)
        if not profile:
            raise SetupError('profile_missing')
        with self.profile_lock(profile['path']):
            plan = self.plan(identity)
            if plan['fingerprint'] != expected:
                raise SetupError('plan_changed')
            hashes = self.runtime_files()
            if plan['target'] == 'snap':
                self.copy_snap(Path(plan['library']).parent, {n: hashes[n] for n in LIBRARIES})
            if not plan['alreadyConfigured']:
                if not Path(self.modutil).is_file():
                    raise SetupError('tools_missing')
                module_file = profile['path'] / 'pkcs11.txt'
                before = read_private(module_file)
                foreign = lambda data: [m for m in records(data) if m['name'] != plan['moduleName']]
                backup = profile['path'] / 'cie-firefox-setup-backup.json'
                # Keep only module configuration for recovery, never cert/key DBs.
                if backup.exists() or backup.is_symlink():
                    checked(backup)
                atomic_write(backup, json.dumps({'schema': 1, 'pkcs11': before.decode('utf-8')}).encode())
                quote = lambda value: '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
                specification = 'name=' + quote(plan['moduleName']) + ' library=' + quote(plan['library']) + ' NSS="trustOrder=100"'
                try:
                    guard = self.runtime / 'browser_setup/libcie_browser_setup_guard.so'
                    descriptor = os.open(guard, os.O_RDONLY | os.O_NOFOLLOW)
                    try:
                        # An inherited descriptor also supports bundle paths with
                        # spaces, which cannot appear literally in LD_PRELOAD.
                        env = dict(os.environ, LC_ALL='C', LD_PRELOAD='/proc/self/fd/' + str(descriptor))
                        # RawAddModule still recursively opens existing modules.
                        # Generate in an EMPTY database instead of the profile.
                        with tempfile.TemporaryDirectory(prefix='.cie-setup-', dir=profile['path']) as temporary:
                            completed = self.run([self.modutil, '-dbdir', 'sql:.',
                                                  '-nocertdb', '-rawadd', specification, '-force'],
                                                 cwd=Path(temporary), pass_fds=(descriptor,),
                                                 stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env, timeout=20)
                            generated = read_private(Path(temporary) / 'pkcs11.txt')
                            blocks = re.split(rb'\r?\n[ \t]*\r?\n', generated)
                            own_blocks = [block for block in blocks if any(m['name'] == plan['moduleName'] for m in records(block))]
                            if completed.returncode or len(own_blocks) != 1:
                                raise SetupError('registration_failed')
                            proposed = merge_record(before, plan['moduleName'], own_blocks[0])
                    finally:
                        os.close(descriptor)
                    own = [m for m in records(proposed) if m['name'] == plan['moduleName']]
                    if foreign(before) != foreign(proposed) or len(own) != 1 or own[0]['library'] != plan['library']:
                        raise SetupError('registration_failed')
                except (OSError, subprocess.TimeoutExpired, SetupError):
                    raise SetupError('registration_failed_restored')
                if read_private(module_file) != before:
                    raise SetupError('plan_changed')
                atomic_write(module_file, proposed)
                if read_private(module_file) != proposed:
                    raise SetupError('plan_changed')
            return dict(ok=True, configured=True, browserLoginTested=False, pinRequested=False,
                        snapPermission=self.permission() if plan['target'] == 'snap' else 'not_required')

    def connect_pcsc(self):
        if not any(p['target'] == 'snap' for p in self.profiles()):
            raise SetupError('profile_missing')
        if self.processes_running():
            raise SetupError('browser_running')
        if self.permission() != 'connected':
            try:
                self.run(['/usr/bin/pkexec', '/usr/bin/snap', 'connect', 'firefox:pcscd'],
                         stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=45)
            except (OSError, subprocess.TimeoutExpired):
                pass
        if self.permission() != 'connected':
            raise SetupError('permission_not_verified')
        return dict(ok=True, snapPermission='connected', browserLoginTested=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action', choices=['inspect', 'plan', 'apply', 'connect-pcsc'], default='inspect')
    parser.add_argument('--profile', default='')
    parser.add_argument('--fingerprint', default='')
    args = parser.parse_args()
    service = FirefoxSetup(Path.home(), Path(__file__).resolve().parent.parent)
    try:
        result = (service.inspect() if args.action == 'inspect' else
                  service.plan(args.profile) if args.action == 'plan' else
                  service.apply(args.profile, args.fingerprint) if args.action == 'apply' else
                  service.connect_pcsc())
    except SetupError as error:
        result = dict(ok=False, code=str(error))
    except (OSError, ValueError, KeyError, configparser.Error):
        result = dict(ok=False, code='configuration_unavailable')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
