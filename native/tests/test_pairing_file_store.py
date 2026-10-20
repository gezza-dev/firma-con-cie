#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Isolated cache files only: persistence, renamed program, tampering and paths."""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cie-file-cache-') as folder:
    root = Path(folder)
    env = dict(os.environ, CIE_PAIRING_TEST_CACHE=str(root))
    extension = '.exe' if os.name == 'nt' else ''
    writer, remover = [root / (name + extension) for name in ['CIE-Old-Name', 'CIE-New-Name']]
    for target in [writer, remover]:
        shutil.copyfile(binary, target)
        target.chmod(0o700)
    def run(program, action, card='TESTMIGA', succeeds=True):
        p = subprocess.run([str(program), action, card], env=env,
            capture_output=True, text=True, timeout=30)
        assert (p.returncode == 0) == succeeds, (action, p.returncode, p.stderr)
        return p
    run(writer, 'seed')
    run(writer, 'seed', 'TESTMIGB')
    cache = root / 'cache-v3'
    card = cache / 'TESTMIGA.card'
    other = cache / 'TESTMIGB.card'
    before = card.read_bytes()
    assert b'1234' not in before and b'12345678' not in before
    assert (cache / '.key').stat().st_size == 64
    run(remover, 'present')  # another process/name, same per-user format
    run(remover, 'remove')
    run(remover, 'remove')
    run(remover, 'present', 'TESTMIGB')
    assert not card.exists()
    run(writer, 'seed')
    assert card.read_bytes() != before
    encoded = card.read_bytes()
    damaged = bytearray(encoded); damaged[-1] ^= 1; card.write_bytes(damaged)
    run(remover, 'present', succeeds=False)
    run(remover, 'remove')  # no decryption needed to remove a damaged record
    run(remover, 'present', 'TESTMIGB')
    key = cache / '.key'
    saved_key = key.read_bytes(); key.unlink()
    run(remover, 'present', 'TESTMIGB', succeeds=False)
    run(writer, 'seed', succeeds=False)  # never regenerate over existing records
    assert not key.exists()
    run(remover, 'remove', 'TESTMIGB')
    run(writer, 'seed')  # now empty: a new random key may be created
    assert key.read_bytes() != saved_key
    if os.name != 'nt':
        assert stat.S_IMODE(cache.stat().st_mode) == 0o700
        assert stat.S_IMODE(key.stat().st_mode) == 0o600
        assert stat.S_IMODE(card.stat().st_mode) == 0o600
        card.chmod(0o644); run(remover, 'present', succeeds=False); card.chmod(0o600)
        witness = root / 'outside'; witness.write_bytes(b'outside untouched')
        card.unlink(); card.symlink_to(witness)
        run(remover, 'remove', succeeds=False)
        assert witness.read_bytes() == b'outside untouched'
        card.unlink(); run(writer, 'seed')
        key_bytes=key.read_bytes();key.unlink();key.symlink_to(witness)
        run(remover, 'present', succeeds=False)
        assert witness.read_bytes() == b'outside untouched'
        key.unlink();key.write_bytes(key_bytes);key.chmod(0o600)
        import fcntl
        with (cache / '.lock').open('r+b') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            run(remover, 'present', succeeds=False)
        run(remover, 'present')
    run(remover, 'remove')
    assert not list(cache.glob('*.card')) and not list(cache.glob('.tmp-*'))
print(json.dumps({'passed': True, 'isolatedFileCache': True,
    'restartAndRename': True, 'otherCardPreserved': True,
    'tamperingAndMissingKeyRejected': True, 'damagedRecordRemovable': True,
    'posixPermissionsSymlinksAndLock': os.name != 'nt',
    'realCredentialStoreOperations': 0, 'realCardOperations': 0}))
