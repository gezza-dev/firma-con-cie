#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Run inside the Flatpak test sandbox; synthetic software tests, never detect.

The caller must disable the PC/SC socket and provide the external development
kit read-only. This tool does not install packages or configure browsers.
"""
import argparse
import configparser
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess

APP_ID = 'it.giancarloezza.FirmaConCIE.Test'


def check(manifest, tools, report):
    info = configparser.ConfigParser()
    info.read('/.flatpak-info')
    assert os.environ.get('FLATPAK_ID') == APP_ID
    assert info['Application']['name'] == APP_ID
    assert 'pcsc' not in info.get('Context', 'sockets', fallback='').split(';')
    assert 'no-card-guard.so' in os.environ.get('LD_PRELOAD', '')
    assert not Path('/run/pcscd/pcscd.comm').exists()
    assert not (tools.parent / 'outside-home-sentinel').exists()
    value = json.loads(manifest.read_text())
    for name, digest in value['files'].items():
        assert hashlib.sha256((Path('/app') / name).read_bytes()).hexdigest() == digest, name
    app = Path('/app/lib/firma-con-cie')
    runtime = app / 'cie_native'
    assert not (runtime / 'tests').exists() and not (runtime / 'ltv/tests').exists()
    assert not list(Path('/app/share/icons').rglob('*1024*png'))
    elf_count = 0
    for name in value['files']:
        path = Path('/app') / name
        with path.open('rb') as stream:
            if stream.read(4) != b'\x7fELF':
                continue
        elf_count += 1
        env = dict(os.environ)
        if 'cie_native/ltv/jre/' in name:
            jre = runtime / 'ltv/jre/linux-x86_64/lib'
            env['LD_LIBRARY_PATH'] = str(jre) + ':' + str(jre / 'server')
        result = subprocess.run(['ldd', str(path)], env=env, text=True, capture_output=True, check=True)
        assert 'not found' not in result.stdout, (name, result.stdout)
    assert elf_count == value['elfFilesChecked']
    pdfium = ctypes.CDLL(str(app / 'lib/libpdfium.so'))
    pdfium.FPDF_InitLibrary()
    pdfium.FPDF_LoadDocument.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    pdfium.FPDF_LoadDocument.restype = ctypes.c_void_p
    document = pdfium.FPDF_LoadDocument(str(app / 'data/flutter_assets/assets/prova.pdf').encode(), None)
    assert document
    pdfium.FPDF_GetPageCount.argtypes = [ctypes.c_void_p]
    assert pdfium.FPDF_GetPageCount(document) > 0
    pdfium.FPDF_CloseDocument.argtypes = [ctypes.c_void_p]
    pdfium.FPDF_CloseDocument(document)
    pdfium.FPDF_DestroyLibrary()
    report.parent.mkdir(parents=True, exist_ok=True)
    for script, name in [('smoke_native.py', 'smoke.json'), ('test_ltv.py', 'dss.json')]:
        test_env = dict(os.environ, LD_LIBRARY_PATH=str(runtime) + ':' + str(app / 'lib'))
        result = subprocess.run(['/usr/bin/python3', str(tools / 'scripts' / script),
                                 '--runtime', str(runtime), '--test-tools-runtime', str(tools),
                                 '--report', str(report.parent / name)], env=test_env, text=True, capture_output=True)
        (report.parent / (script + '.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (script, result.stderr[-5000:])
    smoke = json.loads((report.parent / 'smoke.json').read_text())
    assert smoke['backendLoaded'] and 'cardDetection' not in smoke
    dss = json.loads((report.parent / 'dss.json').read_text())
    assert dss['passed'] and dss['selfTests']['passedCases'] >= 14
    result = {'passed': True, 'appId': APP_ID, 'payloadFilesVerified': len(value['files']),
              'elfFilesResolved': elf_count, 'pdfiumLoadedSyntheticPdf': True,
              'nativeSmokeWithoutDetectPassed': True, 'dssCasesPassed': dss['selfTests']['passedCases'],
              'syntheticRootRejected': dss['productionRejectsSyntheticRoot'],
              'pcscSocketDisabled': True, 'pcscCallsGuarded': True,
              'outsideSandboxSentinelHidden': True, 'realCardTestsRun': False,
              'browserConfigurationModified': False}
    report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--test-tools', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    check(args.manifest, args.test_tools, args.report)
