#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Package a private native test runtime and the current corresponding sources."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a = p.parse_args()
a.output.parent.mkdir(parents=True,exist_ok=True)
if a.output.exists(): raise SystemExit('Output already exists')
files = sorted(set(subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0'))-{''})
with tempfile.TemporaryDirectory(prefix='cie-native-package-') as temporary:
    kit = Path(temporary)/'firma-con-cie-windows-x64-testkit'
    shutil.copytree(a.runtime.resolve(),kit/'runtime',ignore=shutil.ignore_patterns('.DS_Store'))
    (kit/'scripts').mkdir()
    for name in ['smoke_native.py','test_card_signing.py','verify_signed_documents.py','test_ltv.py','test_history.py','test_pin.py','test_network_runtime.py','test_pairing_runtime.py','runtime_test_tools.py','ltv_runtime.py']:
        shutil.copy2(ROOT/'scripts'/name,kit/'scripts'/name)
    shutil.copy2(ROOT/'assets/prova.pdf',kit/'prova.pdf')
    shutil.copy2(ROOT/'docs/BUILD_NATIVE.md',kit/'ISTRUZIONI.md')
    for relative in files:
        source = ROOT/relative
        if not source.is_file() or source.is_symlink(): continue
        target = kit/'sources'/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
    (kit/'README.txt').write_text('''Firma con CIE — test del backend Windows x64

Pacchetto di sviluppo, senza installer e senza firma Authenticode.
Non sostituisce l'app CIE ID macOS o il middleware ufficiale.

1. Estrarre tutto il contenuto del file ZIP.
2. Installare Python 3.10 o successivo a 64 bit, se assente.
3. I test software non richiedono lettore, carta, PIN o PUK.
   Leggere sources/docs/COSIGN_GUIDE_PREFERENCES.md e
   sources/docs/SETTINGS_DIAGNOSTICS_PROXY.md per le nuove integrazioni.
4. Aprire PowerShell nella cartella estratta ed eseguire:

   py -3 scripts/smoke_native.py --runtime runtime --report windows-native-report.json
   .\\runtime\\tests\\cie_cosign_tests.exe
   py -3 scripts/test_network_runtime.py --runtime runtime --report windows-network-report.json

Inviare il report JSON; non contiene PIN, nomi o identificativi della carta.
Se il comando py non è disponibile usare python (a 64 bit).
Il controllo della CIE non richiede il PIN e non effettua una firma.

Solo se richiesto esplicitamente, collegare lettore e CIE e usare --detect.
Le prove reali PIN/PUK restano rinviate; nessuno dei test software le esegue.

Dopo il test iniziale, per una prova esplicita di firma PAdES/CAdES:

   py -3 scripts/test_card_signing.py --runtime runtime --input prova.pdf --output prova-firmata.pdf --format pdf
   py -3 scripts/test_card_signing.py --runtime runtime --input prova.pdf --output prova-firmata.p7m --format p7m

Ogni comando chiede il PIN nel terminale con input nascosto, con un solo
invio all'SDK e nessun retry automatico. Il PIN non va inviato in chat.
I documenti firmati contengono il certificato della CIE: conservarli localmente.
La catena di fiducia e la revoca sono verificate alla data corrente; un errore
di rete o una risposta non autenticabile mantengono lo stato sconosciuto.
Il controllo non attesta la qualificazione giuridica. Le marche della firma e
le prove storiche hanno esiti separati; vedere sources/docs/TEMPORAL_VALIDATION.md.
Istruzioni: ISTRUZIONI.md.

La cartella sources contiene il progetto corrispondente alle librerie incluse.
Le dipendenze si ricompilano dagli URL/checksum nel lockfile. Le licenze sono
in runtime/licenses e sources. Il backend è compilato con MinGW-w64 POSIX x64.
L'esecuzione di questo pacchetto su Windows deve ancora essere verificata.
''',encoding='utf-8')
    checksums = []
    for file in sorted(kit.rglob('*')):
        if file.is_file():
            checksums.append(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.relative_to(kit).as_posix())
    (kit/'SHA256SUMS.txt').write_text('\n'.join(checksums)+'\n')
    with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for file in sorted(kit.rglob('*')):
            if file.is_file(): archive.write(file,file.relative_to(kit.parent))
print(a.output)
print('SHA-256:',hashlib.sha256(a.output.read_bytes()).hexdigest())
