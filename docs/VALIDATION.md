# Verifiche del prototipo — 18 ottobre 2026

## Stato corrente

La sintesi aggiornata per CIE ID Desktop è in [STATUS.md](STATUS.md).
Le sezioni seguenti conservano il diario cronologico delle prove: indicazioni
di funzionalità ancora da verificare si riferiscono alla data della singola voce.
I percorsi locali dei vecchi artefatti sono esempi, non file distribuiti.

## UX2: Home automatica e abbinamento unico

Implementazione condivisa di riconoscimento automatico, ciclo di vita,
abbinamento singolo e recupero/rimozione per fasi. Nuove ABI additive v2;
nessuna modifica al contratto delle firme CTK già collaudate. L’estensione
0.1.11 incorpora il motore aggiornato; il funzionamento reale della nuova
procedura non è ancora collaudato.

- 73 test Flutter complessivi superati, analisi senza problemi. Nuovi test con backend simulato: Home su macOS/Windows,
  cancellazione/pausa del monitor, dati vecchi, recupero dopo riavvio senza
  autenticazione, esito PIN negativo senza ritento, rimozione parziale e
  diagnostica priva di identità/certificati/segreti. Analisi e suite completa
  registrate nei log `.build/ux2-{analyze,flutter-tests}.log`.
- 20 gruppi CTest macOS superati. I due nuovi gruppi verificano politiche di
  osservazione/record e confini ABI dell’abbinamento unico con archivi in memoria.
  Nessun uso dell’archivio reale o comando sulla CIE in questi test.
- Backend Windows x64 compilato dalle stesse sorgenti; nuova esecuzione sul PC
  e build Flutter Windows da ripetere successivamente. Compilare non dimostra
  registrazione/attivazione o funzionamento KSP/browser.
- Da collaudare con l’utente: tempi/occupazione del lettore, nuovo abbinamento
  con un solo PIN, persistenza dei dati pubblici, nome nell’anteprima e nel PDF,
  recupero della pubblicazione e rimozione completa sui due sistemi, login
  Safari dopo abbinamento e login con app chiusa. Cambio PIN/Sblocco Carta rinviati.

Percorsi della build e verifiche finali nel rapporto locale
`reports/ux2-integration-20261018.json`.

## UX1: navigazione e nome CIE nel segno PAdES

Menu, titoli, Indietro/Concludi, stato delle operazioni e documenti usano codice
Dart condiviso; grafica Flutter conservata. Informazioni contiene versione,
licenze e dettagli tecnici. Il backend condiviso ricava il Nome e Cognome dal
certificato della CIE già autenticata per la firma, senza un secondo VERIFY.
Il nome dell’anteprima è un segnaposto fino alla firma.

- `flutter analyze`: nessun problema; 61 test Flutter superati, incluse varianti
  macOS/Windows per navigazione, cancellazione PIN e stato dei documenti.
- 18 gruppi CTest macOS superati; 108 controlli documentali comprendono lettura
  rigorosa di givenName/surname, rifiuto di dati mancanti o ambigui, quattro
  rotazioni PDF, testo visibile e immagine con didascalia, verifica CMS indipendente.
  Identità solo sintetiche, con accenti e apostrofi, nessun certificato installato.
- Backend Windows x64 compilato con MinGW dalle stesse sorgenti nella VM Linux;
  questa è una prova di compilazione, non di esecuzione sul PC Windows.
- Bundle macOS Universal con runtime e CryptoTokenKit incorporati, firmato Apple
  Development e verificato con codesign. Versione estensione 0.1.10, logica CTK
  invariata rispetto alla 0.1.9 collaudata con Safari. Controllo GUI dei nuovi nomi
  e delle pagine Informazioni/Firma Elettronica/Verifica Firma.
- Da eseguire: firma grafica reale sui due sistemi, controllo del Nome e Cognome
  nel PDF prodotto, nuova build/esecuzione Windows. Non è stata usata la CIE
  per questo collaudo; Cambio PIN e Sblocco Carta reali restano rinviati.

Log locali `.build/ux1-{flutter-tests,analyze,ctest,windows-build,app-build}.log`;
rapporto sintetico `reports/ux1-integration-20261018.json`. Il piano dei blocchi
successivi è in [FEATURE_PARITY.md](FEATURE_PARITY.md).

## Accesso ai siti: integrazione sperimentale

Motore C ABI condiviso, estensione CryptoTokenKit macOS e minidriver Windows
v7 separati dall’app pubblicata. Configurazione del certificato pubblico
nell’app, firma locale tramite componente di sistema e rimozione della sola
configurazione del prototipo. Nessuna modifica alla cache PKCS#11 legacy.
Dettagli e limiti: [WEB_AUTHENTICATION.md](WEB_AUTHENTICATION.md).

- 57 test Flutter superati; analisi senza problemi.
- 18 gruppi CTest macOS superati, inclusi policy DigestInfo, ABI/trasporto,
  firma RSA sintetica e configurazione Web con adattatore/archivio fittizi.
  Il nuovo gruppo di 110 controlli verifica il legame fra richiesta e risultato,
  consumo singolo, rifiuto delle richieste mutate e dei tentativi ripetuti.
- Bundle macOS Universal compilato e firmato Apple Development, con estensione
  incorporata e firma verificata. Avvio GUI e rilevamento CIE reale riusciti.
- Il preflight nativo legge l’identificativo senza PIN; la lettura completa del
  certificato richiede la configurazione autenticata nell’app.
- Windows: test eseguiti sul PC, analisi e 57 test Flutter superati; nuova Release
  separata compilata. Minidriver MSVC con CPDK ufficiale: 27 controlli isolati;
  archivio certificati: 25; ponte Web sintetico: 10; conflitto MY: 5;
  regressione documenti: 90. Nessuna registrazione o operazione sulla CIE.
- Corretto un difetto emerso nel test Windows: MY può unificare copie dello
  stesso DER. Ora una copia con associazione estranea causa il rifiuto prima
  delle scritture. Le nuove aperture dell’archivio verificano la preservazione.
- macOS: configurazione reale del certificato pubblico, persistenza, scoperta
  del token fisico e riferimento alla chiave `SecKey` verificati. Il certificato
  passa da un App Group dedicato, separato dai dati PIN, ed è ricontrollato
  rispetto alla carta prima di pubblicare l’identità.
- **Firma locale reale tramite CryptoTokenKit riuscita**, confermata dall’utente
  e dai log del 17 ottobre: autenticazione e controllo del certificato completati,
  firma calcolata/verificata nella stessa transazione e consegna singola per
  la richiesta originale. La GUI verifica nuovamente il risultato tramite
  Security.framework e mostra «Firma della richiesta locale verificata tramite
  CryptoTokenKit». Il PIN è stato inserito dall’utente nella finestra di macOS;
  nessun PIN è stato inserito da strumenti automatici.

La correzione esegue autenticazione e firma nella stessa transazione sensibile:
la precedente chiusura della transazione tra le due callback perdeva il contesto,
anche con PIN corretto. La callback successiva può ritirare soltanto il risultato
verificato della stessa richiesta, una sola volta. Nessun PIN viene conservato
per autenticare nuovamente dopo un errore. Le transazioni esplicite demandano
la selezione MF/IAS/CIE al backend comune; il filtro/preselezione automatica AID
che impediva il funzionamento su questa carta è stato eliminato.

