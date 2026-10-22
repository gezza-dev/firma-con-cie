# Pacchetto di installazione Windows x64

Il pacchetto locale di test del 21 ottobre 2026 include l'app Flutter completa,
runtime MinGW, PDFium, DSS/JVM privata, licenze, componente di accesso ai siti e
Microsoft Visual C++ Redistributable x64. Non è una release pubblica firmata.

## Distribuzione senza strumenti di sviluppo

Il packager crea automaticamente una copia `Release` dentro la directory di
output, senza modificare il runtime di sviluppo o la build Flutter originale.
La policy versionata [release-policy.json](../packaging/windows/release-policy.json)
esclude soltanto percorsi espliciti:

- `cie_native/tests`: eseguibili di regressione, DLL simulate e script Python;
- `cie_native/ltv/tests`: harness Java dei test;
- `cie_native/provenance`: registri di assemblaggio conservati nel report esterno;
- `jawt.lib` e `jvm.lib` della JVM: librerie per il collegamento in compilazione,
  senza rimuovere le DLL corrispondenti.

Tutte le librerie operative, il fetcher CRL, i 50 JAR, la JVM con configurazione,
certificati e testi `legal`, le risorse Flutter/PDFium, i source JAR e gli avvisi
rimangono inclusi. Non si applicano filtri generici ai nomi che contengono
`test` o `source`, né si rimuovono sezioni dai binari già collaudati. Il payload
Web e il suo identificativo rimangono identici.

`build/release-audit.json` elenca hash, dimensioni e motivi delle esclusioni.
Il manifest nativo distribuito elenca solo i file presenti e conserva hash del
manifest originale e della policy; il manifest originale completo è archiviato
nel report di build esterno al bundle. L'aggiornamento rimuove anche i vecchi
file di sviluppo esclusi, usando nomi individuali, senza cancellazioni ricorsive
o wildcard. Eventuali file estranei nelle stesse cartelle vengono conservati.

Misure del pacchetto del 21 ottobre (MB decimali):

| Contenuto | Prima | Dopo |
| --- | ---: | ---: |
| Installer compresso | 175,5 MB | 142,5 MB |
| Cartella Release | 496,9 MB | 381,7 MB |
| File nella cartella Release | 919 | 880 |

Sono esclusi 39 file (115.194.239 byte). I 879 file mantenuti, escluso il solo
manifest nativo aggiornato, sono identici byte per byte: tra questi 648 file di
licenza/avvisi, inclusi quelli della JVM e i sorgenti allegati. Queste misure
riguardano il bundle; il componente di sistema e il prerequisito Microsoft
hanno anche le proprie destinazioni di installazione.

## Installazione e aggiornamento

Avviare `Firma-con-CIE-0.1.0-Windows-x64-Setup.exe` e confermare UAC. App e
componente vengono installati nella stessa sessione amministrativa. Il
prerequisito Microsoft viene eseguito senza un'altra elevazione e senza
riavviare automaticamente Windows. Sono disponibili italiano e inglese.

Le finestre di installazione e disinstallazione seguono il tema chiaro/scuro
di Windows tramite `WizardStyle=modern dynamic` di Inno Setup. La preferenza
viene letta all'avvio: un cambiamento del tema di sistema richiede di riaprire
il programma di installazione o disinstallazione. I temi a contrasto elevato
mantengono la gestione nativa prevista da Inno Setup. La scelta del tema
nell'app rimane indipendente da quella dell'installer.

Non occorrono lettore, CIE o PIN, neppure alla prima installazione. Il helper
registra i 12 ATR completi e le maschere verificati nel middleware ufficiale,
senza contesto PC/SC, enumerazione dei lettori, avvio del servizio Smart Card o
connessione alla carta. [Catalogo, provenienza e migrazione](WINDOWS_CARD_CATALOG.md).
Per un futuro modello non presente nel catalogo serve un aggiornamento
dell'app, non una nuova installazione con la carta sul lettore.

La verifica preliminare controlla payload e conflitti prima della copia
dell'app, senza modificare il registro. Le registrazioni estranee con ATR
sovrapposti non vengono sovrascritte: il conflitto interrompe la configurazione.
La fase finale completa la registrazione con ripristino in caso di errore;
un errore viene riportato come installazione non completata, senza cancellare
gli archivi personali. La riesecuzione dell'installer consente di riprovare.

