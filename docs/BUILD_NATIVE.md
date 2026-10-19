# Compilare e provare il backend condiviso

La guida principale aggiornata per il nuovo repository è [BUILDING.md](BUILDING.md):
include backend, interfaccia, CryptoTokenKit, primo utilizzo Windows e DSS/JVM.
Questo documento conserva procedure di approfondimento e riferimenti storici;
per lo stato dei collaudi correnti vedere [STATUS.md](STATUS.md).

La build riguarda esclusivamente il prototipo. Non richiede di modificare l'app
CIE ID installata e non installa librerie nel sistema. Python 3.10+, CMake 3.23+,
Ninja, make, Perl, pkg-config e Meson 1.11+ sono richiesti per la build completa.
I sorgenti delle dipendenze vengono scaricati e verificati usando
`native/backend/scripts/dependencies.lock.json`.

## Linux (Ubuntu 24.04)

```bash
sudo apt-get update
sudo apt-get install build-essential cmake ninja-build pkg-config libpcsclite-dev pcscd libccid python3-venv perl autoconf automake libtool gettext
python3 -m venv .build/tools
.build/tools/bin/pip install meson==1.11.0
export PATH="$PWD/.build/tools/bin:$PATH"
python3 scripts/build_portable_dependencies.py
python3 scripts/build_native.py --dependency-prefix "$PWD/.build/dependencies/linux-$(uname -m)/prefix"
python3 scripts/smoke_native.py --runtime native/runtime/linux --detect --report reports/linux-native.json
```

Per l'interfaccia servono anche Flutter fissato in `toolchain.lock.json` e le
librerie GTK (`libgtk-3-dev`, `liblzma-dev`). Dopo la preparazione del runtime:

```bash
flutter pub get --enforce-lockfile
flutter build linux --release
```

Il bundle copia il runtime in `cie_native`, con rpath `$ORIGIN` per le librerie
private. Devono essere disponibili pcsc-lite e i driver del lettore sul PC finale.
La VM Linux di sviluppo non inoltra automaticamente il lettore USB del Mac.

## Windows x64: compilazione incrociata da Linux

La prima toolchain supportata è MinGW-w64 POSIX. Non si devono collegare oggetti
C++ prodotti da MinGW direttamente al runner MSVC; il ponte usa solo ABI C.

```bash
sudo apt-get install g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix
python3 scripts/build_portable_dependencies.py --target windows-x64 --arch x86_64
python3 scripts/build_native.py --system windows \
  --toolchain "$PWD/.build/dependencies/windows-x64/mingw.cmake" \
  --dependency-prefix "$PWD/.build/dependencies/windows-x64/prefix"
```

Questa build non esegue CTest sull'host Linux. Le DLL e i tre programmi di test
vanno provati su Windows. Il pacchetto di test contiene anche gli script Python,
gli avvisi e una copia delle sorgenti del progetto. Non è firmato Authenticode
ed è destinato esclusivamente a prove di sviluppo.

## Prova sul PC Windows

1. Estrai il pacchetto in una cartella locale e installa **Python 3.10+ a 64 bit**
   se non è già presente. Non occorrono Visual Studio o MSYS2 per questi test.
2. Collega il lettore con il suo driver e appoggia la CIE.
3. Apri PowerShell nella cartella estratta ed esegui:

```powershell
py -3 scripts/smoke_native.py --runtime runtime --detect --report windows-native-report.json
```

Lo script controlla i checksum delle DLL, carica il backend reale, esegue test
SDK/OCSP/CRL/handle e verifica PDF sintetici. Le fixture vengono generate sul PC
al momento della prova. Il report non include nomi dei firmatari, identificativi
della carta o il PIN. Il riconoscimento atteso è `cardDetection.cards: 1`. Se il driver resta in attesa,
il probe termina dopo 30 secondi con `pcsc_timeout`: controllare lettore, carta
e applicazioni che la stanno usando. Il timeout riguarda soltanto la lettura
pubblica, non una firma in corso.

Per provare **una firma reale**, scegli un documento di prova e un nome di output
nuovo. Il file prodotto contiene il certificato della CIE e rimane sul PC.

```powershell
py -3 scripts/test_card_signing.py --runtime runtime --input prova.pdf --output prova-firmata.pdf --format pdf
py -3 scripts/test_card_signing.py --runtime runtime --input prova.pdf --output prova-firmata.p7m --format p7m
```

Ogni comando chiede il PIN nel terminale con input nascosto ed esegue **un solo
tentativo**. Non inserire il PIN nella riga di comando o in chat. In caso di errore
non vengono fatti altri tentativi automaticamente. Non ripetere prove con PIN
volutamente errati: riducono il numero di tentativi disponibili sulla carta.

Per compilare anche l'interfaccia Flutter sul PC occorrono Flutter e Visual Studio
con gli strumenti C++ desktop. Copia le DLL del pacchetto e il manifest in
`native/runtime/windows` della copia sorgenti, quindi:

```powershell
flutter pub get --enforce-lockfile
flutter build windows --release
```

Il runner include automaticamente il runtime privato. La GUI è stata eseguita
su Windows, con firme reali PAdES/CAdES verificate:
vedere [VALIDATION.md](VALIDATION.md). Una nuova compilazione incrociata C++
richiede comunque l'esecuzione dei test sul sistema destinatario.

## macOS: backend compilato dalle sorgenti condivise

```bash
python3 scripts/build_portable_dependencies.py --arch arm64
python3 scripts/build_native.py --dependency-prefix "$PWD/.build/dependencies/macos-arm64/prefix"
python3 scripts/smoke_native.py --runtime native/runtime/macos --detect --report reports/macos-native.json
```

