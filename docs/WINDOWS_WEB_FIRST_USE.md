# Componente Windows e configurazione dell’accesso ai siti

Per l'accesso ai siti il componente Windows richiede sempre tutte le otto cifre
del PIN, come macOS, anche per carte abbinate. Non ricostruisce il PIN dal
prefisso dell'abbinamento. Lunghezze diverse da otto e caratteri non numerici
sono rifiutati localmente, prima di selezionare o autenticare la carta. La firma
dei documenti con carta abbinata mantiene la propria modalità con quattro cifre.
Il login Chrome al portale CIE con la policy a otto cifre è stato confermato
dall'utente; i collaudi storici riportati in fondo precedono questa uniformazione.

Il PIN completo può essere riutilizzato dal Base CSP/KSP di Windows tramite
`PinCacheTimed`, per un massimo di 60 secondi dalla memorizzazione. Windows lo
protegge cifrandolo in memoria; non lo usa oltre la scadenza. Questa policy
sostituisce `PinCacheNone`, che può provocare due finestre PIN durante le fasi
successive di uno stesso accesso. Il minidriver non conserva copie del PIN e
non lo salva su disco o nell'archivio dell'abbinamento. Non si usa una cache
illimitata per tutta la durata del browser. Ogni callback di autenticazione
continua a verificare il PIN fornito e la firma richiede una sessione valida.
L'utente ha confermato il funzionamento dopo la modifica della cache; i test
isolati controllano il contratto della policy. Altri browser/siti restano da verificare.

Riferimento: [policy PIN del Base CSP/KSP Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/card-pin-operations).

## Installazione dal pacchetto Windows

Il [pacchetto Windows x64](WINDOWS_INSTALLER.md) installa app e componente nella
stessa sessione UAC. Non occorrono carta, lettore o PIN: sono registrati i
[12 ATR e le maschere ufficiali verificati](WINDOWS_CARD_CATALOG.md).
Gli aggiornamenti preservano gli archivi personali e migrano le registrazioni
compatibili del progetto, senza sovrascrivere altri middleware.

Il runner avvia soltanto il helper con `--check <lettore>`, senza `runas` né
richieste amministrative. Il controllo precede il dialogo PIN. Se il componente
manca, l'app indica di eseguire l'installer; l'utente può annullare oppure
scegliere esplicitamente Continua solo per firmare. Per una CIE già abbinata,
Completa accesso ai siti ripubblica i dati pubblici salvati senza un altro PIN.
L'abbinamento e i certificati restano nel profilo dell'utente normale, anche se
UAC dell'installer è autorizzato con un diverso account amministratore.

Il helper dell'installer usa soltanto payload con dimensioni e SHA-256 fissati,
in Program Files, con ACL protette e cartelle immutabili identificate dal
contenuto. Non sovrascrive binari caricati. Non accetta destinazioni, script,
PIN o credenziali. L'installazione legge e aggiorna soltanto il database Calais
a 64 bit; non chiama PC/SC e non dipende dal servizio Smart Card. Il controllo
`--check` usato dall'app legge l'ATR della carta selezionata senza inviare APDU.
L'aggiornamento delle registrazioni di più modelli ripristina
quelle precedenti se una scrittura fallisce. Registrazioni estranee non vengono
sostituite. Cache, preferenze, certificati utente e browser sono conservati.

## Preparazione della build

1. Preparare `native/runtime/windows` con il backend e il relativo manifest.
2. Compilare `native/platform/windows/web` con MSVC x64 e il CPDK ufficiale v7.
3. Eseguire `scripts/package_web_windows.py --runtime <runtime> --provider
   <cie_prototype_minidriver.dll> --output <cartella-nuova>`; la destinazione
   prevista dal runner è `native/runtime/windows-web-component`.
4. Riconfigurare il progetto nativo con
   `-DCIE_WEB_SETUP_MANIFEST=<output>/setup_payload.h`, compilare il target
   `cie_web_setup` e copiarne `CIE-Web-Setup.exe` nella cartella del payload.
5. `CIE-Web-Setup.exe --validate-package` verifica solo i file, senza UAC,
   lettore, registrazioni o scritture di sistema. `--plan-package` verifica anche
   i conflitti leggendo il registro, senza carta, UAC o scritture. Non usare
   `--check` come prova senza carta; `--install-package` e `--unregister-package`
   modificano le sole registrazioni del progetto e richiedono l'installer elevato.
6. Eseguire i test Flutter e `flutter build windows --release`. L’intera
   cartella Release è necessaria; il solo eseguibile non è distribuibile.
7. Preparare l’installer completo come descritto in [WINDOWS_INSTALLER.md](WINDOWS_INSTALLER.md).

