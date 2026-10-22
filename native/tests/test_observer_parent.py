# SPDX-License-Identifier: BSD-3-Clause
"""Exercise the production worker supervisor with a blocked synthetic bridge."""
import subprocess, sys, queue, threading

def start():
    return subprocess.Popen([sys.argv[1], 'synthetic', 'synthetic'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def line(p):
    q = queue.Queue()
    threading.Thread(target=lambda: q.put(p.stdout.readline()), daemon=True).start()
    return q.get(timeout=3).strip()

p = start()
try:
    p.stdin.write('observe\n'); p.stdin.flush()
    assert line(p) == 'SYNTHETIC_BLOCK_ENTERED'
    p.stdin.close()
    assert p.wait(timeout=2) == 0, 'EOF must end worker even during blocked PCSC'
finally:
    if p.poll() is None: p.kill(); p.wait()

p = start()
try:
    p.stdin.write('detect\n'); p.stdin.flush()
    assert line(p) == 'CIE_OBSERVER_JSON={"ok":true,"readers":[]}'
    p.stdin.write('sign\n'); p.stdin.flush()
    assert p.wait(timeout=2) == 64, 'private/unknown commands must be rejected'
finally:
    if p.poll() is None: p.kill(); p.wait()
print('Worker EOF during blocked PCSC and command allowlist passed; no real card used')