L'app è in `Program Files\Firma con CIE`; il componente mantiene la propria
cartella immutabile in `Program Files\CIE ID Flutter Prototype\WebToken\<hash>`.
Le vecchie versioni non vengono sovrascritte: possono essere ancora caricate
nei browser. L'installer può chiedere di chiudere Firma con CIE prima di aggiornarla. Il nuovo nome pubblico non cambia l’identificativo dell’installer né gli archivi personali preesistenti.
Il collegamento sul desktop è facoltativo; quello nel menu Start è incluso.
L'avvio a fine installazione è facoltativo e usa il token dell'utente originario.

## Conservazione dei dati

Gli identificativi dell'app e della cache non cambiano. L'installer non importa,
non migra, non riscrive e non elimina dati nei profili utente:

- abbinamenti, chiave locale e certificati Web cifrati rimangono in
  `%LOCALAPPDATA%\it.giancarloezza.CIEID.FlutterPrototype.pairing.v1\cache-v3`;
- impostazioni, preferenze e immagini rimangono in `%APPDATA%\gezza-dev\CIE ID`;
- i certificati dell'utente e le configurazioni dei browser restano conservati.

Gli archivi sono ancora per utente, anche se l'app viene installata per tutti
gli utenti. Confermare UAC con un altro account amministratore non trasferisce
gli abbinamenti a quell'account. L'app non viene avviata automaticamente con
privilegi amministrativi e non richiede UAC durante l'abbinamento: esegue
soltanto `CIE-Web-Setup.exe --check <lettore>`. Se il componente manca, indica
di eseguire l'installer; rimane disponibile la scelta esplicita di procedere
solo per la firma dei documenti. Il completamento Web riusa i dati pubblici
salvati e non installa componenti.

## Disinstallazione

La disinstallazione rimuove le sole registrazioni smart card riconosciute come
appartenenti a questa applicazione, poi i file elencati nel log dell'installer.
Se la rimozione delle registrazioni fallisce, si arresta prima di cancellare
l'app. Abbinamenti, impostazioni, immagini e certificati utente vengono
conservati per una successiva reinstallazione. Non esistono cancellazioni
ricorsive delle cartelle dati. File estranei aggiunti alla cartella di
installazione non vengono eliminati.

I file di un vecchio componente installato separatamente e le versioni
precedenti immutabili possono restare sul disco, senza registrazioni attive:
non vengono cancellati indiscriminatamente, soprattutto se ancora caricati da
un browser. I file installati da questo pacchetto sono gestiti dal suo log;
Windows può richiedere un riavvio se sono ancora in uso.

## Compilazione riproducibile

1. Preparare il runtime e il payload Web come in [WINDOWS_WEB_FIRST_USE.md](WINDOWS_WEB_FIRST_USE.md).
   Per includere il modulo PKCS#11 Windows, compilarlo con
   `scripts/build_windows_pkcs11.py` e passarlo a
   `scripts/package_web_windows.py --pkcs11 <cie_pkcs11.dll>` prima di generare
   il nuovo helper. [Ricetta e ABI](MIDDLEWARE_COMPATIBILITY_UPDATE.md).
2. Compilare il nuovo `CIE-Web-Setup.exe` con il manifest del payload e copiarlo
   in `native/runtime/windows-web-component`. Il payload RSA collaudato resta
   invariato; il helper ora espone `--plan-package`, `--install-package` e
   `--unregister-package`, riservati all'installer elevato; `--plan-package`
   esegue soltanto la verifica preliminare e non richiede elevazione.
   Ricompilare anche `cie_bridge.dll`: `web_cert_store.cpp` incorpora le regole
   di riconoscimento di `setup_policy.h` e `card_catalog.h`. Aggiornare solo il
   helper lascia l'app incapace di riconoscere i nuovi nomi nel registro.
3. Generare i cataloghi, eseguire analisi/test e compilare l'app Windows.
4. Usare Inno Setup 7.1.0 e il `vc_redist.x64.exe` firmato Microsoft fornito da
   Visual Studio Build Tools; il packager verifica la firma del prerequisito.