La firma locale tramite CryptoTokenKit è collaudata su macOS Apple Silicon.
La prova reale di login con Safari 27.0.1 (browser predefinito) sul portale
ufficiale CIE ha restituito `No_client_certificate` dopo che l’utente ha
completato la finestra PIN. Il prototipo è stato effettivamente chiamato, ma nei
log non è osservata la conclusione di una firma per questa richiesta browser.
Non è dimostrato un PIN errato né è ancora isolata la causa. Nuove richieste
normali e in finestra privata ritornano immediatamente allo stesso errore,
senza una nuova finestra PIN. Una sonda pubblica senza certificato client
conferma TLS 1.2 e algoritmi RSA SHA-256/384/512 accettati dal servizio; nessuna
impostazione TLS, fiducia o preferenza di identità è stata modificata.
Dopo il riavvio e la riconfigurazione pulita del solo certificato pubblico,
Safari mostra una sola identità CIE, appartenente al prototipo. Alle 20:39 del
17 ottobre i log confermano autenticazione, verifica del certificato, calcolo e
verifica della prima firma browser e consegna del risultato. Le richieste
successive vengono però rifiutate con codice `-5` e «Sessione di autenticazione
terminata»: lo stato del driver è terminale dopo una sola richiesta per
`TKTokenSession`. Safari termina con un errore di connessione sicura. L’utente
riferisce una pagina intermedia relativa al livello 3; non è confermato il
completamento della prima connessione TLS né dell’accesso al portale. Occorre
correggere la gestione delle richieste successive senza conservare il PIN o
ripetere automaticamente una verifica PIN fallita.

La build successiva 0.1.8 implementa richieste multiple nello stesso contesto
carta autenticato, senza nuovo VERIFY. Il contesto viene controllato dentro
ogni transazione, senza ricrearlo silenziosamente se è perso. I test verificano
cinque richieste successive, autorizzazioni preventive del browser e arresto
su rimozione, contesto estraneo, errore o tentativo di riautenticazione.
308 controlli di stato/richiesta e tutti i 18 gruppi CTest sono riusciti.
Estensione Universal e bundle verificati con Apple Development; collaudo
Safari 0.1.8: raggiunta la pagina di consenso al rilascio attributi per il
livello 3; la prima autenticazione/certificato è accettata dal portale, ma il
contesto carta è perso prima delle richieste successive. Nessun VERIFY ripetuto.
La build 0.1.9 mantiene la transazione sensibile fra le callback, con scadenza
inattiva di 30 secondi serializzata con le operazioni e rilascio al primo errore.
Tutti i 18 gruppi CTest sono passati nuovamente; build Universal firmata e
verificata. **Collaudo Safari 0.1.9 riuscito** sul portale ufficiale CIE:
alle 20:54:42 i log confermano l’autenticazione, alle 20:54:43 la prima firma e
alle 20:54:46 la firma successiva senza nuovo VERIFY; l’utente conferma l’ingresso
nell’area personale dopo il consenso al rilascio attributi. Alle 20:55:18 è
osservato il rilascio della transazione inattiva. Nessun PIN è stato salvato o
inserito dall’automazione. Nessun dato dell’area personale è stato letto.

La firma locale e il login al portale CIE con Safari sono convalidati su questo Mac Apple Silicon; altri siti/browser e Windows restano prove separate.
Rapporto locale: `reports/web-browser-macos-20261017.json` (senza credenziali,
certificati personali o URL di sessione). La firma tramite KSP Windows rimane
da collaudare.
Il supporto iniziale è RSA-2048 PKCS#1 v1.5 SHA-256/384/512; RSA-PSS e
la compatibilità TLS 1.3 non sono implementati. Registrazione Windows e firma
Microsoft del minidriver richiedono ulteriori verifiche. Non sono state
modificate le policy di sicurezza. Le preferenze delle sole due estensioni CIE
precedenti e le registrazioni delle loro copie di build, temporaneamente escluse
con consenso dell’utente durante la prova di priorità, sono state ripristinate (produzione: default; sviluppo: use).
Cambio PIN e Sblocco Carta reali restano rinviati.

## Abbinamento e PIN parziale

Implementati abbinamento con PIN completo, elenco delle CIE, disabbinamento
singolo/completo e firma con ultime quattro cifre. Prefisso nel Portachiavi macOS
o Gestione credenziali Windows; nessun file PIN o accesso alla cache legacy.
Dettagli: [PAIRING.md](PAIRING.md).

- 52 test Flutter e analisi senza problemi, 13 gruppi CTest macOS superati.
- 25 controlli del ponte con adattatore/archivio sintetici, 7 controlli SOD su
  dati alterati/mancanti/duplicati e 7 prove Portachiavi in namespace distinto,
  con rimozione dei record di test.
- Prova FFI Dart→nativo: abbinamento, firma con PIN parziale e disabbinamento
  sintetici riusciti, senza accesso alle credenziali di produzione.
- Prima prova reale Mac fallita; riprodotto un errore di lettura identificativo
  nella preparazione, senza alcun PIN. Corretta la transazione PC/SC: connessione
  condivisa e transazione dopo il reset iniziale, nessun reinvio degli APDU.
  Il preflight corretto IAS/DAPP e layout SOD passa sulla CIE reale senza PIN.
  I messaggi distinguono le fasi precedenti al VERIFY e quelle SOD successive.
- La verifica DG aggiuntiva rifiuta le incongruenze che il verificatore legacy
  SHA-256 stampava soltanto; la verifica crittografica IAS resta obbligatoria.
- Nuovo bundle macOS Universal Apple Development in `macos-pairing`, separato
  dalla release pubblicata. Windows cross-compilato dalle stesse 517 impronte
  sorgenti; 19 file Dart comuni. Collaudo sul PC del kit corretto completato dopo la correzione del caricamento
  DLL nei soli test Python; le librerie e i sorgenti Dart non cambiano.

Prove reali macOS completate: abbinamento con PIN completo, verifica SOD e
persistenza dopo riavvio, firme PAdES e CAdES con le sole ultime quattro cifre.
Entrambi i documenti superano la verifica CMS indipendente OpenSSL, la verifica
nativa e il controllo corrente di catena/revoca. Il contenuto estratto dal P7M
coincide con il documento originale. Non sono presenti marche attendibili:
la validità storica resta indeterminata. I documenti firmati restano fuori dal
repository, in una cartella locale privata.

Windows: 25 controlli pairing, 7 SOD, 7 Gestione credenziali, 32 workflow PIN
sintetici, regressione ABI e test documentali/cofirma/rete superati. La Release
finale è ricompilata; i 52 test Flutter e analyzer pulito sono riutilizzati da
sorgenti Dart/test/configurazioni identici, confrontati con hash. GUI Carta,
aggiornamento elenco senza rilevamento, guida e impostazioni collaudati. Una
cattura iniziale bianca si risolve con ridisegno della finestra; nessuna azione
basata su coordinate non visibili. Dati applicativi e proxy iniziali ripristinati,
13 progetti precedenti e 4 documenti preservati, record di test rimossi. Questa
fase software non usa la carta; le successive prove reali sono descritte sotto.
Rapporti Windows: `reports/pairing-windows-summary.json` e
`reports/pairing-test-harness-patch.json`.

Prove reali Windows completate e confermate dall’utente: abbinamento persistente
al riavvio, firme PDF/P7M con PIN parziale e integrità confermata da OpenSSL e
backend. La verifica successiva riferita dalla chat Windows conferma catena
attendibile e firmatario/catena non revocati; i file rimangono invariati. Senza
marca temporale attendibile la validità storica resta indeterminata.
Riepilogo: `reports/pairing-real-windows-confirmation.json`.

Le prove reali Cambio PIN/Sblocco Carta restano
rinviate. Rapporto: `reports/pairing-integration-20261017.json`.


## Impostazioni, diagnostica, proxy e Assistenza

Nuovo bundle macOS Universal Apple Development separato in
`/percorso/Builds/CIE-ID/macos-settings/CIE ID Flutter Prototype.app`.

- 48 test Flutter superati e analisi Dart senza problemi. La raccolta diagnostica
  è inizialmente disattivata; i test controllano l’elenco esplicito dei campi,
  l’assenza di dati sensibili, il limite di 200 eventi, la persistenza della sola
  configurazione non sensibile e il rifiuto di directory/file tramite symlink.
- 11 gruppi CTest macOS superati. Il ponte verifica/firma accetta configurazioni
  per singola chiamata, senza ereditare il proxy delle precedenti. Configurazioni
  non valide sono rifiutate prima del firmatario e i buffer vengono cancellati.
