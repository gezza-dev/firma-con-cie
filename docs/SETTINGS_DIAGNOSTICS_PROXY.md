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