Per una build Universal del backend occorre un prefisso di librerie che contenga
entrambe le architetture; passare poi `--architectures 'arm64;x86_64'` a
`build_native.py`. `scripts/merge_macos_dependencies.py` controlla che gli header delle due build
siano identici e unisce gli archivi senza modificare i prefissi originali.
Gli header generati delle dipendenze devono essere compatibili
con entrambe le architetture. Una build con sole librerie ARM64 non diventa
Universal aggiungendo soltanto il parametro CMake.

`scripts/prepare_native.py` rimane disponibile per confronti con il vecchio
backend macOS v1.5.2 non modificato. I due percorsi sono alternativi: il runtime
in `native/runtime/macos` identifica nel manifest quale backend è stato preparato.

Per assemblare l'app macOS con un runtime scelto esplicitamente:

```bash
python3 scripts/build_macos.py --runtime native/runtime/macos --identity 'Apple Development: ...'
```

Durante questo porting il runtime macOS condiviso di confronto è stato salvato
separatamente in `native/runtime/macos-shared`; può essere selezionato con lo
stesso parametro, mantenendo disponibile il runtime precedente.

Per mantenere anche due bundle GUI distinti, usare `--destination` e
`--build-workspace` dedicati:

```bash
python3 scripts/build_macos.py --runtime native/runtime/macos-shared \
  --identity 'Apple Development: ...' \
  --destination /percorso/Builds/CIE-Flutter/macos-shared \
  --build-workspace /percorso/Builds/CIE-Flutter/workspace-shared
```

Lo script impone `pubspec.lock` prima di compilare e firma le librerie prima
del bundle. I checksum successivi alla firma sono nel manifest delle risorse;
quelli della build nativa sono conservati in `source-runtime-manifest.json`.

Per un controllo indipendente dei documenti già firmati, senza usare la carta,
servono Python 3.10+ con `pypdf` e il comando OpenSSL:

```bash
python3 scripts/verify_signed_documents.py --runtime native/runtime/macos-shared \
  --input prova.pdf --pdf prova-firmata-pades.pdf --p7m prova-firmata-cades.p7m \
  --openssl /percorso/openssl --require-trust --report reports/firme-reali.json
```

Lo stesso script usa DLL Windows o librerie Linux sulla rispettiva piattaforma.
Controlla indipendentemente CMS, ByteRange e contenuto P7M. Il backend controlla
catena e revoca; `--require-trust` richiede anche percorso attendibile e stato
non revocato di tutti i certificati non root, altrimenti restituisce codice 1.
Senza il parametro, il codice di uscita attesta la sola integrità e il report
conserva comunque gli esiti di fiducia/revoca. La qualificazione giuridica non
viene attestata. I documenti firmati rimangono locali.

## Prove temporali senza carta

Lo smoke esegue i casi RFC 3161 e le fixture temporali non attendibili tramite
lo stesso ponte usato dalla GUI. I documenti già firmati possono essere
ricontrollati con `scripts/verify_signed_documents.py`; `--require-history`
richiede prove storiche positive, mentre `--require-trust` riguarda i controlli
attuali. Una firma senza marca non supera il requisito storico. Ambito:
[TEMPORAL_VALIDATION.md](TEMPORAL_VALIDATION.md). Non eseguire nuove firme per
questi test e non inviare PIN o documenti personali a servizi esterni.

## Worker DSS/LTA

Il runtime include il trasporto privato `ltv/fetcher/cie_crl_fetch`, compilato
dagli stessi sorgenti C++ e firmato nel bundle macOS. La verifica del prototipo
può recuperare le sole CRL; documenti e chiavi restano locali. Per i test comuni
di recupero e validazione storica, senza carta/PIN:

```sh
python3 scripts/test_history.py --runtime native/runtime/macos-crl-history-integrated --report reports/history.json
```

Su Windows usare il Python disponibile sul PC e il relativo runtime Windows.
`--document /percorso/documento.pdf` aggiunge una verifica reale con recupero
CRL. Le prove deterministiche includono dati mancanti, motivi sconosciuti,
firme CRL alterate, scadenza, accuratezza della marca e revoche precedenti o
successive. La lettura di un documento esistente non richiede la CIE o il PIN.

Dopo il runtime C/C++ eseguire `scripts/build_ltv.py` con Java 21 e Maven
fissati, percorso del runtime base e una nuova destinazione. Il JAR è condiviso
fra Mac e Windows; le JVM private sono specifiche per architettura.
`test_ltv.py` esegue le prove senza carta o PIN. Per usare la GUI copiare il
runtime completo, incluso ltv/, nel percorso previsto dal runner. Sul Mac
build_macos.py incorpora e firma anche le JVM. Policy:
[LONG_TERM_VALIDATION.md](LONG_TERM_VALIDATION.md).


## Diagnosi di una CRL pubblica

Il runtime include `tests/cie_trust_probe` (`.exe` su Windows), collegato allo
stesso SDK del middleware. Esegue in sola lettura la verifica di una CRL già
scaricata e restituisce metadati tecnici senza identità di cittadini.

```text
cie_trust_probe subca002.pem root.pem cierootca.crl
```

Usare soltanto certificati CA e CRL pubblici. Il risultato include hash CRL,
intervallo di validità, uso della chiave, emittente, firma e il vero risultato
`verifyCrlResponse`. `nativeCrlStatus=0` indica GOOD per quel target e quella
data. Non prova la fiducia del certificato di un documento, non scarica la CRL,
non accede alla carta e non installa autorità. Su Windows le DLL MinGW private
devono restare disponibili come negli altri test del runtime.
