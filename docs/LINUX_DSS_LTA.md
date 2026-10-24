# DSS/LTA su Linux x86_64 e ARM64

Il validatore locale EU DSS 6.5.1 è disponibile su Linux x86_64 e nella build di test ARM64.
Usa il worker Java condiviso con macOS/Windows e una JVM privata Eclipse
Temurin 21.0.12.1+1. Il `.deb` non richiede Java di sistema e non modifica
`JAVA_HOME`, alternative Java, browser, abbinamenti o archivi di fiducia.
La JVM Linux ARM64 è selezionata separatamente; ARM32 non è supportato.

## Funzionamento

La verifica esamina firme PDF/P7M, certificati, dati di revoca incorporati,
marche temporali e rinnovi di archivio. Il profilo LTA rilevato da solo non
determina un esito positivo: restano obbligatori i controlli di integrità,
fiducia, copertura delle revisioni e sufficienza delle prove.
La policy locale non attesta la qualificazione eIDAS della firma.

Il documento viene elaborato sul computer. Le eventuali CRL sono recuperate
dal trasporto C++ privato con limiti di dimensione, durata e destinazione;
il documento non viene caricato online. AIA e OCSP online nel worker DSS
restano disabilitati. Proxy e credenziali passano attraverso stdin, senza
ereditare opzioni/agenti Java o proxy dall'ambiente. La verifica non richiede
lettore, carta, PIN o PUK e non aggiunge nuove marche al documento.

## Build riproducibile

Usare il JDK `build-linux-x86_64` oppure `build-linux-arm64` e Maven indicati in
`native/ltv/toolchain.lock.json`, verificando gli archivi con SHA-256/SHA-512
prima dell'estrazione. Gli strumenti restano in una cartella privata di
compilazione. Impostare `CIE_JAVA_HOME` alla directory del JDK e
`CIE_MAVEN` all'eseguibile Maven estratto.

In un checkout di build nuovo, nel quale `native/runtime/linux` non esiste:

```sh
python3 scripts/build_native.py --system linux --jobs 2 \
  --dependency-prefix .build/dependencies/linux-x86_64/prefix \
  --output .build/linux-native-base
python3 scripts/build_ltv.py --system linux \
  --java-home "$CIE_JAVA_HOME" --maven "$CIE_MAVEN" \
  --base-runtime .build/linux-native-base --output native/runtime/linux
flutter pub get --enforce-lockfile
flutter build linux --release --no-pub
```

Su Linux ARM64 il prefisso nativo è normalmente
`.build/dependencies/linux-aarch64/prefix`. Per assemblare da un host x86_64
un runtime ARM64 già compilato, aggiungere `--architecture arm64` a
`build_ltv.py`. Lo script confronta l'architettura della JVM con il manifest
del runtime base e rifiuta una combinazione differente. Il worker e i 50 JAR
possono essere riutilizzati solo dopo confronto con i rispettivi hash;
fetcher nativo e JVM devono essere ARM64. `--skip-java-build` richiede che i
prodotti Java e i source JAR siano già presenti nella cache verificata.

Conservare runtime base e output completo in directory distinte; lo script
rifiuta una destinazione esistente. Non usare `--refresh-dependency-lock`
per una normale build. I 50 JAR, il JRE Linux e i relativi hash sono fissati;
il manifest completo comprende worker, JVM, trasporto, fiducia e avvisi.

## Test senza CIE

```sh
python3 scripts/test_ltv_runtime.py -v
python3 scripts/test_ltv.py --runtime native/runtime/linux \
  --report reports/linux-lta.json
python3 scripts/test_history.py --runtime native/runtime/linux \
  --report reports/linux-history.json
python3 scripts/test_network_runtime.py --runtime native/runtime/linux \
  --report reports/linux-network.json
flutter test --no-pub \
  --dart-define="CIE_LTV_RUNTIME=$PWD/native/runtime/linux"
```

Le prove usano documenti e identità sintetici: PDF/CAdES LTA con rinnovi,
certificati/TSA scaduti, marche alterate, revisioni non coperte, radici non
attendibili e revoche storiche. La rete di prova usa solo loopback; nessuna
radice sintetica viene installata. Il test Dart avvia il worker privato
tramite lo stesso codice dell'app, senza Java su PATH. I test nativi del
backend restano separati; lo smoke si esegue senza `--detect`.

## Pacchetto e limiti

`scripts/package_linux_deb.py` include DSS/JVM quando il bundle li contiene.
Controlla l'architettura, include le dipendenze ELF della JVM e conserva
licenze e source JAR disponibili. Esclude sia `tests/` sia `ltv/tests/` e
aggiorna il manifest del runtime distribuito. Il controllo del pacchetto
esegue il worker di produzione dopo l'estrazione in un percorso nuovo,
senza avviare l'app o usare una CIE.

Il pacchetto rimane una build locale di test. Compatibilità con altre
distribuzioni, materiali sorgente OpenJDK e requisiti per la distribuzione
pubblica rimangono descritti in [LINUX_PACKAGE.md](LINUX_PACKAGE.md) e
[LICENSING.md](LICENSING.md). Questa integrazione non realizza un servizio
di conservazione né emissione/rinnovo automatico di marche temporali.
