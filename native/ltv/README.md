# Validatore DSS locale condiviso

Worker Java 21 condiviso fra macOS, Windows e Linux x86_64/ARM64. Usa EU DSS 6.5.1,
policy predefinita e livello ARCHIVAL_DATA: DSS/VRI, OCSP/CRL incorporati,
revisioni PDF e rinnovi di marche di archivio PAdES/CAdES. Il middleware C/C++
e la firma con CIE rimangono gli stessi. La coordinazione Dart usa un processo
senza shell, con memoria/output/durata limitati e senza opzioni Java ereditate.

Il helper C++ privato `fetcher/cie_crl_fetch` recupera le CRL HTTP/HTTPS indicate
nei certificati, con massimo 8 URL distinti, 20 secondi, 24 MiB per oggetto e
64 MiB complessivi. Usa lo stesso libcurl/macOS-Windows: TLS e nome host
verificati, nessun proxy ereditato, nessun downgrade HTTPS, controllo degli
indirizzi effettivi delle socket per impedire accessi a reti private/locali.
Nessuna ricerca automatica su archivi Web o invio del documento: i file restano
sul computer. AIA, OCSP online e policy/certificati tramite URL restano disabilitati.
Le CRL vengono autenticate e controllate per emittente, ambito e date prima
dell'uso. Il confronto storico comprende l'accuratezza della marca, le date
di revoca/invalidità e la conservazione dei certificati scaduti. Motivi sconosciuti,
sospensioni ambigue e prove insufficienti rimangono indeterminati. La cache è
limitata alla singola verifica; il controllo dei motivi riguarda tutti i
certificati effettivamente coinvolti, indipendentemente dai callback DSS.
La policy di fiducia, identica sulle due piattaforme, contiene la Root CA
CIE ministeriale, le due CA ufficiali di firma/TSA della PKI Difesa, con URL e
checksum in `native/backend/cie_sign_sdk/trust/difesa/manifest.json`, e le CA
del cacerts Temurin fissato nel manifest. Le SubCA CIE
sono candidati, non ancore. Non si importano radici dal documento e non si
modificano portachiavi, Windows-ROOT o altri archivi del sistema. L'app non
attesta qualificazione eIDAS: non sincronizza le Trusted List europee.

La presenza del profilo BASELINE-LTA non basta: si richiedono TOTAL_PASSED,
processo archivistico PASSED, marche di archivio verificate e profilo tecnico
LTA. Il risultato nativo precedente è separato da questa validazione completa.
LTA non significa validità eterna: dipende da prove, rinnovi e policy applicabile.

Build: `scripts/build_ltv.py --java-home ... --maven ... --base-runtime ...
--output ... --system macos|windows|linux`. Maven scarica le dipendenze da Central;
JAR e runtime sono fissati con SHA-256. `--refresh-dependency-lock` è riservato
all'aggiornamento esplicito delle dipendenze. Sono inclusi JRE privati, senza
installazione, JAR originali separati, sorgenti Maven e avvisi di licenza.
DSS è LGPL-2.1-or-later; i nuovi sorgenti sono BSD-3-Clause. OpenJDK/Temurin
usa GPL-2.0 con Classpath Exception, con licenze in ciascun `jre/*/legal`.
Questi pacchetti sono prototipi privati: una distribuzione pubblica richiede
anche il corrispondente sorgente completo OpenJDK e la verifica degli avvisi.
Provenienza OpenJDK: https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.12.1%2B1
DSS e sorgenti: https://github.com/esig/dss/tree/6.5.1
Documentazione: https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/doc/dss-documentation.html

`LtvSelfTest` genera una PKI sintetica e documenti di prova localmente. Il suo
JAR è fuori dal classpath di produzione; non installa CA e non contiene PIN o
documenti personali. Le radici sintetiche non sono attendibili per Worker.
`HistoricalCrlTest` verifica anche recupero simulato, motivi sconosciuti,
revoche prima/dopo la marca, precisione temporale, CRL alterate/scadute e
retention dei certificati scaduti. `scripts/test_history.py` esegue gli stessi
casi su Mac/Windows e, se richiesto, la verifica reale con il helper incluso.

Linux x86_64/ARM64: JVM Temurin privata, nessuna installazione Java di sistema.
Build, test sintetici e pacchetto `.deb` sono descritti in
[LINUX_DSS_LTA.md](../../docs/LINUX_DSS_LTA.md). La JVM deve corrispondere al runtime nativo; ARM32 non è supportato.
