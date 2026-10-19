#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""One explicit card-signing attempt; enter a PIN only in the local terminal."""
import argparse
import ctypes
import getpass
import json
import os
from pathlib import Path
import platform
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime', required=True, type=Path)
p.add_argument('--input', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--format', choices=['pdf','p7m','cosign'], required=True)
args = p.parse_args()
if not sys.stdin.isatty():
    raise SystemExit('Use an interactive terminal: the PIN must not be echoed or supplied by a pipe.')
runtime = args.runtime.resolve()
if not args.input.is_file() or args.output.exists():
    raise SystemExit('Choose an existing input file and a NEW output path.')
win = platform.system() == 'Windows'
dll = os.add_dll_directory(str(runtime)) if win else None
prefix = '' if win else 'lib'
suffix = '.dll' if win else '.dylib' if platform.system() == 'Darwin' else '.so'
bridge = ctypes.CDLL(str(runtime/(prefix+'cie_bridge'+suffix)))
bridge.cie_bridge_free.argtypes = [ctypes.c_void_p]
for name, count in [('load',2),('detect',0),('sign',6)]:
    f = getattr(bridge,'cie_bridge_'+name)
    f.argtypes = [ctypes.c_char_p]*count
    f.restype = ctypes.c_void_p

def call(name,*values):
    pointer = getattr(bridge,'cie_bridge_'+name)(*values)
    if not pointer: raise RuntimeError('No native result')
    try: return json.loads(ctypes.string_at(pointer).decode('utf-8'))
    finally: bridge.cie_bridge_free(pointer)

result = call('load',str(runtime/(prefix+'cie-pkcs11'+suffix)).encode(),str(runtime/(prefix+'cie_card_adapter'+suffix)).encode())
if not result.get('ok'): raise SystemExit(result.get('code','backend_missing'))
cards = [r for r in call('detect').get('readers',[]) if r.get('isCie')]
if len(cards) != 1: raise SystemExit('Leave exactly one recognized CIE on a reader and repeat.')
text = getpass.getpass('PIN CIE completo (8 cifre, un solo tentativo): ')
if len(text) != 8 or not text.isascii() or not text.isdigit():
    raise SystemExit('The PIN must contain exactly eight digits. No attempt made.')
pin = ctypes.create_string_buffer(text.encode('ascii'))
text = None
try:
    r = cards[0]
    result = call('sign',r['name'].encode(),r['cardId'].encode(),str(args.input.resolve()).encode(),
        str(args.output.resolve()).encode(),args.format.encode(),pin)
finally:
    ctypes.memset(pin,0,len(pin))
# Never print reader/card identity, paths, certificate subject, or PIN.
print(json.dumps(dict(ok=result.get('ok'),code=result.get('code'),nativeCode=result.get('nativeCode'),
    verification=[{key:s.get(key) for key in ['signatureValid','certificateWithinValidity','revocationStatus']}
        for s in result.get('verification',{}).get('signers',[])]),indent=2))
raise SystemExit(0 if result.get('ok') else 1)
