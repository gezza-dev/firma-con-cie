# Impostazioni, diagnostica, proxy e Assistenza

Questa integrazione appartiene al prototipo Flutter separato. Il codice Dart,
il trasporto C++ e il worker Java sono condivisi tra macOS e Windows. Non
installa componenti di sistema e non cambia le impostazioni proxy del computer.

## Impostazioni

La voce Impostazioni contiene rete, diagnostica e le precedenti preferenze
per formato e immagine della firma. La configurazione di rete ha un archivio
separato da quello dell’immagine; ripristinare la rete non elimina la grafica.
Lo schema 1 di `settings/settings.json` contiene soltanto modalità, host e porta
del proxy e livello diagnostico. L’archivio è nell’Application Support del
prototipo; su macOS la cartella è protetta con permessi 0700. I salvataggi usano
un temporaneo e rinomina. Directory radice e file letti tramite link simbolici
sono rifiutati. Non si migrano automaticamente le impostazioni dell’app pubblicata.

Se le impostazioni salvate non sono leggibili, verifiche e nuove firme restano
sospese finché l’utente non salva o ripristina una configurazione valida. Non si
usa automaticamente la connessione diretta dopo un errore di configurazione.

## Proxy

Sono disponibili connessione diretta, proxy HTTP e proxy HTTPS, con host/IP e
porta espliciti. IPv6 richiede parentesi quadre e non accetta identificatori di
interfaccia. URL, percorsi, credenziali incorporate nell’host e caratteri di
controllo sono rifiutati prima di usare la carta. Per l’autenticazione è supportato
Basic: utente e password restano nella sessione, senza scrittura su disco.
Vanno reinseriti dopo il riavvio. Il campo password è protetto. I buffer nativi
vengono azzerati; Dart non garantisce l’azzeramento delle stringhe gestite.

Il ponte espone API aggiuntive v1 per verifica/firma con configurazione per
singola chiamata. Le API precedenti restano dirette. Il proxy raggiunge anche la
verifica successiva alla firma. Il worker DSS riceve la configurazione tramite
stdin privato e la passa allo stesso trasporto C++ delle CRL tramite un altro
pipe privato: nessuna password in argomenti, variabili d’ambiente, file o log.
Le variabili proxy del processo non sono ereditate e `NO_PROXY` non aggira la
scelta esplicita. Un errore del proxy non causa un tentativo diretto alternativo.

Le connessioni HTTPS verificano nome e certificato del server e del proxy HTTPS,
con TLS 1.2 minimo e archivio di sistema. La fiducia nei certificati di firma
rimane separata dalla fiducia TLS e dal successo del trasporto.

Per CRL provenienti da documenti non attendibili, il proxy usa CONNECT verso un
indirizzo pubblico numerico verificato: non può risolvere il nome verso la rete
locale. Il nome originale resta usato per Host, SNI e verifica TLS. Ogni redirect
viene nuovamente controllato e una connessione HTTPS non può degradare a HTTP.
La risoluzione DNS locale ha un’attesa limitata; restano i limiti di tempo,
numero di richieste, dimensioni e autenticazione delle CRL. Il proxy deve
permettere CONNECT anche verso la porta HTTP dei servizi CRL. Una rete che
impedisce la risoluzione DNS locale o il tunnel necessario può lasciare la
revoca indeterminata. Non sono implementati PAC, discovery del proxy di sistema,
SOCKS, NTLM/Kerberos o memorizzazione delle credenziali nel portachiavi. Le opzioni
di avvio in background/area di notifica dell’app di riferimento non fanno parte
di questo blocco: richiedono ancora l’integrazione desktop per ciascun sistema.

Il Test connessione usa la configurazione attualmente inserita nel modulo, anche prima del
salvataggio. Esegue una richiesta HEAD al sito ufficiale CIE, senza documento,
lettore, carta o PIN. Il suo esito non attesta la validità di una firma.
I collegamenti esterni usano il browser e la sua configurazione di rete.

## Diagnostica

### Controllo e recupero dei certificati HTTPS sulle tre piattaforme