- 37 controlli di rete native/Java su loopback superati: proxy esplicito,
  autenticazione sintetica, rispetto della scelta anche con NO_PROXY, HEAD,
  rifiuto del fallback diretto, destinazioni locali e redirect bloccati, TLS
  richiesto e inoltro della configurazione tramite stdin fino al recupero CRL.
- Suite DSS/LTA 14/14 superata, con rifiuto della radice sintetica. Le librerie
  del trasporto e il worker usano le stesse sorgenti sui due sistemi; 509
  fingerprint nativi/script coincidono, con 18 file Dart condivisi. I manifest
  verificano 902 file runtime macOS e 707 Windows prima della firma del bundle.
- GUI macOS: Assistenza sotto Guida, contatti e orari leggibili scorrendo, FAQ
  aperte all’URL esatto nel browser predefinito; HEAD diretto HTTP 200 in 420 ms;
  proxy locale non disponibile segnalato in 14 ms senza tentativo diretto.
  Rapporto JSON esportato dal dialogo nativo, privo di host, credenziali e percorsi.
  Dopo il riavvio restano host/porta/livello ma non utente/password. Ripristino
  rete/diagnostica riuscito, eventi cancellati e preferenze firma intatte.
  Fixture P7M con tre firme sintetiche ancora integra; fiducia e prove storiche
  rimangono indeterminate. Provato anche il blocco su JSON impostazioni corrotto
  e il recupero tramite ripristino.

Sul PC PC Windows di collaudo sono superati 48 test Flutter, analisi Dart, regressioni
native, 14 casi DSS/LTA e 37 controlli di rete. La Release è compilata e il
collaudo grafico Assistenza/Impostazioni è completato: FAQ nell’URL esatto in
Chrome predefinito, HEAD diretto HTTP 200, errore del proxy locale, esportazione
JSON filtrata, persistenza senza credenziali e ripristino con preferenze firma
identiche. L’assenza di fallback diretto è verificata dai test loopback; durante
la prova GUI non sono stati misurati i conteggi delle richieste. Le tre firme
sintetiche P7M mantengono l’integrità; fiducia e validità storica restano
indeterminate. Dati applicativi iniziali ripristinati, app chiusa e proxy di
sistema invariato. Verificati 509 fingerprint nativi, 18 file Dart e 707 file
runtime in ciascuna delle due copie Windows; preservati gli undici progetti
precedenti e i documenti originali. Rapporto:
`reports/settings-assistance-windows-summary.json`.
Le build restano di sviluppo; nessuna release del prototipo viene pubblicata.
Il collaudo non include proxy aziendali reali, PAC/NTLM o esecuzione Intel hardware
sul Mac. Nessun rilevamento CIE, autenticazione, firma reale o modifica PIN/PUK
in questo blocco. Le prove reali di Cambio PIN e Sblocco Carta restano rinviate.
Dettagli: [impostazioni condivise](SETTINGS_DIAGNOSTICS_PROXY.md).
Report locale: `reports/settings-assistance-integration-20261017.json`.

## Cofirma P7M, guida inclusa e preferenze

Bundle macOS Universal Apple Development separato in
`/percorso/Builds/CIE-ID/macos-cosign-preferences/CIE ID Flutter Prototype.app`.

- 40 test Flutter superati e analisi Dart senza problemi. I test comprendono
  preferenze persistenti, percorsi Unicode, copia/rimozione dell'immagine senza
  modificare l'originale, guida offline, collegamenti e selezione della cofirma.
- 10 gruppi CTest macOS superati, inclusi 40 controlli della cofirma e i 90
  controlli dei flussi documentali. Il campione con due firme SHA-384/SHA-256,
  attributo non firmato e CRL incorporata riceve una terza firma con lo stesso
  SDK; tutte le firme restano crittograficamente valide. Test anche RSA/SHA-512,
  PEM/Base64, input alterati/detached, mancata sovrascrittura e assenza di retry.
- I controlli preliminari verificano anche la compatibilità del contenitore con
  il verificatore SDK prima del PIN; la fiducia non viene dedotta dall'integrità.
- GUI macOS: guida e licenze native consultabili, link ufficiale aperto nel
  browser predefinito, formato e immagine conservati dopo riavvio, immagine
  proposta nelle nuove anteprime, rimozione e ripristino verificati. Corretto
  il nome P7M nel salvataggio nativo macOS per evitare l'estensione doppia.
- macOS e Windows condividono gli stessi 503 fingerprint nativi/script e gli
  stessi sorgenti Dart. Il runtime finale è verificato tramite manifest SHA-256.
- Suite DSS/LTA: 14 casi superati e rifiuto delle radici sintetiche con la policy
  di produzione; altre tre esecuzioni indipendenti superate. Corretto un test
  intermittente che poteva sostituire `a` con `A` nell'esadecimale PDF senza
  alterare il token decodificato. Ora cambia sempre un valore numerico e controlla
  che il token sia diverso. Il worker e le dipendenze di produzione sono identici.

Windows: gli stessi 40 test Flutter e i 40 controlli nativi di cofirma sono
superati, insieme ai 90 controlli documentali e alle regressioni native.
La suite LTV corretta passa 14/14 e altre tre esecuzioni 14/14, rifiutando sempre
la marca alterata e la radice sintetica. GUI: formato e immagine persistono
dopo riavvio; nuova anteprima con immagine, cofirma automatica e destinazione
P7M, verifica/estrazione sintetica, rimozione, ripristino, guida, link nel browser
predefinito e licenze verificati. Le preferenze precedenti al QA sono ripristinate. Build Release e ultimo avvio
Windows superati, con 705 hash verificati in ciascuna delle tre copie del runtime
e 503 fingerprint nativi/script corrispondenti.

Nessuna autenticazione CIE o nuova firma reale durante questo blocco. La cofirma con CIE reale resta da provare su entrambi i sistemi;
Cambio PIN e Sblocco Carta rimangono rinviati dall'utente. Linux non collaudato.
Dettagli: [cofirma, guida e preferenze](COSIGN_GUIDE_PREFERENCES.md).
Report locale: `reports/cosign-guide-preferences-integration-20261017.json`.

## Integrazione dei flussi documentali Flutter

Nuovo bundle macOS Universal Apple Development in
`/percorso/Builds/CIE-ID/macos-documents/CIE ID Flutter Prototype.app`.
È separato dall'app pubblicata e dalle precedenti build di prova.

- 32 test Flutter superati; analisi Dart senza problemi.
- 9 gruppi CTest macOS superati; il nuovo test documentale esegue 90 controlli
  senza carta. Quattro PDF con firme sintetiche, rotazioni 0/90/180/270 e
  CropBox decentrata hanno integrità crittografica valida. Un controllo raster
  indipendente PDFium conferma posizione e orientamento dei colori.
- Corretta nell'SDK la trasformazione dell'origine della CropBox ruotata:
  il solo scambio di larghezza/altezza non preservava la posizione del segno.
- ABI: parametri invalidi rifiutati prima del firmatario, PIN cancellato,
  nessun retry e nessuna sovrascrittura. I test UI verificano anche che un drop
  durante un'operazione non cambi il documento né avvii una seconda firma.
- GUI macOS: rendering di testo/grafica PDF, scelta pagina, spostamento,
  PNG personalizzato, conferma e annullamento; estrazione P7M salvata dal dialogo
  nativo e confrontata byte per byte con il PDF originale.
- Backend Windows x64 ricompilato dagli stessi 500 fingerprint nativi/script.
  Kit trasferito e verificato sul PC PC Windows di collaudo. I 90 controlli documentali,
  i 32 test Flutter, l'analisi e le regressioni native/LTV sono superati;
  GUI Windows verificata per anteprima, pagina, posizione tramite clic, PNG,
  conferma/annullamento e pulizia temporanei. Verifica P7M ed estrazione GUI
  riuscite: byte del PDF estratto identici al contenuto originale. Nessuna DLL
  mancante sul PC, nessuna modifica ai sorgenti condivisi importati.
