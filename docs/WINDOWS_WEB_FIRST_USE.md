# Attivazione Windows al primo abbinamento

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

Il runner Windows include `web-component/CIE-Web-Setup.exe`. Quando si preme
Abbina CIE, il monitor viene sospeso e il helper controlla il pacchetto e la
registrazione della carta selezionata. Se la versione corretta è già installata
non richiede UAC. Altrimenti il runner avvia solo quel helper con `runas` e
attende il risultato senza bloccare Flutter. Il dialogo PIN appare dopo il
completamento. Abbinamento e certificati restano nel profilo dell’utente normale,
anche se UAC viene autorizzato usando un diverso account amministratore.

Il rifiuto di UAC non avvia autenticazioni né ritentativi. L’utente può annullare
oppure scegliere esplicitamente Continua solo per firmare. Per una CIE già
abbinata, Attiva accesso ai siti installa il componente e ripubblica i dati
pubblici salvati senza chiedere nuovamente il PIN; la carta deve essere presente.

Il helper copia esclusivamente il payload con dimensioni e SHA-256 fissati nel
suo eseguibile, sotto Program Files in una cartella identificata dal contenuto.
Imposta ACL protette, rifiuta reparse point/hard link dei file e mantiene aperti
i file verificati durante l’installazione. Nessun percorso di destinazione,
script, PIN o credenziale è accettato dal processo elevato. La lettura pubblica
usa solo SELECT, READ BINARY e GET RESPONSE, al massimo 16 comandi. Non esegue
autenticazioni, scritture o reset della CIE.

La registrazione usa le API Smart Card di Windows e l’ATR esatto della carta.
Le registrazioni di altri componenti causano un arresto con spiegazione; non
sono sostituite. Modelli aggiuntivi ricevono nomi separati. Se l’aggiornamento
della registrazione fallisce, il helper tenta il ripristino e conserva i file.
I certificati di fiducia e le configurazioni dell’app originale non sono gestiti
da questo installer.

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
   lettore, registrazioni o scritture di sistema. Non usare `--check` o
   `--install` come test software su una macchina con carta reale.
6. Eseguire i test Flutter e `flutter build windows --release`. L’intera
   cartella Release è necessaria; il solo eseguibile non è distribuibile.

## Validazione e limiti

Test software: ordine installazione/PIN, rifiuto UAC, prosecuzione esplicita solo
firma, recupero senza PIN e pacchetto alterato/mancante. Test nativi isolati:
quoting dei lettori, conflitti di proprietà, whitelist APDU, errori e rollback
delle registrazioni e minidriver con trasporto simulato.

Il nuovo installer e il minidriver sono componenti sperimentali del prototipo,
non firmati digitalmente per una distribuzione di produzione. UAC, installazione
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
