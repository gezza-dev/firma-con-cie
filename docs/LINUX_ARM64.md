# Pacchetto Linux ARM64 di test

Il target è Debian `arm64`, cioè AArch64 a 64 bit little-endian. ARM32/armhf
non è incluso. Il pacchetto mantiene nome, percorsi e comportamento del `.deb`
x86_64, ma contiene eseguibili e librerie ARM64. Non è intercambiabile con il
pacchetto amd64 e non basta cambiare l'architettura nelle informazioni del pacchetto.

## Componenti e provenienza

Interfaccia Flutter, bridge, middleware, provider PKCS#11, observer e trasporto
CRL richiedono binari ARM64. Anche PDFium e la JVM privata devono corrispondere
all'architettura: gli archivi e gli hash sono fissati rispettivamente in
`native/preview/pdfium.lock.json` e `native/ltv/toolchain.lock.json`.
Il worker DSS e i 50 JAR sono indipendenti dalla CPU; il loro riutilizzo richiede
il confronto degli hash con la build già verificata e con il lock delle dipendenze.

La selezione della JVM riconosce Linux ARM64 sia in Dart sia negli strumenti
Python. L'assemblaggio DSS confronta la CPU richiesta con quella del runtime
nativo; il confezionamento controlla inoltre gli ELF e rifiuta una JVM x86_64
in un bundle ARM64. RPM e Arch restano, per ora, ricette di test x86_64.

## Compilazione in un ambiente ARM64

Usare una macchina ARM64 o un ambiente Linux ARM64 emulato. Per mantenere una
base compatibile, la GUI di test viene compilata con Ubuntu 24.04 e Flutter
3.47.7. Sono necessari gli strumenti e le librerie di sviluppo descritti in
[BUILDING.md](BUILDING.md), compreso Meson 1.11.0; il confezionamento richiede
anche dpkg-dev, binutils e desktop-file-utils. Limitare la compilazione a due job.

Da una copia di compilazione con runtime di destinazione non ancora presente:

```sh
python3 scripts/build_portable_dependencies.py --arch aarch64 --jobs 2
python3 scripts/build_native.py --system linux --jobs 2 \
  --dependency-prefix .build/dependencies/linux-aarch64/prefix \
  --output .build/linux-arm64-base
python3 scripts/build_ltv.py --system linux --architecture arm64 \
  --java-home "$CIE_JAVA_HOME" --maven "$CIE_MAVEN" \
  --base-runtime .build/linux-arm64-base --output native/runtime/linux
flutter pub get --enforce-lockfile
CMAKE_BUILD_PARALLEL_LEVEL=2 flutter build linux --release --no-pub
python3 scripts/package_linux_deb.py \
  --bundle build/linux/arm64/release/bundle \
  --output dist/linux-arm64-deb-test --version '1.0.0~test20261025.1'
```

`CIE_JAVA_HOME` indica il JDK ARM64 verificato e `CIE_MAVEN` lo strumento Maven
privato, entrambi fissati nel lock. Per riutilizzare i prodotti Java verificati
si può usare `--skip-java-build`; in tal caso devono essere già presenti anche
JAR delle dipendenze e materiali sorgente richiesti dall'assemblatore.
`--architecture arm64` permette l'assemblaggio DSS da un host di altra CPU,
ma non converte librerie native o JVM. Conservare manifest e provenienza.