- Dipendenze dell'anteprima fissate in `native/preview/pdfium.lock.json`, checksum
  e avvisi conservati in `LICENSES/preview`. Firma profonda e hash del runtime
  macOS verificati. Runner, librerie CIE e PDFium includono ARM64 e x86_64;
  l'esecuzione Intel hardware resta da provare.

Non sono state eseguite autenticazioni, nuove firme reali o modifiche PIN/PUK.
Le nuove firme grafiche richiedono ancora collaudo con CIE reale sui due sistemi.
Il drop è coperto dai test software; manca la prova manuale da Finder/Esplora file.
Il trascinamento del riquadro non ha prodotto uno spostamento osservabile con
l’automazione sui due sistemi: causa non stabilita, da provare con mouse reale.
Il posizionamento tramite clic e i controlli della pagina funzionano. La scelta
JPEG non è stata provata manualmente in questa sessione. Linux resta da collaudare per queste funzioni.
Dettagli: [flussi documentali](DOCUMENT_WORKFLOWS.md),
[confronto funzionale e sequenza successiva](FEATURE_PARITY.md).
Report locale: `reports/document-integration-20261017.json`.

## Rilevamento pubblico della carta ottimizzato

Il backend condiviso corretto è ora provato con la CIE reale sia su Mac sia su
Windows. Sul Mac con miniLector, il confronto ripetuto porta la mediana del
rilevamento completo via ABI da 2.015,360 a 625,687 ms (−69,0%), con 12/12
letture valide per versione. L'identificativo coincide con quello precedente
e la GUI della build corretta riconosce la CIE dopo un solo clic.

Il percorso seleziona prima MF/IAS e poi CIE: la selezione diretta della prima
variante falliva su Windows con `6A82`. Evita reset e PAN e usa una transazione
PC/SC per i dati pubblici. Nessuna autenticazione o modifica PIN/PUK. Le prime
misure Mac della variante diretta (1.784 → 547 ms) restano separate da queste
nuove prove del codice MF/IAS condiviso definitivo.

Otto gruppi CTest passano, compresi 37 controlli della policy/navigazione di identificazione
e la regressione PIN/PUK. Nuovo bundle Universal Apple Development verificato,
579 hash del runtime firmato controllati. Windows x64 compila dagli stessi
494 fingerprint nativi/script. Sul PC Windows la correzione riconosce la CIE in
12/12 prove: mediana 223,756 → 72,864 ms (−67,4%), con 37 controlli identificazione
e 32 casi PIN/PUK superati. Otto gruppi CTest ripetuti sul Mac passano; le
nuove misure Mac usano lo stesso metodo di tre processi alternati per versione
e quattro rilevamenti ciascuno. Caricamento librerie misurato separatamente,
prima inizializzazione USB e latenza GUI escluse. Dettagli e limiti:
[CARD_DETECTION.md](CARD_DETECTION.md).

Collaudo Windows concluso: analisi Dart pulita, 26 test Flutter, 78 controlli di
sicurezza, SDK/handle e build Release passano; anche la GUI riconosce la CIE
dopo un solo clic. I 567 hash runtime sono verificati nel progetto e nella
Release; i 378 file LTV sono invariati. Il caricamento delle librerie è separato
(mediane 86,626 e 91,557 ms, tre misure per versione). Il fallimento iniziale e
un errore transitorio di pulizia smoke, seguito da ripetizione riuscita,
restano documentati. Nessuna autenticazione/firma/modifica PIN/PUK reale.
Riepilogo locale: `reports/windows-detection-validation-summary.json`.
Prova Mac aggiornata: `reports/macos-detection-validation-summary.json`.

## Cambio PIN e sblocco tramite PUK

Il ponte C e l'adattatore espongono entrambe le operazioni alle nuove pagine
Flutter con lo stesso codice su macOS e Windows. Controllo dell'identità prima
dell'autenticazione, connessione esclusiva e callback dedicato senza reinvio
degli APDU. Una risposta persa durante la modifica mantiene l'esito indeterminato.
Le capability permettono alla GUI di riconoscere un runtime precedente.

macOS ARM64: sette gruppi CTest, 32 casi PIN/PUK sintetici, confini ABI,
26 test Flutter, analisi pulita e bundle Universal Apple Development verificati.
Le due pagine sono state ispezionate nella GUI; campi protetti e messaggi sono
leggibili. I 19 casi storici e circolare.pdf conservano gli esiti precedenti.
I 492 fingerprint nativi/script coincidono tra le due build; worker DSS, JVM,
dipendenze e archivio di fiducia sono invariati. Windows x64: 32 casi PIN/PUK, confini ABI, 78 controlli di sicurezza,
26 test Flutter, analisi e build Release superati. Le due pagine si aprono
e scorrono correttamente; senza carta selezionata la modifica è disabilitata.
Progetti e documenti precedenti sono preservati. Il riepilogo locale registra
le evidenze del PC effettivo.

Nessuna autenticazione PIN/PUK o modifica fisica della CIE è stata eseguita da
queste prove. Il collaudo hardware richiede l'inserimento personale delle
credenziali nell'app; non si blocca intenzionalmente la carta per provare il PUK.
Procedura: [PIN_PUK.md](PIN_PUK.md). Report:
`reports/pin-puk-integration-summary.json`, `reports/macos-pin-puk-automated.json`.

## Recupero CRL e validazione storica integrati

Il worker condiviso usa il trasporto HTTP C++ privato per le CRL indicate dai
certificati, con budget e limiti, TLS verificato e blocco degli indirizzi privati
effettivamente contattati. I 19 nuovi casi sintetici comprendono rete assente,
CRL alterate/scadute/non pertinenti, motivo sconosciuto sul firmatario o sulla
TSA, revoche prima/dopo la marca, accuratezza temporale, invalidityDate e
conservazione dei certificati scaduti. Non vengono installate radici di prova.

Nel PDF reale la prima firma può avere storico `passed` alla marca del
10 dicembre 2020; la seconda mantiene `indeterminate / revocation_reason_unknown`
per il motivo 7. Il risultato LTA rimane `no_archive_data` per entrambe.
Il risultato grezzo DSS non sostituisce questo verdetto. Le sezioni successive
conservano la cronologia delle prove precedenti, incluso il vecchio worker offline.

Prove effettive su macOS ARM64 e Windows x64: 19 casi storici, 14 casi DSS/LTA,
21 test Flutter, analisi statica e compilazione Release superati. Il PDF reale
ottiene su entrambi due CRL scaricate senza errori e gli esiti descritti sopra;
l'originale rimane invariato. I 489 fingerprint dei sorgenti nativi/script e
il JAR del worker coincidono. Sul Mac passano anche i sei gruppi CTest e la
verifica dei PDF/P7M CIE già firmati, con fiducia e revoca dell'intera catena.
Il bundle Mac Universal è firmato Apple Development; Intel è compilato,
mentre l'esecuzione Mac di questa prova riguarda ARM64.

La prima esecuzione Windows è conservata come risultato negativo: il filtro
dell'ambiente Python perdeva `SYSTEMROOT` a causa delle maiuscole, impedendo
la risoluzione DNS nei processi figli. Il filtro condiviso Dart e gli strumenti
di test ora conservano le variabili di sistema senza distinzione di maiuscole;
agenti/opzioni Java e proxy ereditati restano esclusi. Il nuovo test copre
questa regressione. Non sono state disabilitate verifiche TLS o installate CA.
Rapporti locali: `reports/crl-history-integration-summary.json`,
`reports/macos-crl-history-integrated.json` e i corrispondenti report Windows.

## Catene TSA PKI Difesa e resilienza della revoca CIE