```powershell
python scripts/generate_l10n.py
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
python scripts/package_windows_installer.py --release build/windows/x64/runner/Release --output dist/windows-installer --iscc <ISCC.exe> --vc-redist <vc_redist.x64.exe> --version 1.0.0
```

Il packager verifica tutti gli hash dei manifest nativo/Web, il legame fra hash
e versione del payload Web, l'assenza di file non elencati nei payload, i file necessari e l'assenza di record personali o
collegamenti nel bundle. Non include le cartelle dati del PC. Produce installer,
SHA-256, manifest dei file e log di compilazione; non installa il prodotto.
Il packager rifiuta un bridge Windows i cui hash di provenienza non coprono le
regole correnti del catalogo. Una ricompilazione del solo bridge su un runtime
esistente è registrata in `artifacts.cie_bridge.dll` con hash del binario,
sorgenti/header e toolchain, senza attribuire la nuova compilazione al backend.

Inno Setup è stato ottenuto dalla [distribuzione ufficiale](https://jrsoftware.org/isdl.php)
e verificato tramite hash dell'asset e firma Authenticode di Pyrsys B.V.
Il [modo amministrativo](https://jrsoftware.org/ishelp/topic_admininstallmode.htm)
è limitato all'installer. Gli avvisi delle dipendenze rimangono inclusi nel
bundle, con il prerequisito Microsoft nella propria distribuzione originale.

## Verifiche e limiti

Le prove usano una build separata dell'installer, con ID distinto, destinazione
temporanea e privilegi utente. Componente e prerequisito sono sostituiti da un
eseguibile sintetico senza PC/SC, registro o accesso agli archivi reali. Il
motore Inno effettivo viene eseguito per prima installazione, aggiornamento,
riesecuzione, fallimento della verifica preliminare, fallimento del componente,
fallimento della rimozione e disinstallazione. Viene verificata la conservazione
di abbinamenti/impostazioni sintetici e dei file estranei.

I test C++ verificano anche il ripristino di tutte le registrazioni precedenti
se un aggiornamento di più modelli fallisce. I test Flutter controllano che la
verifica preceda il PIN, che una configurazione mancante non autentichi la
carta e che il canale invochi solo il controllo, senza installazione/UAC.

Questi test non attestano l'esecuzione UAC dell'installer di produzione né un
nuovo accesso reale dal browser dopo la sua installazione. Tale collaudo rimane
da eseguire personalmente sul PC Windows. Il provider RSA è quello già
collaudato con Chrome, Firefox ed Edge; nessuna nuova firma sulla CIE viene
eseguita durante la preparazione del pacchetto.

Risultati del 21 ottobre: 49 controlli sul ciclo reale dell'installer isolato,
410 controlli del catalogo/registro, 75 della policy setup e 124 del minidriver superati;
215 test Flutter superati, tre test facoltativi saltati e analisi senza problemi.
I 49 controlli includono il rifiuto di un bridge obsoleto, le esclusioni, l'assenza di richieste della carta, la conservazione delle licenze e la
pulizia dei soli vecchi file di test durante l'aggiornamento. Sul bundle ridotto
sono ripetute le prove del bridge per PDF/P7M validi e alterati, percorsi Unicode
e timestamp, i 14 casi DSS/LTA, i 19 casi di revoca storica e i 37 controlli di
rete locale nativa/Java. Gli harness sono esterni al pacchetto e verificati con
gli hash del runtime di sviluppo; DLL, JAR, JVM e fetcher operativi provengono
dalla copia ridotta. Per il pacchetto senza carta sono ricompilati helper e app
(guida italiana/inglese aggiornata); il provider RSA e il backend operativo
restano invariati. I test Flutter e l'analisi sono ripetuti dopo l'aggiornamento.

### Correzione del rilevamento dopo l'installazione

Il primo pacchetto senza carta registrava correttamente i 12 modelli, ma
distribuiva il vecchio bridge MinGW che riconosceva solo il nome storico e i
suffissi esadecimali. `cie_bridge_web_status` restituiva `available:false`.
Il bridge aggiornato restituisce `available:true` sulle stesse registrazioni,
senza lettura della CIE. La prova si ripete sul binario distribuito:

```powershell
python scripts/check_windows_web_component.py --runtime <output>/Release/cie_native --expect-available --report <report>/component.json
```

`--expect-available` si usa solo su un PC dove il componente è già installato;
senza questa opzione la prova riporta anche uno stato assente senza errore.
La funzione chiamata controlla nomi/provider e metadati della DLL, senza
`detect`, abbinamenti, accesso alla cache, PIN o operazioni private.

La correzione locale riusa il backend/adattatore MinGW e il provider Web già
collaudati, ricompilando il solo ponte C ABI con MSVC 14.44 x64. Sono superati
i 13 gruppi CTest del ponte, la suite di 205 controlli sui documenti attraverso
il backend originale e la verifica PDF/P7M/timestamp attraverso il ponte
aggiornato. I dati di abbinamento conservati sono leggibili; il completamento
del certificato pubblico pendente è riuscito senza PIN o carta e senza cambiare
i file di abbinamento/chiave. Il pacchetto precedente resta disponibile soltanto
per confronto diagnostico.

### Primo abbinamento con profilo vuoto

Il flusso Windows pubblica il certificato direttamente dentro
`cie_bridge_enroll`, dopo l'autenticazione e il salvataggio dei dati verificati.
Il callback Dart `publishWebCertificate` su Windows non esegue operazioni:
la pubblicazione nativa deve quindi essere già riuscita al ritorno di `enroll`.

La verifica del 21 ottobre parte da cache vuota, nessun certificato e solo i
nuovi nomi del catalogo. Il test usa `cie_bridge.cpp`, `paired_store.cpp`, la
cache protetta e `web_cert_store.cpp` di produzione. L'autenticazione/SOD è
simulata; il certificato sintetico viene gestito dalle API WinCrypt effettive
in un archivio MY esclusivamente in memoria. Sono sostituite solo l'apertura
dello store di sistema e le osservazioni del componente; nessun fallback allo
store reale è consentito. L'accesso ai lettori è disabilitato nella DLL di test.

Superati 67 controlli in quattro processi con profili nuovi: primo abbinamento,
PIN sintetico errato, errore di pubblicazione e certificato estraneo preesistente.
Il primo abbinamento restituisce immediatamente `webProvisioned:true` e
`systemComponentAvailable:true`, crea una sola identità e verifica certificato,
provider KSP, container e marcatore di proprietà. Non viene mai chiamato
`complete_enrollment`; l'autenticazione simulata avviene una sola volta.
Le prove negative conservano l'abbinamento ove possibile, non sostituiscono
certificati estranei e non ripetono l'autenticazione.

Un test widget Windows con profilo vuoto e callback di pubblicazione privo di
effetti verifica la Home subito dopo il primo abbinamento e dopo la riapertura:
compare «Accesso ai siti configurato», senza «Completa accesso ai siti» o altre
azioni di attivazione. Passano tutti i sette test della suite Windows Web,
i 14 gruppi CTest del ponte e l'analisi Flutter. Sono modificati solo test e
documentazione; la distribuzione corretta dell'app resta invariata.

```powershell
ctest --test-dir .build/validation-bridge-msvc -R windows_first_enrollment_publication --output-on-failure
flutter test --no-pub test/windows_web_setup_test.dart
```

Queste prove verificano il flusso software di un profilo nuovo, non un accesso
fisico con una nuova CIE su un altro computer. Nessuna CIE, certificato personale,
archivio reale, servizio o configurazione del browser viene modificato dai test.

Per ripetere le prove senza reinserire i test nella distribuzione:

```powershell
python scripts/smoke_native.py --runtime <output>/Release/cie_native --test-tools-runtime native/runtime/windows --report <report>/native.json
python scripts/test_ltv.py --runtime <output>/Release/cie_native --test-tools-runtime native/runtime/windows --report <report>/ltv.json
python scripts/test_history.py --runtime <output>/Release/cie_native --test-tools-runtime native/runtime/windows --report <report>/history.json
python scripts/test_network_runtime.py --runtime <output>/Release/cie_native --test-tools-runtime native/runtime/windows --report <report>/network.json
```

Gli errori nella configurazione finale del componente producono un esito
esplicito di configurazione incompleta e il codice d'uscita 20, anche in modalità
silenziosa; l'app non viene proposta per l'avvio a fine installazione in quel caso.