L'output deve essere una cartella nuova: gli script non sovrascrivono un
pacchetto precedente. [Contenuto e comportamento dell'installazione](LINUX_PACKAGE.md).

## Verifiche software e isolamento

Eseguire i test nativi e lo smoke nell'ambiente ARM64, usando soltanto
fixture e identità sintetiche. Per una compilazione incrociata eseguire CTest
esplicitamente sul target, dato che `build_native.py` non lo avvia sull'host.
Lo smoke va eseguito senza `--detect`.

```sh
python3 scripts/test_ltv_runtime.py
python3 scripts/test_linux_packaging.py
python3 scripts/smoke_native.py --runtime native/runtime/linux \
  --report reports/linux-arm64-smoke.json
python3 scripts/test_linux_deb.py \
  dist/linux-arm64-deb-test/cie-id-desktop_1.0.0~test20261025.1_arm64.deb \
  --report reports/linux-arm64-deb.json
```

Il test del `.deb` verifica checksum, launcher, icone, caricamento degli ELF,
provider e worker DSS rilocati. Installa, aggiorna e rimuove il pacchetto
soltanto in una cartella temporanea con un database dpkg separato; la
risoluzione delle dipendenze dell'ambiente viene simulata. Non eseguirlo
sul computer x86_64 per convalidare librerie ARM64: deve girare nel target.

Gli ambienti di collaudo sono privati, senza home reale, USB, socket PC/SC
o configurazioni browser dell'utente. L'eventuale prova grafica usa Xvfb,
home temporanea e guardia PC/SC. Le configurazioni guidate dei browser
restano azioni esplicite dell'utente nella Home; il pacchetto non le esegue.

Nel collaudo emulato la compilazione nativa può impiegare un compilatore
incrociato x86_64 per produrre gli ELF AArch64; la GUI e i test vengono poi
eseguiti nell'ambiente ARM64. Registrare separatamente host di compilazione,
CPU dei binari, motore/kernel di emulazione e test realmente eseguiti.
Il tool Flutter ufficiale può essere compilato come AOT ARM64 per ridurre il
costo del bootstrap sotto emulazione, senza cambiare framework o motore
dell’app. I test delle procedure browser devono girare come utente ordinario
con HOME temporanea: non disabilitare il rifiuto di esecuzione come root.

I limiti di proprietà UID/GID delle immagini usa e getta sono adattati solo
nel bootstrap dei pacchetti di base, senza applicare tali adattamenti ai test
del pacchetto dell'app.

## Esiti del collaudo del 24 ottobre 2026

Il pacchetto `0.1.0~test20261024.21_arm64` è stato verificato su Ubuntu 24.04
e Debian 13 ARM64 emulati con QEMU. La base richiede glibc 2.38 o successiva;
non è stata verificata la compatibilità con versioni precedenti delle distribuzioni.
Su entrambe le distribuzioni sono passati i controlli dei 737 file e 60 ELF,
del launcher, delle nove icone, dell'ABI del provider, del worker DSS rilocato
e delle dipendenze. Superati installazione, aggiornamento e rimozione con un
database dpkg temporaneo, preservando un record utente sintetico; superato
anche l'avvio della GUI su display virtuale con PC/SC bloccato.

Nell'ambiente ARM64 sono passati 37 gruppi CTest, lo smoke senza `--detect`
e 14 casi DSS/LTA; il worker di produzione rifiuta la radice sintetica.
Sul computer x86_64 sono passati analisi statica, 346 test Flutter, 18 test
Python di confezionamento/selezione JVM e tre regressioni native mirate.

Il pacchetto non è stato installato sul computer: la `.20` x86_64 e i suoi
737 file sono rimasti invariati. Nessuna modifica ai browser o ai permessi
Snap e nessuna prova sulla CIE reale. Pacchetto, checksum, snapshot dei sorgenti
e rapporti restano artefatti locali in `dist/linux-arm64-deb-test` e
`reports/linux-arm64`, esclusi da Git.

## Correzioni native emerse nel porting

Il serializzatore DER ora estrae un byte alla volta senza shift oltre la
larghezza del tipo. Il parser X.509 riconosce il wrapper opzionale `[3]` delle
estensioni, evitando di interpretare la chiave pubblica quando le estensioni
sono assenti. Un test confronta otto intestazioni DER note e tre casi delle
estensioni; i test P7M usano certificati sintetici senza estensioni.
La cattura C++17 del nome del lettore non dipende più da una structured binding.

Prima di una release restano da verificare hardware ARM64 reale, desktop
GNOME/KDE, lettore, funzionalità CIE e browser disponibili sulla distribuzione.
I collaudi software in emulazione non certificano questi aspetti. Il pacchetto
resta locale e non firmato; si applicano i requisiti di [LICENSING.md](LICENSING.md).