## Validazione e limiti

Test software: controllo del componente prima del PIN, componente mancante, prosecuzione esplicita solo
firma, recupero senza PIN e pacchetto alterato/mancante. Test nativi isolati:
quoting dei lettori, conflitti di proprietà, whitelist APDU, errori e rollback
delle registrazioni e minidriver con trasporto simulato.

Il nuovo installer e il minidriver sono componenti sperimentali del prototipo,
non firmati digitalmente per una distribuzione di produzione. UAC dell’installer completo, installazione
effettiva, caricamento nel KSP e login nel browser richiedono collaudo reale
separato: i test automatici non li attestano. La prima implementazione era stata
verificata solo con test software; i collaudi successivi sono registrati nei
rapporti Windows del progetto.

### Contratto delle versioni delle strutture

Le strutture di interrogazione diverse da CARD_DATA devono trattare la versione
0 come versione 1 e negoziare una versione supportata per richieste più recenti.
Il rifiuto della versione 0 con SCARD_E_INVALID_PARAMETER impediva l’apertura
silenziosa della chiave dal KSP, prima della richiesta PIN. Capabilities, spazio,
dimensioni chiave, informazioni file e container ora restituiscono la versione
1; i test verificano richieste 0, 1 e successive con un certificato sintetico
valido e senza autenticazioni reali.

Riferimento: [convenzioni Microsoft per i minidriver](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/smart-card-minidriver-overview).

### Sessione tra raccolta PIN e firma

La prova locale del 19 ottobre ha aperto la chiave e registrato una prima
autenticazione riuscita, seguita da una seconda autenticazione con errore del
backend, prima di CardSignData. Non era un rifiuto del PIN nel primo controllo.
Il KSP può usare più contesti: la selezione IAS e il canale sicuro memorizzati
durante una precedente lettura pubblica non attestano lo stato attuale della
carta dopo il dialogo Windows.

Ogni callback esplicito di autenticazione ora ricrea la sessione IAS, seleziona
le applicazioni e verifica l'identità e il certificato prima del singolo
controllo PIN. Non effettua reset, ritentativi o riuso di un controllo PIN
precedente. I test isolati riproducono due contesti che invalidano la selezione
reciproca e verificano che un PIN errato successivo a un successo venga rifiutato
e impedisca la firma. Dopo l'installazione con UAC, la prova locale reale sul KSP
ha completato entrambe le autenticazioni Windows e una firma RSA PKCS1 SHA256
di un messaggio diagnostico fisso: risultato 0, firma di 256 byte verificata
con la chiave pubblica del certificato. Il PIN è stato inserito personalmente
dall'utente. Nessun ritentativo automatico. Il successivo collaudo completo
con Chrome Windows, CIE livello 3 e lettore ha aperto l'area personale del
portale ufficiale: esito confermato dall'utente e presenza del comando Esci
verificata senza acquisire dati personali della pagina.

### Compatibilità delle richieste RSA di Firefox

Il minidriver accetta anche un DigestInfo SHA-256/384/512 già codificato, con
padding PKCS1 e `pszAlgId == NULL`, oppure `aiHashAlg == 0` nel formato legacy.
È la forma usata dal [backend Windows di osclientcerts](https://searchfox.org/firefox-main/source/security/manager/ssl/osclientcerts/src/backend_windows.rs).
Il DER deve essere canonico e viene inoltrato senza aggiungere un secondo
DigestInfo. Hash grezzi, blocchi RSA arbitrari, SHA-1, PSS e dati malformati
restano rifiutati; le richieste di dimensione non autenticano e non firmano.
Il rifiuto precedente è riprodotto con carta simulata: 115 controlli isolati
passano con la correzione. Il 21 ottobre 2026, dopo l'aggiornamento del componente
con UAC e il riavvio completo di Firefox 158.0.1 su Windows, l'utente ha
confermato l'apertura dell'area personale del portale CIE con PIN completo.
La traccia numerica del minidriver conferma autenticazioni e firme riuscite
con algoritmo separato assente. Il protocollo TLS del tentativo reale non è
stato rilevato. Non sono stati aggiunti moduli PKCS#11 o cambiate preferenze
di sicurezza del browser; altri siti/versioni restano da collaudare.

Il 21 ottobre l'utente ha confermato anche il collaudo riuscito dell'accesso con
Microsoft Edge su Windows usando il componente installato. La conferma è
manuale; versione di Edge e protocollo TLS non sono stati rilevati
indipendentemente. La [verifica RSA-PSS](RSA_PSS_FEASIBILITY.md) mantiene le
capacità dichiarate PKCS#1 v1.5 e porta a 124 i controlli isolati del minidriver.