Sono incluse come ancore esplicite dell'app le due CA di firma/TSA scaricate dal
[portale ufficiale PKI Difesa](https://pki.difesa.it/IT/default.aspx). Provenienza,
confronto con le impronte pubblicate, verifica delle self-signature e SHA-256
sono registrati in `native/backend/cie_sign_sdk/trust/difesa/manifest.json`.
Il catalogo e i due PEM sono comuni al motore C++ e al worker DSS Mac/Windows.
Non si installano CA nel sistema né si deduce fiducia dai certificati del PDF.

Sul Mac le due marche del PDF reale superano impronta, firma, ESS, EKU e catena
TSA alla data del token; le date rilevate sono quelle del 10 dicembre 2020.
OpenSSL OCSP conferma indipendentemente lo stato attuale non revocato della TSA.
Il primo firmatario è scaduto oggi; il secondo ha catena PKI Difesa attendibile
ma è revocato dal 16 gennaio 2024 alle 12:13:12 UTC, confermato da una risposta
OCSP autenticata. Questo non prova da solo la validità o invalidità storica nel
2020. Lo storico resta indeterminato e nel documento non sono presenti prove LTA.
Il worker DSS offline passa da `NO_CERTIFICATE_CHAIN_FOUND` a
`CERTIFICATE_CHAIN_GENERAL_FAILURE`: non dispone delle prove archivistiche di
revoca richieste. Non si inseriscono risposte del 2026 come prove del 2020.

Il precedente `unknown` della catena CIE Windows non è più riproducibile anche
prima di cambiare codice. La CRL Root è scaricata da tre client, compreso il
libcurl della DLL, e passa firma, emittente e validità. Una causa transitoria è
plausibile, ma non è stata dimostrata la causa esatta. `Revocation.cpp` ora ritenta
una sola volta gli errori transitori del download CRL, dentro gli stessi limiti
di tempo/richieste e dimensione. TLS non autenticato, CRL scadute/contraffatte e
HTTP permanenti non vengono promossi a stato buono o ritentati come guasti di rete.

macOS ARM64: sei gruppi CTest, 77 controlli di sicurezza, SDK/handle, 17 test
Flutter, analisi pulita e 14 casi DSS/LTA superati. La GUI Universal, firmata
Apple Development, mostra entrambe le catene TSA verificate, la scadenza del
primo firmatario e la revoca del secondo. I PDF/P7M CIE mantengono integrità,
fiducia e revoca dell'intera catena positive. Intel compilato, non eseguito.
Windows x64: gli stessi 77 controlli di sicurezza, SDK/handle, 17 test Flutter,
analisi e 14 casi DSS/LTA passano; build Release e GUI verificate. I PDF/P7M CIE
passano `--require-trust`, con revoca GOOD di firmatario e catena. Il probe dello
stesso SDK accetta la CRL Root con stato 0. I 485 fingerprint di sorgenti/script
e i 557 file runtime, incluse le due nuove CA, sono verificati. Gli esiti del
PDF reale coincidono col Mac e lo snapshot identico è rimosso a fine controllo.
Non è dimostrata la causa esatta del precedente guasto transitorio.

Rapporto locale: `reports/authority-chain-summary.json`. I rapporti delle prove
precedenti sotto sono conservati e descrivono le rispettive revisioni.

## Correzione delle estensioni nelle marche temporali

Il motore C++ condiviso ammette le estensioni TSTInfo non critiche senza usarle
per concedere fiducia o revoca. Le firme dei token proteggono anche le
estensioni: i byte alterati sono rifiutati. Estensioni duplicate danno errore;
quelle critiche non supportate, le versioni e gli algoritmi non supportati
restano indeterminati con motivazione distinta dalla struttura malformata.
La GUI distingue la catena TSA non ricostruibile da una marca non valida.

Sul Mac passano sei gruppi CTest, 69 controlli di sicurezza, SDK/handle,
17 test Flutter e l'analisi statica. Passano anche i 14 casi DSS/LTA con worker,
50 JAR, JVM e archivio di fiducia invariati. Il PDF reale mantiene le due firme
integre; le marche passano da `invalid / timestamp_malformed_or_unsupported` a
`indeterminate / tsa_chain_not_trusted_at_timestamp`. Nessuna catena non
attendibile viene promossa e non vengono inventate prove LTA mancanti.

Il nuovo bundle Mac è Universal e firmato Apple Development; ARM64 eseguito,
Intel solo compilato. Le build precedenti sono conservate. Il pacchetto Windows
contiene i sorgenti condivisi, il runtime aggiornato e le stesse dipendenze DSS.
Su Windows passano i 69 controlli di sicurezza, i 17 test Flutter, l’analisi
statica e i 14 casi DSS/LTA; build Release riuscita. La verifica GUI è completata su entrambi i sistemi.
I PDF/P7M CIE mantengono integrità, fiducia e revoca del firmatario positive.
La revoca della catena risulta indeterminata anche col runtime precedente
(`revocation_unavailable_or_invalid`), con sorgenti di fiducia invariati.
Sul Mac la verifica corrente della catena e della revoca CIE è positiva.

Report conclusivo: `reports/timestamp-fix-summary.json`; Windows:
`reports/windows-timestamp-fix-summary.json`. I quattro file di codice modificati
hanno SHA-256 identici sulle due piattaforme. I 480 fingerprint nativi/script e
i manifest dei runtime sono verificati. Lo snapshot del PDF è identico e rimosso
a fine controllo, con originale invariato, anche nella nuova GUI Windows.

## Documento reale marcato — macOS e Windows

Verifica completata in sola lettura su macOS ARM64 e Windows x64, con lo stesso
worker e gli stessi hash dell'archivio di fiducia di produzione. Il PDF fornito
contiene due firme e due marche RFC 3161 del 10 dicembre 2020. OpenSSL conferma
indipendentemente l'integrità delle firme e dei token; le impronte delle marche
corrispondono ai valori delle firme. Questo non convalida le catene né la revoca.

Gli esiti DSS coincidono sulle due piattaforme: `PKCS7-T` e `PAdES-BASELINE-T`,
`INDETERMINATE / NO_CERTIFICATE_CHAIN_FOUND`, `no_archive_data`, nessun DSS e
nessuna marca archivistica. Le catene del Ministero della Difesa non sono
ricostruite dalla policy corrente. Non è un test positivo LTA.

Confermato anche un limite nativo comune: un'estensione TSTInfo non critica
viene rifiutata e la GUI indica «Marca temporale non valida», mentre il controllo
crittografico indipendente è positivo. Il problema di interoperabilità e
classificazione è corretto nella revisione successiva descritta sopra; non va
confuso con una prova di falsificazione.

Quattro campioni pubblici EU DSS danno gli stessi esiti su Mac e Windows.
Due sono riconosciuti BASELINE-LTA con due/tre rinnovi, ma non passano la catena
di fiducia di produzione. Le GUI mostrano gli esiti senza promuoverli a validi.
Il test positivo completo di un documento reale LTA attendibile resta aperto.
Non sono modificati codice, fiducia, orologio o app stabile. Nessun PIN usato,
nessuna nuova firma CIE; originale invariato e trasferimento diretto al PC
Windows concluso. Nessun upload a validatori esterni.

Report locale anonimo: `reports/real-document-lta-summary.json`; prove complete
Mac e copia delle evidenze Windows sono referenziate dal report. Sul PC:
`reports/real-document-lta/windows-real-document-lta-summary.json`.
Dettagli e fonti: [LONG_TERM_VALIDATION.md](LONG_TERM_VALIDATION.md#documenti-reali-e-campioni-esterni--16-ottobre-2026).

## DSS/LTA e rinnovi archivistici — prototipo aggiornato

EU DSS **6.5.1**, ARCHIVAL_DATA, worker e policy condivisi macOS/Windows; JVM
Temurin **21.0.12.1+1** private incluse. Il codice C/C++ nativo è invariato.
Le 50 dipendenze JAR, il worker e il cacerts sono identici sulle due piattaforme.
Ambito e policy offline: [LONG_TERM_VALIDATION.md](LONG_TERM_VALIDATION.md).

**macOS ARM64 e Windows x64:** 14 casi DSS/LTA superati, 62 casi di sicurezza
nativi superati, test SDK/handle positivi, analisi Flutter pulita e **15 test
Flutter** superati. Build GUI e controlli visivi completati su entrambi.
Sono verificati i 480 fingerprint nativi/script comuni e i file dei runtime.
Sul Mac sono verificati firma Apple Development e 573 file del validatore/JVM
nel bundle. Il runner e il middleware Mac sono Universal; l'esecuzione Intel
Mac resta da provare, mentre la JVM Intel privata è inclusa.

I casi LTA positivi usano PKI sintetiche e comprendono PAdES/CAdES con due
marche di archivio, firmatario e prima TSA scaduti oggi, DSS/VRI e OCSP/CRL
incorporati. Sono rifiutati la radice privata in produzione, una marca finale
alterata, una pagina e un DSS aggiunti dopo l'archivio, la revoca antecedente
alla prova e la TSA scaduta senza rinnovo. Non sono installate CA di test.

Entrambi i motori della GUI leggono la stessa copia temporanea privata. I test
verificano il rifiuto degli esiti se l'originale cambia e la pulizia su errore.
Il flusso è osservato anche nelle GUI reali Mac/Windows: copia identica al PDF,
rimozione automatica, originale invariato. Sul PC Windows un primo monitor
senza directory osservate è conservato come prova non conclusiva; il controllo
finale conferma esplicitamente contenuto e pulizia.

I PDF/P7M CIE già prodotti mantengono integrità, catena e revoca attuali positive.
DSS rileva BASELINE-B, senza prove LTA. Gli esiti sono separati e l'interfaccia
non mostra il vecchio riepilogo nativo limitato alla revisione finale quando
è disponibile il risultato DSS. La successiva prova su un PDF reale con marche
di una TSA esterna è descritta sopra; le prove LTA positive restano sintetiche.
Non sono state effettuate nuove firme CIE o usati PIN.

Riepilogo locale: `reports/long-term-validation-summary.json`; sul PC:
`reports/windows-lta-snapshot-final-summary.json`. Kit Windows iniziale SHA-256
`03bbfa9e314ad818d5b0cbe7ba57af1360465a959bcda0adc78354bde45e6e1f`,
con due delta di sorgenti Dart/UI/documentazione, senza cambiare il runtime.
Le versioni e i report precedenti sono conservati; nessuna release pubblicata.
Le sezioni seguenti descrivono i cicli di prova precedenti.

## Marche temporali e controlli storici — revisione successiva

Il motore temporale C++ è condiviso fra macOS e Windows. La policy e i limiti
sono descritti in [TEMPORAL_VALIDATION.md](TEMPORAL_VALIDATION.md): marca della
firma RFC 3161, verifica ESS/TSA/impronta, CRL complete incluse e controlli
attuali della TSA; non è una validazione universale DSS/LTA. Il parser CMS
legacy è corretto per la presenza del campo opzionale CRL.

**macOS ARM64:** sei gruppi CTest, 62 casi di sicurezza e sette test UI superati;
analisi Flutter pulita. Le fixture comprendono un firmatario scaduto oggi ma
valido al riferimento provato, falsificazioni/ESS/impronte/CRL negative e
DocTimeStamp finale separato dalle firme. Il ponte pubblico rifiuta la fiducia
nelle radici sintetiche di entrambe le fixture PDF/P7M. Nessuna CA installata.
La GUI Universal è firmata Apple Development; ARM64 eseguito, Intel solo
compilato. Il bundle verifica firma e checksum delle tre librerie incluse.

Rilettura dei PDF/P7M CIE già prodotti sul Mac: integrità, catena e revoca attuali
positive; marca assente e validità storica non determinabile. Il requisito
`--require-trust` passa; `--require-history` fallisce con codice 1 atteso.
La GUI mostra gli stessi esiti sul PDF, senza accedere alla carta.
I casi storici positivi usano fixture sintetiche: non è ancora stato provato
un documento reale dotato di marca di una TSA esterna.

Il pacchetto Windows `CIE-ID-windows-temporal-20261016.zip` contiene sorgenti e
runtime corrispondenti (471 fingerprint nativi/script, 83 file runtime),
SHA-256 `82c1e51cb697ac1fd783ad3714090b41a8978a1f2b0a406acd160b39847f49c1`.
Il PC Windows ha confermato checksum, smoke e controlli sui file reali con gli
stessi esiti temporali. Anche Windows supera 62 casi di sicurezza, sette test
UI, analisi e build Release; il controllo visivo conferma marca assente e
storico non determinabile accanto ai controlli attuali positivi. Tutti i 471
fingerprint e gli 83 file runtime nelle due copie corrispondono. I report
conclusivi sono conservati localmente nella chat Windows. Non sono necessarie nuove firme o PIN.
Le sezioni successive documentano le prove delle revisioni precedenti.

## Catena di fiducia e revoca — backend condiviso aggiornato

Questa sezione descrive la revisione successiva alle prime prove di firma
documentate sotto. Le vecchie indicazioni di revoca sconosciuta e catena non
controllata restano come evidenza delle build precedenti.

Il nuovo backend include la Root CA CIE e tre SubCA dalla pagina ministeriale;
provenienza e SHA-256 sono registrati in `cie_sign_sdk/trust/manifest.json`.
Solo la Root CA è un'ancora esplicita: i certificati del CMS, le SubCA e AIA
restano candidati. Per altre autorità si usano le policy native macOS/Windows,
con ulteriore verifica OpenSSL del percorso accettato dal sistema.

Il test di sicurezza ora copre anche radice attendibile, emittente mancante,
radice privata inserita nel documento, rifiuto della radice da parte del sistema,
radice non correlata, certificato/emittente scaduto, firma del certificato
alterata, emittente non CA, uso della chiave errato e rete disabilitata. Le prove
end-to-end di revoca usano risposte OCSP/CRL firmate sintetiche: catena buona,
emittente revocato con firmatario buono, CRL dell'emittente contraffatta,
firmatario revocato ed endpoint irraggiungibile. Nessun errore viene promosso
a “non revocato”. I test automatici non richiedono carta o PIN.

**macOS ARM64:** sei gruppi CTest, smoke nativo, analisi Flutter e cinque test UI
superati. Rilettura dei PDF/P7M reali già firmati: integrità valida, percorso di
tre certificati attendibile verso la Root CA CIE, OCSP del firmatario positivo e
CRL firmata della Root CA positiva per la SubCA. Revoca dell'intera catena non
root: buona. I controlli sono eseguiti alla data corrente, con documenti e
report anonimi conservati localmente; non attestano qualificazione eIDAS o LTV.

**Windows x64:** la revisione finale supera smoke, 39 casi di sicurezza, verifica
stretta sui PDF/P7M reali e test negativo self-signed (integrità valida, fiducia
rifiutata e codice 1 atteso). Corrispondono tutti i 467 fingerprint sorgenti e
gli 83 file del runtime, incluso quello nel bundle. Il primo kit aveva il solo
fingerprint di `PORTING.md` obsoleto: la discrepanza è risolta nel kit finale,
conservando i report storici. Analisi, cinque test UI e build GUI superati.

Nel controllo UI macOS è emerso che il rilevamento automatico della carta può
attendere il driver PC/SC e bloccare anche la verifica senza carta. L'avvio ora
carica solo il backend e lascia il rilevamento al pulsante esplicito. Il test UI
verifica che non si acceda al lettore durante l'avvio e che la pagina Verifica
sia disponibile prima del primo rilevamento. Nessun timeout o retry è aggiunto
alle operazioni di firma.

Le prove hardware Linux restano in sospeso; l'archivio di fiducia Linux nativo
non è integrato in questa revisione. Non è richiesta una nuova firma o un PIN
per verificare i documenti già prodotti.

## Backend condiviso del porting

| Ambiente | Compilazione | Esecuzione osservata |
| --- | --- | --- |
| macOS 27.0.1 / Xcode 27 | Backend, SDK, adattatore e GUI Universal ARM64 + x86_64, firmati Apple Development | ARM64: 6 gruppi CTest, smoke ABI reale, percorsi UTF-8, 4 test UI; rilevamento CIE e firme reali PAdES/CAdES riuscite. CMS/ByteRange/contenuto P7M verificati indipendentemente. Esecuzione Intel ancora da provare. |
| Ubuntu 24.04 nella VM Lima `cie-porting`, ARM64 | Backend, SDK, ponte e adattatore ELF compilati con GCC 13 | 6 gruppi CTest superati; SDK, sicurezza revoca, handle e ponte reale verificati senza carta |
| Windows 11 Pro 10.0.26300, x64, PC Windows di collaudo | Sei DLL MinGW originali; test SDK ricompilato con correzione PNG; GUI Release MSVC 14.44 e Flutter 3.47.7 | Smoke completo superato: SDK, OCSP/CRL, handle, PDF/P7M validi e alterati, firme multiple, percorsi UTF-8, recupero dopo file mancante. Due lettori logici e una CIE riconosciuta senza PIN. Quattro test UI superati. Esiti delle prove hardware descritti sotto. |

### Prova Windows del 16 ottobre 2026

Pacchetto `CIE-ID-native-windows-x64-testkit-20261016.zip`, 30380060 byte,
SHA-256 `d5927d881e67621969fb29056aa59c3c310f27557b88818fde7fdd1efbedfe8d`.
Tutti i 620 file elencati in `SHA256SUMS.txt` risultano corretti. ZIP ed estrazione
originale sono conservati; le modifiche sono nella copia separata `prototype-windows`.
Python 3.12.14 AMD64; driver Microsoft Usbccid 10.0.26100.9711; servizio Smart Card
attivo con avvio manuale, senza cambiamenti alla configurazione del sistema.

Il primo smoke originale terminava con codice 1 in `cie_sdk_tests.exe`:
`PdfErrorCode::UnsupportedImageFormat`, percorso della fixture `.\\cieXXXX.tmp`.
Il test Windows usa `GetTempFileNameA`, che assegna `.tmp`; PoDoFo seleziona il
decoder dal suffisso. In `native/backend/cie_sign_sdk/tests/sdk_tests.cpp` la
correzione rinomina il file temporaneo riservato aggiungendo `.png`, senza
sovrascrivere file esistenti. Il test SDK è stato successivamente ricompilato
nella VM Linux con identica toolchain MinGW e dipendenze fissate. **La correzione
è ora eseguita e verificata su Windows:** tutti e tre gli EXE e lo smoke completo
terminano con codice 0. Il pacchetto originale e i report del fallimento sono
conservati come evidenza storica.

Aggiornamento `CIE-ID-windows-sdk-test-fix-20261016.zip`, 8774741 byte,
SHA-256 `4f009ccf684dbd3ab0ef8c6bf1a78a123696f9e6771da306cdd5f00a0bc9a5bc`,
scaricato direttamente dal Mac nella rete locale. Verificati tutti e sei i file
di `SHA256SUMS.txt`, `UPDATE.json`, hash del vecchio e nuovo EXE e identità dei due
sorgenti rispetto alle modifiche già presenti sul PC. Nuovo `cie_sdk_tests.exe`:
SHA-256 `3941075229512fd78269c36cebec5370d5199817bf9a7b7c276d4e2883f8ee32`.
Il runtime di prova `runtime-windows-fixed-20261016` è una copia verificata del
runtime originale; sono sostituiti soltanto test SDK e manifest. Tutte le sei DLL
restano identiche. I 77 checksum del nuovo manifest sono corretti. La stessa
sostituzione è stata applicata al runtime di lavoro e al bundle GUI; copie dei
due file precedenti sono in `reports/runtime-before-sdk-fix`.

`scripts/smoke_native.py` ora conserva stdout e diagnostica completa dei test,
continua il rilevamento e salva il report anche dopo un fallimento degli EXE.
Se il generatore SDK fallisce, le verifiche che ne dipendono sono esplicitamente
saltate e il comando restituisce comunque codice 1. OCSP/CRL e handle terminano
con codice 0; il probe senza PIN riporta due lettori e una CIE.

Per verificare separatamente le DLL originali sono state generate sul PC nuove
fixture sintetiche tramite Python cryptography: CMS incapsulato, PDF con una e
due firme incrementali, versioni alterate e PDF senza firma. Queste fixture
**non sono prodotte dal test SDK** e non ne sostituiscono l'esito. Sul ponte reale
passano integrità, validità temporale, revoca sconosciuta, nomi UTF-8 e recupero
dopo un file mancante. Anche `dart run tool/smoke.dart` passa usando queste
fixture e il runtime incorporato nella GUI; riconosce una CIE, senza PIN.

Dopo l'aggiornamento il test SDK ha generato nuove fixture sul PC, utilizzate
anche dal client Dart con il runtime del bundle: PDF/P7M validi e alterati,
PDF con due firme e senza firma, recupero dopo file mancante, tutti superati.
Lo smoke nativo conferma inoltre gli stessi esiti con nomi UTF-8. Ripetuti
`flutter analyze --no-pub` (nessun problema) e `flutter test --no-pub` (4/4).
OpenSSL 3.5.7 già presente con Git conferma indipendentemente la firma CMS del
PDF sintetico e il ByteRange esteso all'intero file; per il P7M sintetico conferma
CMS e uguaglianza del contenuto estratto rispetto al contenuto originale.
Il controllo OpenSSL usa `-noverify`, senza attestare la catena di fiducia.

Flutter Windows 3.47.7, commit `abaf9c523780a608bd46686fd5e53740a07077f8`,
Dart 3.13.5; archivio Windows verificato con SHA-256
`c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`.
Toolchain e cache pub locali al progetto; nessuna variazione di `pubspec.lock`
o `toolchain.lock.json`. `flutter pub get --enforce-lockfile` passa dopo la
preparazione di junction locali per i plugin Windows/Linux: il primo tentativo
era terminato per assenza del privilegio symlink. Nessuna modifica alla modalità
sviluppatore o al toolchain Flutter. Analisi senza problemi, quattro test UI
passati, `flutter build windows --release --no-pub` riuscito con Visual Studio
Build Tools 2022 17.14.39 / MSVC 14.44.35207 e Windows SDK 10.0.26100.0.
Tutti i 77 file nel manifest del runtime incluso nel bundle conservano i checksum;
runner, plugin, motore Flutter e sei DLL private sono PE AMD64.

Report sul PC, nella cartella `CIE-ID/reports`: `windows-native-report.json`
(fallimento SDK conservato), `windows-independent-bridge-report.json` e
`dart-bundled-runtime-report.json`; log separati per dipendenze, analisi, test
e build. `verify_windows_bridge.py` documenta la generazione indipendente.
Report dell'aggiornamento: `windows-native-fixed-report.json`,
`dart-bundled-sdk-fixed-report.json`, `independent-sdk-fixed-verification.json`.

### Firme reali Windows con il backend condiviso

Il 16 ottobre 2026 l'utente ha eseguito personalmente una firma PAdES e una
CAdES dalla GUI Windows, inserendo il PIN completo esclusivamente nel campo
protetto dell'app e premendo il pulsante per ciascuna prova. Nessuna firma o
autenticazione è stata automatizzata. È stato usato il documento sintetico
`signing-tests-20261016/prova.pdf`, con due destinazioni nuove nella stessa
cartella. Queste prove riguardano le sei DLL del backend condiviso del testkit,
non il vecchio backend macOS originale.

- PAdES `prova-firmata-pades.pdf`: una firma, integrità valida e certificato nel
  periodo di validità attraverso il ponte. Controllo indipendente OpenSSL CMS
  riuscito; ByteRange corretto ed esteso all'intero PDF, escluso il Contents.
- CAdES `prova-firmata-cades.p7m`: una firma, integrità valida e certificato nel
  periodo di validità attraverso il ponte. Controllo indipendente OpenSSL CMS
  riuscito; contenuto estratto identico, byte per byte, al PDF originale.
- Per entrambe le firme lo stato di revoca è non determinato (codice 3).
  Nessuna verifica della catena di fiducia o attestazione giuridica; OpenSSL
  usa `cms -verify -noverify` per la sola integrità crittografica.

`reports/windows-real-pades-report.json` e `windows-real-cades-report.json`
contengono soltanto flag e codici. I file firmati, che incorporano il certificato
personale, restano sul PC e non sono inclusi nelle patch dei sorgenti.
`reports/verify_signed_documents.py` verifica file già esistenti senza firmare,
autenticare o mostrare identità; i file intermedi sono locali e temporanei.

### Prove macOS con il backend condiviso allineato

Le correzioni `sdk_tests.cpp` e `smoke_native.py` coincidono byte per byte con
quelle verificate sul PC Windows. La documentazione incorpora gli esiti delle
due firme reali Windows. Lo strumento indipendente è ora condiviso in
`scripts/verify_signed_documents.py`: seleziona le librerie della piattaforma e
accetta `--openssl`, senza percorsi Windows incorporati. Richiede Python 3.10+
con `pypdf` e un eseguibile OpenSSL; queste dipendenze servono alla verifica di
sviluppo, non all'app.

Il backend macOS è ricompilato come Universal ARM64/x86_64 dalle stesse sorgenti
e dipendenze fissate. Passano i sei gruppi CTest, lo smoke reale con percorsi
UTF-8 e i controlli indipendenti CMS/ByteRange/contenuto P7M su fixture nuove.
Il rilevamento sul Mac conferma due lettori logici e una CIE senza PIN.
Analisi Flutter senza problemi e quattro test UI superati.

Il nuovo bundle di prova usa la cartella `flutter-prototype/macos-shared`,
distinta dal precedente bundle macOS. La firma Apple Development copre app,
framework e tre librerie private Universal. Il manifest nel bundle registra i
checksum delle librerie dopo la firma; il manifest della build sorgente è
conservato separatamente come `source-runtime-manifest.json` nelle risorse.
Il 16 ottobre 2026 l'utente ha eseguito personalmente entrambe le firme dalla
GUI, inserendo il PIN esclusivamente nel campo protetto. Il controllo successivo
con il ponte e OpenSSL conferma:

- PAdES: una firma CMS valida, ByteRange corretto ed esteso all'intero PDF.
- CAdES: una firma CMS valida e contenuto estratto identico al PDF originale.
- Entrambe: certificato nel periodo di validità, revoca non determinata
  (codice 3), catena di fiducia non validata.

La verifica indipendente non autentica la carta e non esegue firme; il report
`reports/macos-shared-real-signatures.json` contiene soltanto flag e codici.
I report locali sono `reports/macos-shared-aligned-native.json`,
`reports/macos-aligned-independent-fixtures.json` e
`reports/macos-shared-bundle-validation.json`.

Non è al momento disponibile un ambiente Linux dell'utente per le prove GUI o
con lettore e CIE. La precedente VM dedicata è stata usata per compilazione e
test automatici senza carta; questi risultati non attestano la firma hardware.
Le prove Linux restano in sospeso e non sono un requisito per le prove macOS.

Una precedente lettura PC/SC sul Mac è rimasta in attesa nel servizio di sistema
e ha restituito due lettori ma nessuna CIE riconosciuta; la verifica dei documenti
è rimasta funzionante. Lo strumento di smoke test isola ora il solo rilevamento
in un processo con limite di 30 secondi, senza introdurre timeout o retry della
firma. Il comportamento con il proprio lettore va confermato nelle prove hardware.

I sei gruppi CTest comprendono confini ABI sintetici, caricamento/PKCS#11,
verifica attraverso il middleware, handle numerici, sicurezza OCSP/CRL e SDK.
I test dell'SDK coprono PDF/P7M validi e alterati, PDF con firme multiple,
compatibilità SHA-1 in lettura e provider OpenSSL default/legacy. Il test degli
handle controlla anche il wrap del contatore e il riuso della variabile shared_ptr.
Gli ingressi stringa troppo lunghi vengono rifiutati prima della copia.

`scripts/smoke_native.py` carica i componenti reali, genera fixture nuove, verifica
PDF e P7M attraverso lo stesso ponte dell'interfaccia, ripete la verifica con
nomi UTF-8 e controlla il recupero dopo un percorso inesistente. I report locali
sono in `reports/` e non includono PIN, nomi dei sottoscrittori o ID della carta.

Il lettore del Mac non è inoltrato alla VM. La policy PC/SC di Ubuntu rifiuta
l'utente SSH della VM: questo errore torna correttamente come `pcsc_unavailable`.
Una prova separata con privilegi nella sola VM ha ottenuto servizio disponibile
e zero lettori. Non è stata modificata la policy polkit e non è richiesta
l'esecuzione dell'app Linux come root: il test dell'utente desktop con il proprio
lettore resta da fare.

Le dipendenze Windows sono compilate dagli stessi archivi fissati e controllati
con SHA-256, fra cui OpenSSL 3.5.9, Crypto++ 8.9.0 e PoDoFo 1.1.2. Gli import PE
sono stati esaminati: oltre alle DLL di Windows servono libgcc, libstdc++ e
winpthreads, inclusi nel runtime privato con gli avvisi. Non sono necessarie
DLL OpenSSL/PoDoFo esterne. Questo controllo non sostituisce il caricamento
ed esecuzione delle DLL sul PC Windows.

Analisi Dart: nessun problema. Quattro test dell'interfaccia superati, compresi
messaggi lunghi, distinzione degli esiti, campo PIN svuotato e assenza di retry.
Il workflow CI è predisposto anche per l'esecuzione del backend su Windows,
ma non è stato avviato su GitHub dal prototipo locale.

## Prove precedenti con il backend macOS originale v1.5.2

Il primo prototipo collegato alla libreria originale, conservata senza modifiche,
è stato provato dall'utente con PIN inserito soltanto nell'app:

- Firma reale PAdES e firma reale CAdES riuscite.
- Verifica successiva nell'app riuscita.
- Controllo indipendente OpenSSL: CMS validi; ByteRange del PDF esteso a tutto il
  documento; contenuto estratto dal P7M identico al file d'ingresso.
- Bundle e librerie Universal firmati Apple Development.

Le prove hardware precedenti rimangono distinte da quelle del nuovo backend
condiviso, ora confermate anche su macOS nella sezione dedicata sopra.
Il pacchetto Windows
contiene uno strumento di firma interattivo, con un solo tentativo per comando.

Non è stata verificata l'esecuzione Intel sul Mac: Rosetta non è installato.
Le firme hardware Windows sono descritte nella sezione dedicata sopra.
La firma hardware Linux resta da provare. La GUI Windows è stata compilata ed
eseguita sul PC; la GUI Linux resta da compilare/eseguire.
Non sono state pubblicate release del porting.

## Significato e limiti degli esiti

La verifica separa integrità crittografica, validità temporale e revoca. Non
attesta catena di fiducia o qualificazione giuridica della firma. Le prove
OpenSSL precedenti usano `cms -verify -noverify` per il solo controllo crittografico.
Lo stato di revoca non determinato dei documenti reali non viene promosso a
“non revocato”. I certificati sintetici durano un'ora e sono rigenerati a ogni
esecuzione dei test.

La release CIE ID macOS v1.5.2 e il suo repository rimangono separati dal prototipo.

## UX3 — 18 ottobre 2026

Firma guidata condivisa: 86 test Flutter e 20 gruppi CTest macOS superati;
analisi senza problemi, build macOS Apple Development e backend Windows x64
compilato. Preflight documentale eseguito con veri PDF/CMS sintetici; controllo
visivo macOS senza PIN. Le prove con CIE reale e l’esecuzione della nuova build
sul PC Windows restano rinviate. Dettagli e percorsi in [SIGNING_UX3.md](SIGNING_UX3.md).

## UX4 — 18 ottobre 2026

100 test Flutter superati, più 3 integrazioni native macOS facoltative superate
su PDF/CMS sintetici e 135 controlli del generatore nativo. Analisi senza problemi.
Verifica immediata, esiti indeterminati, scarto dei risultati superati e
estrazione sulla copia verificata; nessun PIN o accesso alla carta. Runtime nativo
UX3 invariato. Artefatto macOS e limiti Windows in [VERIFICATION_UX4.md](VERIFICATION_UX4.md).