Se il Test connessione restituisce il codice TLS 60, oppure una firma con
catena CIE attendibile presenta revoca indeterminata, l’app propone il dialogo
**Aggiornamento dei certificati di sicurezza**. Il testo italiano/inglese è
comune a Windows, macOS e Linux. Indica che potrebbero mancare certificati:
non attribuisce con certezza a questa causa ogni errore di revoca. Nessun
recupero parte prima di **Consenti e riprova**. **Non ora**, ESC e chiusura
mantengono il risultato precedente. Il consenso è proposto una sola volta per
sessione; per riprovare dopo un rifiuto è possibile riavviare l’app.

Dopo il consenso, processi asincroni senza shell eseguono richieste HEAD HTTPS
alle due destinazioni fisse `https://www.cartaidentita.interno.gov.it/` e
`https://ldap.cie.interno.gov.it/cierootca.crl`. Non accettano URL dai documenti,
non seguono redirect, non inviano documenti e non richiedono la CIE o il PIN.
Ogni richiesta ha limite di 10 secondi e interruzione del client dopo 15.
L’interfaccia rimane responsiva. Il controllo usa:

- **Windows x64/ARM64:** il client Schannel `curl.exe` della directory nativa
  ottenuta dall’API Windows, con selezione automatica del certificato client
  disabilitata. Windows può recuperare materiale della catena secondo le sue
  regole di fiducia. Non serve UAC per queste richieste.
- **macOS:** `/usr/bin/curl` con il backend Apple SecureTransport/SecTrust e
  l’archivio di sistema. Non si importa una CA ricavata dal server né si
  modificano portachiavi o regole di fiducia. Una radice assente o una policy
  che rifiuta il certificato può richiedere gli aggiornamenti del sistema;
  non si promette di correggere ogni errore attraverso il solo collegamento.
- **Linux:** `/usr/bin/curl` con gli stessi percorsi CA di sistema selezionati
  dal middleware, anche per il proxy HTTPS. Se l’archivio manca o il controllo
  fallisce con codice TLS 60/77, il consenso consente di proporre un aggiornamento
  tramite PackageKit e l’autorizzazione Polkit personale del sistema. Un errore
  DNS, di connessione o HTTP non avvia un aggiornamento dei certificati.

Su Linux l’app usa D-Bus del sistema e transazioni PackageKit 1.x: aggiorna i
metadati dei repository configurati, risolve solo `ca-certificates` e i pacchetti
opzionali `ca-certificates-mozilla`/`ca-certificates-utils`, quindi simula il piano.
Piani con rimozioni, downgrade, pacchetti non attendibili o modifiche a pacchetti
esterni a questo insieme vengono rifiutati. L’installazione/reinstallazione
richiede `ONLY_TRUSTED`; nessuna accettazione di nuove chiavi dei repository,
nuova sorgente software, password amministrativa raccolta dall’app o aggiornamento
completo del sistema. Polkit applica le policy amministrative della distribuzione.
Se PackageKit, il backend o l’agente di autorizzazione non sono disponibili,
l’operazione resta non conclusa e l’app invita a usare gli aggiornamenti del
sistema. I pacchetti DEB/RPM/Arch richiedono il client curl e raccomandano o
propongono PackageKit; con AppImage questi servizi devono essere presenti
sul sistema ospitante. Non si installano servizi di sistema in silenzio.

Il timeout di una transazione chiede l’annullamento al gestore pacchetti;
non viene terminato forzatamente un installer privilegiato. Se il documento
viene annullato durante un aggiornamento già autorizzato, quest’ultimo può
concludersi sotto il controllo del gestore: il risultato del documento viene
comunque scartato. L’annullamento prima della fase di installazione impedisce
di avviarla. Le attività interne di aggiornamento dei certificati seguono la
configurazione di rete e le policy del sistema, separatamente dal proxy dell’app.

La lista dei certificati revocati viene consultata nella verifica: non è una
raccolta di CA HTTPS e non viene installata come certificato attendibile.
Non si riducono verifiche su nome, certificato o revoca TLS. Il client CIE usa
il proxy esplicito dell’app, senza ripiego diretto; credenziali Basic solo in
stdin privato. Curlrc personali e percorsi CA dell’ambiente sono esclusi; per il client
di sistema vengono rimossi LD_LIBRARY_PATH/LD_PRELOAD e le variabili DYLD_*. Messaggi stderr e dettagli nativi PackageKit non vengono conservati.
La diagnostica opt-in registra codici numerici, contatori, durata e indicatori
di aggiornamento, senza nomi di documenti, certificati o credenziali.

