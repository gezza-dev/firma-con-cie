# Abbinamento privato e PIN parziale

Questa integrazione riguarda il prototipo Flutter condiviso macOS/Windows.
Non legge, migra o modifica gli abbinamenti dell’app CIE ID Universal o del
middleware ufficiale. Non installa o attiva silenziosamente CryptoTokenKit/minidriver;
la preparazione dell’accesso ai siti è ora inclusa nell’abbinamento unico UX2. La cache legacy del middleware rimane disabilitata.

## Uso

La Home riconosce automaticamente lettore e CIE. **Abbina CIE** richiede il PIN
completo di otto cifre e una conferma esplicita; Annulla non autentica la carta.
L’ABI additiva `cie_bridge_enroll`/`cie_card_enroll_v2` esegue un solo VERIFY,
controlla IAS/DAPP e SOD e restituisce il certificato esatto verificato nel DG,
con givenName/surname. Non concatena `pair` ed `enrollWeb` e non cambia PIN/PUK.
Il prefisso resta esclusivamente nel ponte nativo. La successiva pubblicazione
nel sistema usa soltanto il materiale pubblico e non autentica nuovamente.

Il componente di sistema viene osservato prima del dialogo PIN. Se manca,
il dialogo lo segnala: è comunque possibile abbinare per firmare e completare
l’attivazione successivamente. Non si eseguono installazioni privilegiate o
modifiche alle registrazioni di altri middleware. La presenza di un certificato
non equivale a un login riuscito. Stato firma, dati pubblici, pubblicazione,
componente e identità osservata sono distinti, senza promuovere uno stato ignoto.

Le vecchie registrazioni con solo prefisso rimangono utilizzabili per firmare.
**Completa abbinamento** richiede esplicitamente una nuova lettura con il PIN
completo; non usa di nascosto il PIN parziale. **Completa accesso ai siti** per
un record v2 riutilizza il certificato già verificato anche dopo il riavvio,
senza lettore o PIN. Un errore di pubblicazione conserva l’abbinamento per la
firma e i dati pubblici disponibili; non viene ritentata l’autenticazione.
La scrittura dei dati pubblici precede quella del prefisso: se fallisce, un
abbinamento precedente non viene sovrascritto. Gli store non sono una transazione
atomica; gli errori di fase restano visibili e non si finge un rollback completo.

L’elenco mostra Nome e Cognome per i nuovi abbinamenti, anche senza carta.
**Rimuovi CIE** coordina le sole copie del prototipo: pubblicazione macOS,
certificato Windows con verifica di proprietà, metadati e prefisso. Il PIN non
serve. Se una fase fallisce, la rimozione resta incompleta e può essere ripetuta.
La rimozione multipla si ferma al primo errore e conserva le CIE ancora presenti.
Non vengono rimossi certificati estranei o abbinamenti dell’app originale.

In Firma Elettronica, per una CIE abbinata selezionata, attivare Usa le ultime quattro cifre
del PIN. La scelta è esplicita; resta disponibile il PIN completo. Il PIN parziale
vale per PAdES, anche con grafica, CAdES e cofirma P7M. Dart passa soltanto le ultime
quattro cifre: il ponte nativo legge il prefisso e ricompone il PIN in un buffer
locale, poi l’adattatore verifica nuovamente la carta prima dell’autenticazione.
Le API legacy continuano a richiedere otto cifre. Una carta non abbinata o un
archivio non leggibile non causano un tentativo con quattro cifre né un fallback
con altre credenziali. Dopo un PIN non accettato, controllare i dati e ripetere
l’abbinamento se il PIN è stato cambiato; non ripetere alla cieca.

## Protezione dei dati

macOS usa una password generica nel Portachiavi, non sincronizzata, con protezione
WhenUnlockedThisDeviceOnly per i nuovi elementi. Windows usa credenziali generiche
nell’archivio del corrente utente con persistenza locale al PC. Il servizio è
`it.giancarloezza.CIEID.FlutterPrototype.pairing.v1`; l’account/target contiene
l’identificativo della carta. Il valore segreto contiene soltanto quattro cifre.
Non vengono salvati il PIN completo, le ultime quattro cifre o il PUK.
Il nuovo materiale pubblico v2 (certificato DER e Nome/Cognome, nessun prefisso)
usa un namespace distinto: servizio `.public.v2` nel Portachiavi o suffisso
`/public.v2` in Credential Manager. Formato binario versionato, lunghezze limitate
e nessun fallback a file. Anche questi dati identificano l’intestatario e restano
locali al suo account. L’elenco dei prefissi ignora esplicitamente i record pubblici.
Le copie pubblicate per CTK/MY rimangono separate dall’archivio dei prefissi.

La protezione dipende dagli accessi del sistema operativo; non protegge da un
account utente compromesso. L’identificativo è un dato personale locale e può
comparire nell’interfaccia del gestore credenziali. Non si usano file cifrati con
chiavi incorporate nell’app, fallback in chiaro o sincronizzazioni personalizzate.
Non si promette la cancellazione forense dei backup del sistema operativo.

I buffer nativi di input e ricomposizione vengono azzerati e le richieste sono
serializzate. Firma e abbinamento usano una connessione condivisa con transazione PC/SC
che serializza gli APDU, senza reinvio automatico. La transazione viene acquisita
dopo il solo reset iniziale e rilasciata con reset alla chiusura. Questo evita
l’incompatibilità osservata sul Mac nella lettura dell’identificativo con
connessione esclusiva; il preflight corretto completa IAS/DAPP senza alcun PIN. I dati copiati internamente dalle API del sistema
operativo e le stringhe gestite Dart non consentono garanzie di azzeramento
completo. Il prefisso non attraversa l’ABI JSON/FFI e non entra in diagnostica,
preferenze, report o esportazioni. Nessuna password viene richiesta in chat.

Se si avvia Cambio PIN o Sblocco Carta con dati formalmente validi, il ponte
rimuove prima l’abbinamento locale della carta; se la rimozione fallisce, la
modifica non parte. Questo evita prefissi obsoleti anche quando l’esito della
modifica fisica è incerto. L’abbinamento va ripetuto dopo l’operazione; ciò può
servire anche se il tentativo non ha modificato il PIN. Modifiche effettuate da
altre app non sono osservabili automaticamente. Le prove reali di Cambio PIN e
Sblocco Carta restano rinviate dall’utente.

## Test separati dalle carte reali

`native/tests/test_pairing.py` usa soltanto un adattatore sintetico e un archivio
in memoria, in una libreria di test distinta dalla produzione. Controlla
validazione, autenticazione unica, cambio carta, PIN errato/bloccato, archivio
non disponibile prima del VERIFY, ricomposizione nativa e rimozioni.
I test ABI PIN/PUK usano anch’essi questa libreria isolata: nessuna scrittura
nell’archivio protetto reale.

`cie_pairing_store_tests` verifica lettura, aggiornamento, elenco e rimozione con
credenziali sintetiche nel servizio **pairing.tests.v1**, separato dagli abbinamenti
del prototipo. Rimuove il record creato e controlla che gli altri record del
servizio di test restino identici. Va avviato esplicitamente, non è nel CTest
automatico. Il test runtime controlla prima tutti gli hash del manifest:

```
python scripts/test_pairing_runtime.py --runtime native/runtime/windows-pairing --report pairing.json --protected-store-test
```

I nuovi test `test_enrollment.py` e `enrollment_state_tests.cpp` coprono
una sola autenticazione, recupero senza PIN, record vecchi/corrotti, errori di
scrittura per fase, preservazione del prefisso e rimozioni incomplete. Usano
solo archivi in memoria. Il test esplicito `cie_pairing_store_tests` comprende
anche round trip/elenco/rimozione del namespace pubblico, ma non è stato eseguito
con i nuovi record sui sistemi reali in questo blocco.

I test Flutter controllano conferma/annullamento, lunghezza del PIN, invio singolo,
visibilità dell’opzione parziale, pulizia del campo, archivio non disponibile e
assenza di identificativi/segreti nella diagnostica. Le prove con la CIE reale
sono distinte e richiedono inserimento personale del PIN nel prototipo.
Linux non dispone ancora di un adattatore per l’archivio protetto: l’abbinamento
è disabilitato, senza fallback a file. Non viene pubblicata una release.

## Esiti precedenti e nuovo collaudo UX2

Sul Mac l’abbinamento reale è riuscito, resta disponibile dopo riavvio e permette
firme PAdES/CAdES con le ultime quattro cifre. La verifica indipendente conferma
integrità e contenuto; il controllo corrente di catena e revoca è positivo.
Su Windows i test software e Credential Manager isolato passano, con Release e
GUI collaudate. Anche le prove CIE reali Windows sono riuscite: abbinamento
persistente e firme PDF/P7M con PIN parziale, integrità confermata da OpenSSL
e backend. La successiva verifica corrente di fiducia/revoca è positiva; la
validità storica resta indeterminata senza una marca attendibile. Il caricamento ctypes dei test
usa soltanto la cartella runtime privata tramite `os.add_dll_directory`, senza
modificare impostazioni o PATH di sistema. Nessun Cambio PIN/Sblocco Carta reale.
Esiti e limiti completi in [VALIDATION.md](VALIDATION.md).

### Riconoscimento automatico e concorrenza

La scansione iniziale e i tick a un secondo avvengono fuori dall’isolate UI.
`SCardGetStatusChange` usa timeout zero e un contesto PC/SC posseduto dalla sola
osservazione, senza thread bloccati o cancellazioni globali. Solo per una nuova
presenza si tenta l’identificazione pubblica, con connessione esclusiva e senza
reset/VERIFY: se un altro client possiede la carta, viene differita. Una CIE già
riconosciuta è ricordata entro la stessa epoca di presenza (ATR e contatore
inserimenti); una carta non CIE non viene interrogata a ogni tick. Gli errori
transitori hanno un intervallo minimo di tre secondi. Nessun certificato o PIN
viene letto dalla carta dal monitor. Al cambio di presenza e ogni cinque tick
viene osservato lo stato pubblico del componente di sistema, senza operazioni
private, così l’attivazione o una pubblicazione ritardata aggiornano la Home.

Un solo tick può essere in corso. Prima delle operazioni dell’app e dei dialoghi
sensibili il controller sospende e attende il tick corrente; risposte superate
non cambiano la selezione. L’app inattiva sospende il monitor, anche mentre il
browser chiede il PIN. Il monitor non forza reset e non naviga verso la Home.
La scelta automatica avviene solo con una CIE non ambigua; il cambio carta
invalida anteprima e risultati della firma, preservando il documento selezionato.
I tempi con lettori reali e la convivenza col browser restano da collaudare.

Il nuovo flusso UX2 è coperto da test software condivisi e build macOS/Windows.
Le prove reali del nuovo abbinamento, del recupero e della rimozione coordinata
sono rinviate dall’utente, insieme a quelle del segno PAdES. Le precedenti prove
riuscite non sono presentate come collaudo della nuova procedura.