Dopo una connessione riuscita o una transazione certificati conclusa correttamente,
si ripete una sola volta la verifica sulla stessa copia privata, o sul file
appena salvato dopo la firma. **La firma non viene mai ripetuta**. Né HTTP 200
né la riuscita dell’aggiornamento provano lo stato di revoca: servono le prove
OCSP/lista di revoca autentiche e valide per l’intera catena. Un fallimento del
nuovo controllo conserva il precedente risultato leggibile.

Riferimenti: [archivi TLS nativi di curl](https://curl.se/docs/sslcerts.html),
[opzioni curl](https://curl.se/docs/manpage.html),
[API PackageKit](https://www.freedesktop.org/software/PackageKit/doc/dbus-org.freedesktop.packagekit1.Transaction.html),
[archivio CA Debian/Ubuntu](https://manpages.ubuntu.com/manpages/noble/man8/update-ca-certificates.8.html).

#### Simulazione interattiva del dialogo

`tool/tls_recovery_demo.dart` è un punto di ingresso diagnostico separato,
compilabile con `flutter build windows --release --target tool/tls_recovery_demo.dart`.
Mostra il titolo **SIMULAZIONE HTTPS**, il dialogo effettivo dell’app e risposte
interamente sintetiche. Permette di provare rifiuto, consenso con recupero
riuscito e consenso con recupero non riuscito. Non usa rete, processi esterni,
middleware, CIE, PIN, documenti, profili o archivio certificati di sistema.
Non dimostra il recupero reale da un archivio incompleto. Il programma
diagnostico va distribuito in una cartella distinta, senza sostituire
l’eseguibile dell’app o l’installer di produzione. Non esistono opzioni di
avvio della build di produzione che inventino risultati della verifica.

La raccolta è inizialmente disattivata. Si possono scegliere solo errori oppure
operazioni e tempi. Gli ultimi 200 eventi rimangono esclusivamente in memoria;
si possono cancellare o esportare volontariamente in un nuovo file JSON.
Disattivando la raccolta si cancellano gli eventi. Il rapporto è consultabile
in anteprima e non viene inviato a servizi esterni.

Il rapporto viene costruito con un elenco esplicito di campi: sistema e
architettura, versione del prototipo, capacità booleane del backend, modalità
proxy e presenza di autenticazione, operazioni, esiti, durate, codici ammessi e
contatori. Non copia messaggi o oggetti restituiti dal middleware. Non contiene
host del proxy, utente/password, PIN/PUK, percorsi, nomi dei lettori, ID CIE,
certificati, nominativi, hash o contenuto dei documenti. I log legacy nativi
rimangono disattivati, anche quando si abilita la diagnostica applicativa.

## Assistenza

La voce Assistenza si trova subito sotto Guida. Include le informazioni dello
screenshot fornito dall’utente e i riferimenti confermati il 17 ottobre 2026
sulla [pagina ufficiale CIE](https://www.cartaidentita.interno.gov.it/assistenza/).
Il pulsante Domande frequenti apre nel browser predefinito l’indirizzo indicato
dall’utente: <https://www.cartaidentita.interno.gov.it/Assistenza/#FAQ>.
Sono indicati e-mail, telefono, orari di assistenza, numero e procedura di blocco
per furto/smarrimento. La pagina distingue il servizio ufficiale CIE dal supporto
al prototipo indipendente. Non raccoglie né trasmette dati personali e non
avvia telefonate o messaggi. Un errore del browser rende visibile il link da copiare.

## Collaudi

Le prove automatiche usano server/proxy loopback e credenziali sintetiche:
configurazione diretta ed esplicita, autenticazione, HEAD, assenza di fallback,
filtri sugli indirizzi e redirect, requisiti TLS, frame stdin e passaggio dal
worker Java al recupero C++ delle CRL. Le prove ABI controllano che configurazioni
non valide non raggiungano il firmatario e che i buffer sensibili siano cancellati.
Le prove Flutter controllano validazione, persistenza non sensibile, link,
menu, report filtrati e rifiuto dei collegamenti simbolici. Esiti effettivi e
limiti dei collaudi desktop sono in [VALIDATION.md](VALIDATION.md).
Le prove reali Cambio PIN/Sblocco Carta restano rinviate dall’utente.
