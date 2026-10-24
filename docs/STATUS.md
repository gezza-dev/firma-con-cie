# Stato del progetto e verifiche

Situazione al 24 ottobre 2026. [VALIDATION.md](VALIDATION.md) conserva il diario storico: le attività da svolgere nelle voci precedenti descrivono lo stato di quel momento.

## Hover del menu condiviso (24 ottobre)

Il menu laterale Flutter usa ora righe Material interamente interattive:
al passaggio del mouse si evidenzia solo la voce interessata e il puntatore
diventa una mano. Il comportamento è condiviso da Linux, Windows e macOS,
nei temi chiaro/scuro e nelle modalità estesa/compatta. La selezione resta
distinta dall'hover; durante le operazioni che bloccano la navigazione le
voci sono disabilitate e il puntatore torna normale. Conservati scorrimento,
navigazione da tastiera e descrizioni delle icone in modalità compatta.

Superati analisi statica e 346 test Flutter, incluse le quattro integrazioni
software runtime/DSS e 15 nuove varianti di test del menu sulle tre piattaforme
simulate. I test confrontano anche i pixel dello sfondo delle singole righe.
Il collaudo desktop nativo Windows/macOS resta da eseguire.

Preparato e installato su Linux il pacchetto di test
`0.1.0~test20261024.20`, con GUI Release compilata su Ubuntu 24.04 con due job
e runtime nativo/DSS riutilizzato dopo confronto degli hash. Superati i
controlli del pacchetto, compreso il ciclo installazione/aggiornamento/rimozione
in una cartella isolata; verificati tutti i 737 file installati sul computer.
L'utente ha confermato il collaudo dell'interfaccia aggiornata con esito
positivo. Nessuna modifica ai browser o prova sulla CIE eseguita dall'agente.
Pacchetto, snapshot dei sorgenti e rapporti restano artefatti locali esclusi
da Git.

## Pacchetti Linux x86_64 per distribuzione (24 ottobre)

Preparate ricette e pacchetti di test `.19` per Ubuntu 24.04 LTS/Debian 13,
Fedora 44 e Arch rolling. GUI Release ricompilata su Ubuntu 24.04 con due job,
runtime nativo/DSS riutilizzato dopo confronto degli hash e senza modificarne
la provenienza. Il confezionamento ora dichiara esplicitamente EGL/OpenGL/GLES,
necessari all'avvio anche se caricati dinamicamente.

Superati 11 test del confezionamento, 331 test Flutter e analisi statica;
in ogni ambiente verificati installazione/aggiornamento/rimozione, 737 file,
61 ELF, Java/DSS privato, avvio GUI su display virtuale con PC/SC bloccato e
smoke nativo senza `--detect`. Durante queste prove isolate la `.18`
installata sul computer è rimasta invariata; nessuna modifica ai browser,
ai permessi Snap o prova sulla CIE. In seguito sono state installate, su
richiesta dell'utente, la `.19` e la `.20` (collaudata come descritto sopra).
Gli artefatti RPM e Arch restano alla `.19`. Prima del commit ripetuti i
12 test Python del confezionamento e del supporto Xvfb, tutti superati.
Restano separati i collaudi su desktop completi e SELinux di Fedora.
[Dettagli, versioni, isolamento e limiti](LINUX_DISTRIBUTION_PACKAGES.md).

## Configurazione browser Linux solo nella Home (23 ottobre)

Rimossi i riquadri Firefox/Firefox Snap e Google Chrome dalle Impostazioni.
Le procedure restano disponibili solo in cima alla Home quando le ispezioni
in sola lettura rilevano una configurazione da completare o un errore da
controllare. I browser già configurati non mostrano il riquadro; restano
invariati il filtro dei profili non inizializzati e il controllo del permesso
Snap. I messaggi della CIE abbinata e la Guida, in italiano e inglese,
rimandano ora alla Home. Questa modifica sostituisce i precedenti riferimenti
all'accesso permanente dalle Impostazioni nelle sezioni storiche sottostanti.

Verifiche software: analisi Flutter senza problemi, 331 test superati
(incluse le quattro integrazioni runtime/DSS), controllo repository e cataloghi
IT/EN superati. I test aggiornati verificano l'assenza dei due riquadri nelle
Impostazioni e la loro scomparsa dalla Home dopo una configurazione simulata.
Resta il warning di hit-test già noto in `pairing_test.dart`; nessun test
fallito o saltato. Nessuna modifica ai browser, prova sulla CIE o installazione
di pacchetti in questa verifica.

Successivamente ricompilata l'app Linux Release con due job e preparato il
pacchetto locale `0.1.0~test20261023.18`, riutilizzando il runtime nativo/DSS
invariato dopo confronto degli hash. Superati i controlli del pacchetto:
734 file, 61 ELF, launcher e icone, runtime Java privato e ciclo
installazione/aggiornamento/rimozione in una radice isolata. La versione `.18`
è stata poi installata su questo computer, con verifica degli hash di tutti
i 734 file. SHA-256 del `.deb` di test:
`4e940a9634923871764754a05a1ad6f1270def72e56f1b64cebd9e3a9b48c4c2`.
L'utente ha confermato il collaudo della nuova interfaccia riuscito.
Nessuna modifica ai browser o nuova prova sulla CIE. Il pacchetto resta un
artefatto locale di test, escluso dal repository insieme ai rapporti locali.

## Verifica Windows di main `16da166` (23 ottobre)

Aggiornata la copia Windows con fast-forward dal commit `5c17a7a` a
`16da166c98e2c1587f0aadb9e7e395fe2dc36ada`, senza modifiche locali iniziali.
Compilati l'app Release 1.0.0 e un nuovo installer completo di runtime privato,
PDFium, DSS/JVM, componente Web e licenze. Il confronto dei sorgenti non
richiede una nuova build MinGW: il cambiamento del bridge riguarda un ramo
Linux escluso su Windows, quello PKCS#11 è solo formattazione e le nuove
dipendenze JVM riguardano Linux. Conservati binari, manifest e provenienza
dei singoli moduli già verificati, senza attribuirli al nuovo commit dell'app.

Analisi Flutter senza problemi; **327 test superati e 4 opzionali saltati**.
Superati i 15 gruppi CTest del bridge, 4 del provider Windows, 2 geometrici,
2 del runner Win32 e 1 PKCS#11: compresi 161 controlli minidriver, 203 PKCS#11,
21 sullo stato del pacchetto e 114 sui pulsanti della finestra. Superati anche
i 50 controlli dell'installer Inno isolato, lo smoke test del runtime distribuito,
i 14 casi DSS/LTA, i 19 di validità storica e i 37 controlli di rete su loopback.
I test dei nuovi servizi Linux usano servizi simulati su Windows; la produzione
non li istanzia e non ne mostra i controlli.

Nella GUI Windows verificati avvio, navigazione, Home con componente corrente,
notifiche **Chiudi** in italiano e **OK** in inglese, temi chiaro/scuro e
ripristino delle preferenze iniziali. Il controllo reale in sola lettura del
componente installato restituisce codice 0; nessun avviso di aggiornamento
superfluo. Le condizioni componente assente/non corrente e l'attivazione macOS
sono coperte dai test software, senza installazioni o attivazioni reali qui.

Completata anche la prova con lettore e CIE reali, senza PIN: rimozione e
reinserimento con app minimizzata, processo observer ancora attivo e miniature
rispettivamente grigia e a colori al ripristino della Home. Verificati nella
GUI restringimento della finestra, navigazione a Verifica Firma, allargamento
tramite massimizzazione e ripristino; i controlli si adattano e rispondono.
La chiusura normale con X termina sia l'app sia l'observer. Gli hash di
abbinamenti, impostazioni, preferenze di firma, archivio certificati pubblici
e registrazioni Calais risultano invariati dopo il collaudo.

La distribuzione contiene 883 file, inclusi 50 JAR; verificati hash dei payload,
identità tra build provata e app confezionata e 649 file di licenza/avvisi
conservati byte per byte. L'installer non è stato installato sul sistema e
rimane un pacchetto locale non firmato Authenticode. Nessuna autenticazione
browser, firma con CIE, richiesta PIN o modifica della configurazione browser.
Report esterno ai sorgenti: `windows-main-16da166-20261023`.

## Browser configurati nel riquadro della CIE su Linux

Il testo sotto ogni CIE abbinata elenca ora **Firefox**, **Firefox Snap** e/o
**Google Chrome**, separati da virgole, quando le rispettive registrazioni
risultano configurate. Per Firefox basta almeno un profilo configurato della
rispettiva versione; nomi dei profili e duplicati sono esclusi. Firefox Snap
richiede anche il permesso `pcscd` verificato. In assenza di browser configurati,
il testo invita ad aprire le Impostazioni per configurarli. Controllo in corso
e lettura non riuscita hanno messaggi distinti.

I dati provengono dalle stesse ispezioni in sola lettura degli avvisi Home,
senza una nuova lettura per ogni carta, e si aggiornano al ritorno nell'app e
dopo la chiusura dei wizard. Conservate le segnalazioni per certificato pubblico
non predisposto, componente non disponibile e rimozione pendente. Il testo su
Windows e macOS è **Accesso ai siti con CIE configurato. Apri il sito nel
browser.** Il browser continua a richiedere il PIN completo.
La configurazione del modulo non viene equiparata a un login riuscito.

Il collaudo usa browser e carte simulati, con controlli su elenco, permesso
Snap, aggiornamento dello stato, esiti tardivi, conferma del wizard Chrome,
italiano/inglese e testo al 200%. Superati 326 test Flutter senza esclusioni,
inclusi 17 nuovi casi; analisi statica pulita. Inclusi i test di verifica di
documenti sintetici con runtime reale e worker DSS privato. Per la successiva
revisione dei testi **Accesso ai siti con CIE configurato.** sono passati 73
test mirati della Home, dell'attivazione e della localizzazione, con analisi
statica pulita. I test non hanno avviato o modificato browser reali né eseguito
prove sulla CIE.

Preparati e installati su richiesta dell'utente i pacchetti di test `.14` e
`0.1.0~test20261023.15`, con build release a 2 job e documentazione aggiornata.
Superati i controlli isolati del pacchetto, del worker DSS dopo estrazione e
dei 61 ELF; verificati tutti i 734 file installati, launcher, icone e
`dpkg --verify`. Il runtime nativo/DSS è rimasto invariato. L'agente non ha
avviato l'app, modificato i browser o eseguito prove sulla CIE durante queste
installazioni. Il 23 ottobre l'utente ha confermato il collaudo riuscito della
nuova Home nella versione `.15`; la conferma non riguarda un nuovo accesso ai siti.
[Testo e criteri di visualizzazione](WEB_AUTHENTICATION.md#avvisi-nella-home).

## Avvisi accesso ai siti nella Home Windows e macOS

Il controllo del componente alimenta ora un unico riquadro in cima alla Home,
visibile soltanto quando occorre intervenire, anche senza lettore o CIE
abbinate e con archivio degli abbinamenti non leggibile. Windows mostra le
istruzioni per l'installer; macOS propone attivazione, aggiornamento o apertura
delle Impostazioni di Sistema. Se l'app è precedente al componente selezionato,
invita ad aprire l'app più recente senza proporre un downgrade. Il riquadro
scompare quando la rilettura conferma il componente pronto. I pulsanti del
componente non vengono duplicati su tutte le carte. Restano invariati i
riquadri condizionali di configurazione Firefox e Chrome per Linux.

Superati su Linux 309 test Flutter, senza test saltati, inclusi 10 nuovi casi
per criteri di visibilità, posizione, assenza/più abbinamenti, archivio non
leggibile, conferma/annullamento, risposta positiva senza stato attivo,
componente più recente e interfaccia inglese con testo al 200%. Inclusi i
test di verifica documenti con runtime reale e worker DSS privato; PIN e carte
sono simulati nei test dell'interfaccia. Superati anche i 36 gruppi CTest
nativi con protezione dalle chiamate alla carta; analisi statica pulita. Il collaudo
nativo/visivo su Windows e macOS resta da eseguire sui rispettivi sistemi.
Nessuna modifica ai browser, installazione di pacchetti o prova sulla CIE.
[Comportamento degli avvisi](WEB_AUTHENTICATION.md#avvisi-nella-home).

## Verifiche precedenti Windows e interfaccia condivisa

Firma con CIE 1.0.0: completata la verifica Windows del nuovo nome pubblico e
delle icone. Il titolo resta disponibile per taskbar e accessibilità, mentre
la barra del titolo visibile mostra soltanto icona e pulsanti nativi.
Conservati il percorso storico delle impostazioni e delle immagini di firma
e il seriale PKCS#11 derivato dal certificato, indipendentemente dalla nuova
etichetta pubblica. I test controllano i byte dei dati salvati e dell'immagine,
l'etichetta del certificato in un archivio WinCrypt in memoria e la rimozione
del solo vecchio eseguibile durante l'aggiornamento.

La Home Windows controlla ora la versione esatta del componente Web tramite
il percorso registrato e gli hash del payload incluso nell'app. La verifica
asincrona avviene all'avvio e al ritorno in primo piano, senza lettore, PIN,
elevazione o scritture di configurazione. Quando occorre un aggiornamento,
la CIE rimane abbinata per firmare e compare «Aggiorna accesso ai siti»;
il pulsante mostra le istruzioni per l'installer, che continua a gestire UAC.
Non vengono avviati aggiornamenti, downgrade o nuove pubblicazioni automatiche.
[Flusso, conservazione e limiti della verifica](WINDOWS_INSTALLER.md).

Collaudo del nuovo controllo: analisi Flutter pulita, 264 test Flutter
superati e tre integrazioni facoltative saltate; quattro gruppi CTest del
provider superati, compresi 21 controlli della nuova policy di sola lettura,
161 del minidriver, 410 del catalogo e 75 della policy setup. Superati i 50
controlli dell'installer isolato. App e installer Windows 1.0.0 ricompilati;
il 22 ottobre l'utente conferma il test riuscito delle ultime modifiche.
Le verifiche automatiche e della Home non hanno autenticato carte, richiesto
PIN o modificato abbinamenti, impostazioni, certificati o registrazioni Windows.
Il componente operativo e le dipendenze rimangono quelli già compilati e
collaudati; per questo controllo sono ricompilati runner Flutter e helper.
Log, rapporti e binari restano fuori dal repository.

Collaudo desktop Windows precedente del 22 ottobre: avvio della finestra centrato
nell'area utile del monitor, titolo «CIE ID» centrato su entrambi gli assi e
pulsanti di sistema mantenuti nativi. Corretta la regressione che, a finestra
massimizzata, interpretava i clic su Riduci, Ingrandisci/Ripristina e Chiudi
come trascinamento del titolo. Il test dedicato usa i rettangoli effettivi
forniti da Windows e supera 114 controlli, compresi due cicli di
massimizzazione, minimizzazione e ripristino. L'utente conferma il collaudo
con il mouse di tutti e tre i pulsanti e il successo delle ultime modifiche.
[Implementazione, regressioni e limiti multipiattaforma](DESKTOP_WINDOW_SIZING.md).

Aggiornati i messaggi della pagina e del dialogo di conferma del cambio PIN,
con cataloghi italiano/inglese coerenti. Il 22 ottobre l'utente conferma anche
il successo del cambio PIN sulla CIE reale. Le prove automatiche di questa
attività usano esclusivamente servizi sintetici; non eseguono altre modifiche
del PIN o operazioni PUK sulla carta. [Testi, flusso e collaudo](PIN_PUK.md).

Verifica finale dello snapshot Windows prima del commit: analisi Flutter
senza problemi, 251 test Flutter superati e tre integrazioni facoltative
saltate. Superati quattro gruppi CTest desktop su MSVC: geometria C/C++,
ridimensionamento del runner e pulsanti della barra del titolo. Gli installer
1.0.0 sono stati ricompilati durante il collaudo e conservano le dipendenze,
le licenze e il componente web; i binari rimangono esclusi dal repository.

Correzione del blocco PC/SC su macOS: il campionamento del processo ha mostrato
`SCardGetStatusChange` fermo in una richiesta XPC e la chiusura Flutter in attesa
dell’isolate FFI. Il rilevamento automatico e manuale usa ora un eseguibile
C++ privato, con supervisor e client Dart condivisi fra macOS, Windows e Linux.
Timeout di cinque secondi, pausa automatica di otto secondi dopo un timeout,
arresto su sospensione/chiusura e uscita anche quando si chiude il canale del
genitore. Il wrapper diagnostico inoltra l’annullamento. Il processo non accetta
PIN, firme o altre operazioni private. Nessun ripiego nel processo della GUI.
La build richiede di confezionare il nuovo eseguibile accanto al bridge.

Verifiche macOS: 230 test Flutter superati, tre integrazioni facoltative saltate,
analisi pulita e 26 CTest nativi superati. I test eseguono processi sintetici
bloccati, crash, protocolli errati/output eccessivo, annullamento durante l’avvio,
chiusura dell’app e controllo dei figli terminati. Il supervisor C++ reale è
provato con un bridge simulato bloccato, anche alla scomparsa del genitore.
Una copia separata della GUI macOS, con lettore simulato bloccato e senza
estensione CTK, è uscita mentre il figlio era ancora in attesa; entrambi i
processi sono terminati. Verificati anche il timeout e la pausa fra i sondaggi.
Al momento di quel collaudo macOS, build e prove Windows/Linux restavano da
eseguire. Il successivo collaudo Windows del 22 ottobre ha ricompilato bridge
e observer: 15 CTest nativi, 49 controlli dell'installer isolato e smoke test
del runtime superati. Rimozione e reinserimento della CIE rilevati anche con
app minimizzata, miniatura grigia/a colori coerente con la presenza, carta
assente selezionabile per preparare il documento e nessun observer residuo
dopo la chiusura. Questo collaudo di rilevamento non ha richiesto PIN o firme.
La verifica del processo su Linux rimane da ripetere sul relativo sistema.

Le miniature delle CIE abbinate nella Home e nella selezione di Firma
Elettronica condividono il controllo della presenza: colore per la carta
rilevata, scala di grigi per le altre o quando il rilevamento non è disponibile.
Il confronto usa l'identificativo pubblico della CIE o il numero carta salvato,
senza autenticazione. In Firma Elettronica le carte assenti restano selezionabili
per preparare il documento. La Home presenta il pulsante di abbinamento sempre
nella stessa posizione e lo disabilita se manca una nuova CIE disponibile.

Allineati il messaggio di presenza e il pulsante di abbinamento della Home
al bordo visibile della miniatura e ai dettagli della carta. Il rilevamento
pubblico prosegue anche quando la finestra perde il primo piano o è minimizzata;
resta sospeso durante operazioni, dialoghi, sospensione del sistema e chiusura.
Il processo separato conserva timeout e annullamento, senza ricevere il PIN.

Palette Material 3 condivisa basata sul blu del logo `#4C65AD`, nelle varianti
chiara e scura. Pulsanti, campi, selezioni, menu, superfici e dialoghi usano
i ruoli coordinati del `ColorScheme` e gli stati Material per disabilitazione,
passaggio del mouse, focus e pressione. Eliminati i colori azzurri imposti
separatamente ai pulsanti; il bordo del trascinamento e le icone di errore
seguono la palette. Conservati struttura delle schermate, dimensione delle
voci laterali, selezione del tema e sfondi abbinati alle icone esistenti.
I controlli automatici verificano contrasto dei testi e dei bordi, stati dei
pulsanti e corrispondenza degli sfondi delle icone in entrambi i temi.
Analisi pulita e 250 test Flutter superati, con tre integrazioni facoltative
saltate. I test dei controlli coprono le varianti di piattaforma macOS,
Windows e Linux; build Universal macOS firmata Apple Development e verificata
con controllo approfondito della firma. Collaudo visivo dei due temi eseguito
nelle Impostazioni, ripristinando poi la preferenza chiara già selezionata.

Personalizzazione successiva del tema scuro: gli accenti dei controlli usano
una palette Material verde chiaro, conservando superfici, testi neutri e colori
di errore. La palette del tema chiaro resta invariata. I controlli di contrasto
e degli stati dei pulsanti coprono anche questa variante verde. Analisi pulita
e 251 test Flutter superati, con tre integrazioni facoltative saltate.

Aggiornamento successivo al confronto ufficiale: compatibilità CryptoAPI
`AT_KEYEXCHANGE`, modulo PKCS#11 Windows con digest/verifica pubblica condivisi
con Linux, scadenza del certificato nella Home e ricerca manuale delle release
del progetto. App/installer Windows 1.0.0 ricompilati: 220 test Flutter, 3
integrazioni facoltative saltate e 894 controlli isolati tra provider, catalogo,
setup e installer, inclusa la successiva regressione Chrome. PIN e motori
crittografici conservati. Dopo l'installazione del componente corretto,
l'utente conferma l'accesso riuscito al portale CIE da Chrome, Edge e Firefox
su Windows. Le suite automatiche usano componenti simulati e non inviano PIN
alla CIE reale; i collaudi browser sono eseguiti personalmente dall'utente.
[Implementazione, percorsi e limiti](MIDDLEWARE_COMPATIBILITY_UPDATE.md).

Correzione successiva per Chrome: riprodotto `No_client_certificate` prima del
PIN, con apertura KSP silenziosa fallita (`NTE_BAD_KEYSET`) quando firma e
alias CryptoAPI condividevano il nome. I due ruoli ora hanno nomi e indici
distinti, conservando il contenitore di firma già pubblicato. Passano i tre
CTest Windows, inclusi 161 controlli del minidriver. Dopo l'aggiornamento
dell'installer con UAC (exit 0), la stessa apertura silenziosa della chiave
KSP è riuscita; verificate le 12 registrazioni e il checksum del componente
installato. Il nuovo accesso completo da Chrome è confermato dall'utente:
con PIN completo e dopo «Prosegui» nella pagina di rilascio attributi si apre
l'area riservata. Il log opt-in conferma esito 0 per autenticazioni e firme.
L'utente ha poi confermato il nuovo collaudo positivo anche con Edge e Firefox.
La precedente pagina bianca dopo il consenso non si è ripresentata nella
prova diagnostica; la sua causa non è stata stabilita. Il launcher abilita
solo la registrazione numerica del componente, senza modificare impostazioni
di sicurezza, profilo del browser o codice installato.
Il controllo ripetibile
`scripts/check_windows_web_key.py` apre la chiave senza firma, PIN o riparazioni.

| Ambito | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Interfaccia condivisa | Compilata Universal; eseguita su Apple Silicon | Compilata/eseguita x64 | Collaudo desktop da completare |
| Adattamento finestra | Implementato; build/collaudo AppKit pendenti | App x64 compilata; ridimensionamento ripetuto e navigazione collaudati con Skia | Adattamento GNOME confermato dall'utente; collaudo KDE della finestra aggiornata da completare |
| Middleware e SDK | Compilati ARM64/x86_64; test nativi su ARM64 | Backend MinGW x64 e componenti MSVC; test su Windows | Compilazione/test nativi senza carta |
| Firma PAdES/CAdES | CIE reale verificata | CIE reale verificata | PDF e P7M con CIE reale e PIN parziale verificati |
| Abbinamento e PIN parziale | Persistenza e firme reali verificate | Persistenza e firme reali verificate | Abbinamento, persistenza e firme con PIN parziale verificati |
| Accesso ai siti | CryptoTokenKit e accesso Safari al portale CIE verificati | CSP/KSP aggiornato: accesso al portale CIE con Chrome, Edge e Firefox confermato dall'utente dopo la correzione dei contenitori | Test reali Mozilla Firefox, Firefox Snap e Chrome desktop con PIN completo confermati riusciti dall’utente |
| Cambio PIN e Sblocco Carta | Test software; collaudo reale da completare | Test software; collaudo reale da completare | Collaudo reale non eseguito |
| DSS/LTA con JVM privata | Predisposto e testato | Predisposto e testato | Integrato Linux x86_64; worker privato e test software superati |

L’esecuzione su un sistema non prova automaticamente la compatibilità con tutti i lettori, le CIE, i browser o i servizi. Il formato LTA non implica da solo una validazione storica positiva: servono prove e una catena di fiducia sufficienti.

## Configurazione guidata Chrome Linux (23 ottobre)

**Configura Chrome** è disponibile nelle Impostazioni generali e nella Home
quando Chrome desktop richiede configurazione. La procedura legge lo stato
senza inizializzare NSS; propone riepilogo e conferma, richiede Chrome chiuso
e controlla nuovamente il piano prima di scrivere. Usa il database NSS desktop
condiviso dell’utente, senza selezione di profili Firefox o percorsi Snap.
NSS genera il solo record CIE in un database temporaneo con PC/SC bloccato;
la modifica atomica conserva i byte degli altri record e non scrive nei
database certificati/chiavi. Il monitor della carta è sospeso nel dialogo.
Il browser richiede ancora il PIN completo; non si eseguono login di prova.

Superati 18 test backend Chrome, inclusa registrazione NSS reale temporanea
con sentinella che esclude il caricamento di moduli estranei. I 13 nuovi test
Flutter coprono conferma/annullamento, piano cambiato, nessun retry, stato Home,
accesso dalle Impostazioni, italiano/inglese e finestra piccola con testo al
200%. Suite completa: 299 test Flutter senza esclusioni, 36 gruppi CTest e
analisi pulita. Conservati DSS/LTA e JVM privata; passano nuovamente 14 casi
LTA e 19 controlli storici. La build release usa 2 job. Nessuna configurazione
browser reale o operazione sulla CIE viene eseguita dai test.
Pacchetto `0.1.0~test20261023.11` preparato: 732 file e 61 ELF verificati,
helper Chrome controllato in sola lettura con HOME temporanea, worker DSS
funzionante dopo estrazione e ciclo dpkg isolato superato. Non installato;
versione `.10` e tutti i file installati invariati. Nessun browser configurato
o avviato e nessuna prova reale sulla CIE.
[Procedura e limiti](LINUX_CHROME.md#configurazione-guidata-nellapp).

Correzione successiva del dialogo Chrome: **Rileggi** viene nascosto quando
Chrome è pronto da configurare; resta disponibile per database non inizializzato
o errori da ricontrollare. Superati 30 test dei wizard e analisi pulita.
Pacchetto `.12` preparato e installato su richiesta dell’utente: 732 file
verificati e `dpkg --verify` superato. Rispetto alla `.11` cambiano soltanto
il codice AOT dell’interfaccia e `LINUX_CHROME.md`; runtime nativo/DSS invariati.
Nessuna app o browser avviati, configurazione browser eseguita o prova sulla CIE.
L'utente ha successivamente confermato il test riuscito della configurazione
guidata Chrome con il dialogo aggiornato; non è una nuova prova di accesso ai siti.


## DSS/LTA Linux x86_64 (23 ottobre)

Il worker EU DSS 6.5.1 è ora assemblato anche per Linux x86_64 con JVM
Temurin 21.0.12.1+1 privata, JDK/JRE Linux fissati tramite hash e i 50 JAR
già bloccati. App Dart e script di test selezionano la JVM Linux senza
ripiegare su macOS. Linux ARM64 resta non coperto. Nessuna installazione
Java di sistema o modifica agli archivi di fiducia.

Superati 14 casi LTA sintetici, 19 controlli storici e 37 controlli di rete
nativo/Java su loopback. Le prove comprendono rinnovi PDF/CAdES, firme e TSA
scadute, marche alterate, revisioni non protette e rifiuto delle radici di
prova nella policy di produzione. Tutti i 286 test Flutter sono superati,
comprese le tre integrazioni documentali opt-in e l'avvio del worker Linux
tramite Dart; superati anche 35 gruppi CTest nativi e l'analisi Flutter.
Lo smoke usa documenti sintetici senza `--detect` e non accede alla CIE.
Il `.deb` include JVM/worker e relative licenze quando presenti nel bundle;
entrambi i livelli di strumenti di test sono esclusi dal runtime distribuito.
Pacchetto `0.1.0~test20261023.10` preparato con 731 file e 61 ELF verificati:
worker DSS funzionante dopo l'estrazione in un percorso diverso, ciclo dpkg
installazione/aggiornamento/rimozione isolato e simulazione APT superati.
Non installato sull'host; versione `.9` e relativi file conservati. Nessuna
app o browser avviati, nessuna prova reale sulla CIE o modifica Snap.
[Build, test e limiti](LINUX_DSS_LTA.md).

Successivamente la versione `.10` è stata installata sull'host su richiesta
dell'utente: verificati i 731 file e `dpkg --verify`. La JVM e i JAR installati
superano 14 casi LTA sintetici e 19 controlli storici, usando il solo harness
di sviluppo esterno. Analizzati anche 11 documenti PDF/P7M sintetici, compresi
file senza firma, malformati, marche alterate e revisioni non coperte; gli
originali sono rimasti invariati e la policy di produzione non ha promosso
le CA sintetiche a fiducia. Superato il test Dart che avvia il worker dal
percorso installato. Nessuna CA di prova installata, documento caricato online,
app/browser avviati o operazione sulla CIE; configurazioni browser conservate.


## Chrome desktop Linux (23 ottobre)

È predisposta l'integrazione NSS del provider Linux per Google Chrome desktop
`.deb`, con il PIN completo: selezione SSL-client e firma attraverso le API NSS
usate da Chromium, configurazione esplicita/idempotente del solo modulo CIE e
rimozione limitata alla registrazione corrispondente. I test di configurazione
usano database SQL temporanei e il provider simulato; non modificano certificati,
chiavi o moduli estranei. Il comando predefinito mostra soltanto il piano senza
inizializzare NSS. L'installer non configura il browser.
Il pacchetto `.deb` `0.1.0~test20261023.2` è stato installato e il modulo
registrato con PC/SC bloccato, preservando gli archivi certificati/chiavi NSS
e la configurazione Firefox controllata. L'utente ha poi confermato il login
reale riuscito all'area personale da Chrome desktop Linux, seguendo la prova
con PIN completo. Pacchetto Chrome rilevato `156.0.8078.47-1`; sito, protocollo
TLS e sessione autenticata non sono stati osservati indipendentemente.
Chromium Snap/Flatpak e la compatibilità con altri siti restano da verificare.
Con il pacchetto `0.1.0~test20261023.7`, dopo il cambio del percorso in
`/opt/firma-con-cie`, è stato corretto il precedente riferimento NSS di Chrome
che causava `No_client_certificate`. La riparazione ha modificato soltanto
la riga della libreria CIE, a browser chiuso e senza caricare moduli. L'utente
ha confermato nuovamente l'accesso ai siti riuscito con il PIN completo.
Certificati/chiavi NSS, registrazioni estranee e Firefox sono stati conservati.
[Procedura e limiti](LINUX_CHROME.md).

## Configurazione guidata Firefox Linux (23 ottobre)

La Home e le Impostazioni generali includono un wizard per Firefox desktop
e Firefox Snap, utilizzabile senza lettore/carta. Il riquadro della Home è in
cima e compare soltanto se un profilo inizializzato richiede configurazione,
se c'è un problema da verificare o se manca la conferma del permesso Snap.
Le Impostazioni mantengono sempre l'accesso; i profili non inizializzati non
compaiono nella lista e non producono avvisi. Anche i profili già configurati
sono esclusi dal selettore; un permesso Snap mancante resta un’azione separata.
Il dialogo usa messaggi brevi e nasconde «Rileggi profili» dopo la scelta.
Lo stato viene riletto senza caricare NSS al ritorno nella Home/app e alla
chiusura del wizard. Scelta esplicita del profilo, piano legato alla
configurazione e conferma prima della scrittura; separata
autorizzazione amministrativa per il solo collegamento `firefox:pcscd`.
L'installer non esegue il wizard. Nessun PIN viene richiesto o acquisito.
Il backend genera il solo record CIE in un database NSS temporaneo e lo
inserisce atomicamente nel profilo, con PC/SC bloccato per il processo NSS.
La sentinella software verifica che altri moduli non vengano inizializzati.
Per Snap sono copiate solo tre librerie verificate in directory per versione;
le vecchie generazioni e gli archivi dell'utente sono conservati.
L'utente ha confermato il collaudo della Home condizionale e della lista dei
profili, e il successivo accesso ai siti con Firefox dopo l'installazione
della `.7`. La variante standard/Snap di quest'ultimo esito non è stata
distinta nella conferma; i precedenti login con configurazione manuale sono
riportati separatamente. L'icona nella barra del titolo richiede un collaudo
visivo distinto sui diversi desktop.
[Procedura e test isolati](LINUX_FIREFOX_SETUP.md).

## Installer Windows x64 (21 ottobre)

Il pacchetto locale di test include l'app completa, il componente Web e il
prerequisito Microsoft Visual C++ x64. Installazione e aggiornamento del
componente sono spostati nell'installer con UAC; l'app controlla la presenza
del componente senza elevazione durante l'abbinamento. Cache, impostazioni,
immagini e certificati utente vengono conservati anche dalla disinstallazione.
Anche la prima registrazione funziona senza lettore, CIE o PIN, usando i 12 ATR
e le maschere del middleware ufficiale verificati al commit `8dd385e`.
Il collaudo usa il
motore Inno reale con componente simulato in una destinazione isolata; UAC e
login dopo l'installazione del pacchetto completo restano da collaudare sul PC.
La distribuzione esclude 39 file di test/sviluppo e conserva integralmente
licenze e dipendenze operative: installer 142,5 MB invece di 175,5 MB,
cartella Release circa 381,7 MB invece di 496,9 MB. Superati 49 controlli dell'installer
isolato e le prove del bundle ridotto per PDF/P7M, LTA, revoca storica e rete.
Il catalogo/registro supera 410 controlli, incluse scritture reali in una chiave
HKCU isolata, migrazione, conflitti, maschere e ripristino; nessuna scrittura nel
database di sistema durante queste prove.
Corretta anche la distribuzione del ponte nativo: il vecchio binario non
riconosceva i nomi `CIE_n`, pur con installazione riuscita. Il ponte aggiornato
riconosce il componente installato; passano 13 gruppi CTest e 205 controlli sui
documenti con il backend originale. Il packager rifiuta runtime con regole del
catalogo obsolete. Il completamento pubblico dell'abbinamento già presente è
riuscito senza autenticazioni sulla carta.
[Preparazione, conservazione dei dati e limiti](WINDOWS_INSTALLER.md).

## Firefox Windows: login confermato (21 ottobre)

Firefox 158.0.1 ha aperto l'area personale del portale CIE dopo l'aggiornamento
del minidriver, con PIN completo inserito dall'utente. La correzione accetta il
DigestInfo SHA-2 canonico già codificato usato da osclientcerts: il test nuovo
fallisce con il provider precedente, mentre passano 115 controlli isolati con
la correzione. La traccia reale contiene soltanto metadati numerici e conferma
autenticazioni e firme riuscite. Si usa il provider smart card Windows senza
un modulo Firefox aggiuntivo o modifiche alle preferenze di sicurezza.
[Dettagli e limiti](WINDOWS_WEB_FIRST_USE.md#compatibilità-delle-richieste-rsa-di-firefox).

L'utente ha confermato anche il collaudo riuscito con Microsoft Edge su Windows
il 21 ottobre. La conferma è manuale; versione di Edge e protocollo TLS non sono
stati rilevati indipendentemente.

## Ridimensionamento Windows: collaudo riuscito (21 ottobre)

Le pagine e l'anteprima usano lo spazio disponibile anche quando la finestra
viene allargata. Il runner gestisce i messaggi di ridimensionamento rientranti
senza richiamare ricorsivamente il ridimensionamento della superficie Flutter.
Sul sistema provato il blocco dei fotogrammi con fascia nera persisteva con
Impeller; la selezione esplicita di Skia ha superato il confronto manuale con
trascinamenti ripetuti e navigazione a Verifica Firma. Passano 215 test Flutter
(tre facoltativi saltati), 926 controlli del ridimensionamento Win32, due gruppi
di geometria e 42 controlli dell'host. [Dettagli e limiti](DESKTOP_WINDOW_SIZING.md).

## Fattibilità RSA-PSS (21 ottobre)

La verifica di specifiche e sorgenti non ha individuato un percorso documentato
RSA-PSS o RSA senza padding per la chiave di autenticazione client del profilo
CIE attuale. PSS non viene dichiarato né attivato; il componente collaudato con
Chrome e Firefox resta invariato. Passano 124 controlli isolati del minidriver,
inclusa la firma PKCS#1 dopo una richiesta PSS rifiutata. Nessuna operazione
sulla CIE reale. [Riscontri, limiti e verifiche](RSA_PSS_FEASIBILITY.md).

## Nuova cache degli abbinamenti (20 ottobre)

L’archivio nativo è ora una cache cifrata per utente, indipendente da Portachiavi e Gestione credenziali. La gestione è condivisa con Linux; la copia pubblica del provider Windows usa lo stesso archivio su file. È richiesto un nuovo abbinamento con PIN completo, senza importazione automatica dei vecchi dati. Le precedenti prove hardware della tabella si riferiscono all’archivio precedente.

Le prove software coprono scrittura/lettura, persistenza fra processi rinominati, integrità, chiavi mancanti, permessi, rimozione e conservazione di un’altra carta. La compilazione incrociata Windows non equivale al collaudo del suo runtime o del nuovo payload del minidriver. Il nuovo archivio richiede ancora prove reali di abbinamento e firma con PIN parziale; Cambio PIN e Sblocco Carta restano esclusi dalle prove automatiche. [Dettagli e limiti della protezione](PAIRING.md).

Verifiche dell’integrazione della nuova cache:

- analisi Flutter senza problemi; 160 test superati e 3 saltati;
- 25 test CTest macOS e 13 test CTest nella VM Ubuntu ARM64 superati;
- 6 gruppi di prove della cache nel runtime macOS, incluso abbinamento e firme PDF/P7M con carta simulata, superati;
- backend Windows x64, provider smart card e relativo setup compilati in cross-compilazione; esecuzione sul PC Windows ancora da verificare;
- app macOS Universal, middleware ed estensione CryptoTokenKit firmati Apple Development; verifica approfondita delle firme e corrispondenza SHA-256 dei sorgenti e dei binari incluse nel controllo finale;
- Home della nuova app verificata senza importazione dei vecchi abbinamenti. Nessuna autenticazione sulla CIE reale eseguita durante queste prove.

## Controllo attivazione CryptoTokenKit (20 ottobre)

La Home mostra **Apri Impostazioni di Sistema** solo quando il componente
macOS incluso richiede attenzione. L’elezione dell’estensione viene letta senza
modificarla; la mancanza di una carta non equivale a disattivazione. Tornando
nell’app, lo stato viene aggiornato e la pubblicazione pendente può essere
completata una volta dai dati pubblici salvati, senza richiedere di nuovo il PIN.
Abbinamento e rimozioni pendenti vengono preservati.

Analisi Flutter senza problemi, 167 test Flutter superati (3 saltati) e 13
controlli Swift dell’attivazione superati. Build macOS Universal firmata Apple
Development, verificata con controllo approfondito della firma. Avvio e Home
verificati con un abbinamento già presente e componente abilitato, senza
pulsante di recupero superfluo. Lo stato disattivato, il ritorno dalle impostazioni
e il recupero senza PIN sono coperti da test simulati: non sono state modificate
le impostazioni del Mac né eseguite autenticazioni sulla carta reale.
[Flusso e limiti](WEB_AUTHENTICATION.md#controllo-dellattivazione-dalla-home).

Nel successivo collaudo reale sul Mac, la disattivazione temporanea della sola
estensione del prototipo ha fatto comparire il pulsante previsto e il pulsante
ha aperto Elementi login. La pagina però non elenca il token CryptoTokenKit,
né per app né per categoria: l’utente non può completare da lì l’abilitazione.
Il componente è stato ripristinato con un’elezione PlugInKit limitata al suo
identificativo. La Home è tornata allo stato configurato, il pulsante è scomparso
e i file degli abbinamenti sono rimasti identici. Nessun PIN richiesto o inviato
alla carta. Il recupero tramite sole Impostazioni di Sistema resta quindi
incompleto su questo Mac e richiede una soluzione dedicata.

## Riattivazione guidata e collaudo reale (20 ottobre)

Il limite delle Impostazioni di Sistema è stato superato con **Attiva accesso
ai siti** nella Home. Dopo la conferma **Attiva**, l’host riabilita la sola
estensione incorporata della propria applicazione e verifica lo stato finale.
Non chiede il PIN, non autentica la carta, non registra bundle e non cambia
altri middleware. Errori e annullamento conservano l’abbinamento, senza
ripetizioni automatiche.

Prova reale completata sul Mac: disattivazione temporanea, comparsa del pulsante,
conferma e riattivazione eseguita dall’app. Il pulsante è scomparso e lo stato è
tornato configurato. I file degli abbinamenti sono rimasti identici e le elezioni
degli altri componenti non sono cambiate. Abbinamento e componente attivo sono
stati verificati anche dopo il riavvio dell’app, senza richiesta del PIN. Nessuna
nuova prova di login nel browser è stata eseguita.

Build macOS Universal firmata Apple Development; firma approfondita e manifest
sorgenti/binari verificati. Analisi Flutter senza problemi, 171 test Flutter
superati (3 saltati), 13 controlli Swift dello stato e prove del comando fisso,
della mancata disponibilità del bundle e dell’errore del comando superati.

## Notifiche operative in finestre di dialogo (20 ottobre)

Le notifiche di abbinamento, rimozione e attivazione Web della Home sono ora
dialoghi con pulsante **OK**. Lo stesso componente Flutter condiviso presenta
avvisi ed esiti di impostazioni, preferenze, operazioni PIN/PUK, anteprima
grafica, estrazione e apertura dei collegamenti. I dettagli dell’analisi delle
firme e gli stati persistenti della carta restano nelle pagine dedicate.

I dialoghi mandano il testo a capo e consentono lo scorrimento dei contenuti
lunghi. Una coda per finestra evita notifiche sovrapposte; ricostruzioni della
GUI e cambi di tema non ripresentano eventi già chiusi. L’apertura sospende
l’osservazione automatica della carta fino alla chiusura. Le notifiche non
eseguono autenticazioni, rimozioni o nuovi tentativi sulle operazioni precedenti.

Analisi Flutter senza problemi, 174 test superati e 3 saltati. Sono inclusi
controlli di testi lunghi, ordine delle notifiche e operazioni ripetute con lo
stesso testo. Build macOS Universal firmata Apple Development, verificata anche
visivamente salvando gli stessi valori della scheda Log: comparsa del dialogo,
chiusura con OK e nessun riquadro residuo. Diagnostica rimasta disattivata;
nessuna operazione reale di abbinamento, rimozione, firma o PIN/PUK eseguita.
Questa revisione non include una nuova esecuzione nativa della GUI Windows/Linux.

## Guida e aspetto dell’interfaccia (20 ottobre)

La Guida inclusa è stata riscritta in italiano e inglese come manuale per
l’utente finale, con istruzioni per macOS, Windows e Linux e collegamenti al
progetto CIE ID Desktop. I dettagli sullo stato di sviluppo restano in questa
documentazione tecnica.

Le didascalie dei pulsanti usano tonalità azzurre adatte al tema chiaro e scuro;
le voci del menu laterale passano da 12 a 13 punti. La modifica è nel tema
Flutter condiviso. Analisi Flutter senza problemi, 174 test superati e 3
saltati; nuova build macOS Universal firmata Apple Development e controllata
visivamente. Non è stato ripetuto il collaudo della GUI su Windows o Linux.

## Precedente integrazione macOS/Windows

I sorgenti delle modifiche Windows sono stati riportati sul Mac e confrontati con manifest SHA-256. Sono inclusi primo utilizzo Web Windows, feedback dell’abbinamento, notifiche Chiudi/OK, barra fissa dei pulsanti nell’anteprima e triangoli direzionali.

Nella compilazione macOS aggiornata:

- analisi Flutter senza problemi;
- 156 test Flutter superati;
- 3 test di integrazione con il backend reale, usando soltanto documenti sintetici;
- 22 gruppi CTest nativi superati;
- runner, codice Dart compilato, middleware, adattatori ed estensione CryptoTokenKit verificati ARM64/x86_64;
- firma Apple Development e verifica approfondita delle firme del bundle riuscite.

La build di sviluppo non è notarizzata. Le prove automatiche citate non inviano PIN o PUK e non cambiano lo stato della carta. I report locali e i documenti di collaudo non sono inclusi nel repository.

L’utente ha confermato il collaudo delle modifiche Windows. L’ultima ricompilazione macOS non equivale a una nuova prova completa con CIE reale di ciascun flusso.

## Pubblicazione

Il repository è predisposto per i sorgenti e resta privato. Non sono pubblicate release binarie di CIE ID Desktop. Prima di distribuire un’app occorre completare il pacchetto corrispondente descritto in [LICENSING.md](LICENSING.md), il collaudo finale e la firma/distribuzione della piattaforma.

## Integrazione Linux / Firefox

Il provider Linux PKCS#11 usa il motore Web comune e il PIN completo richiesto
al browser. I test software esercitano il provider con PC/SC e carta simulati,
NSS senza database e la cache del solo certificato pubblico in un namespace
temporaneo. La disponibilità del modulo non viene presentata come prova di
configurazione Firefox. Nessun profilo browser viene letto o modificato; nessuna
prova CIE reale è inclusa. [Dettagli](LINUX_FIREFOX.md).

## Abbinamento reale Linux

Collaudo locale su Ubuntu 26.10 x86_64: abbinamento della CIE riuscito con PIN
completo inserito dall’utente nell’applicazione. Dopo il riavvio la Home mostra
la carta già abbinata senza chiedere un altro PIN, confermato dall’utente.
La lettura indipendente dell’archivio conferma il record pronto per la firma,
i dati pubblici verificati e la persistenza dei file cifrati, con permessi
0700/0600 e proprietario corretto. Le letture di verifica sono state protette
con un blocco PC/SC, senza ulteriori autenticazioni.

Il collaudo riguarda abbinamento e persistenza. Firma con PIN parziale,
rimozione dell’abbinamento e accesso ai siti non sono stati provati con la CIE
reale in questa sessione; nessuna configurazione browser è stata modificata.

## Firma PDF reale Linux con PIN parziale

Prova su Ubuntu 26.10 x86_64 con la CIE già abbinata: l’utente ha seguito il
flusso nell’applicazione con le ultime quattro cifre del PIN e ha confermato
il salvataggio riuscito di un PDF sintetico. Il file contiene una firma integra
che copre tutto il PDF; la verifica CMS indipendente con OpenSSL è riuscita.
Pagina e testo sono conservati e il documento di partenza è invariato.

I controlli correnti riportano certificato entro validità, catena ministeriale
CIE attendibile e stato di revoca OCSP positivo per la catena. La firma non
contiene una marca temporale e questa prova non stabilisce validità storica.
Il verificatore ha usato un blocco PC/SC, senza ulteriori autenticazioni.
L’abbinamento e i record cifrati sono rimasti invariati dopo la firma.

Il risultato riguarda questa prova PDF e la configurazione locale utilizzata.
CAdES/P7M, rimozione dell’abbinamento e accesso ai siti non sono stati collaudati
con la CIE reale in questa sessione. Nessuna configurazione browser modificata.

## Firma CAdES/P7M reale Linux con PIN parziale

Prova successiva sullo stesso PDF sintetico, su Ubuntu 26.10 x86_64 con la CIE
già abbinata. L’utente ha seguito il flusso CAdES con le ultime quattro cifre
del PIN nell’applicazione e ha confermato il salvataggio riuscito. Il P7M
contiene una firma integra, verificata dal backend e indipendentemente con
OpenSSL; il contenuto estratto è identico byte per byte al PDF originale.

Certificato entro validità, catena ministeriale CIE attendibile e stato di
revoca OCSP della catena hanno esito positivo. Nessuna marca temporale: la
prova non stabilisce validità storica. Le verifiche sono state eseguite con
blocco PC/SC e zero chiamate alla carta. L’abbinamento e i record cifrati sono
rimasti invariati dopo la firma.

Sono quindi collaudati localmente abbinamento, persistenza e firma PDF/P7M con
PIN parziale per questa configurazione. Rimozione dell’abbinamento e accesso
ai siti restano fuori da queste prove reali; nessuna configurazione browser
è stata modificata e nessuna operazione PIN/PUK di modifica è stata eseguita.

## Scaling dei caratteri Linux

Il runner integra il DPI logico dei caratteri GTK quando Flutter riceve una
scala del testo del 100%. Sul desktop KDE locale la lettura effettiva è
120 DPI, quindi 125%. Le modifiche al DPI vengono propagate durante
l’esecuzione. Una scala già fornita da Flutter ha la precedenza: nessuna
moltiplicazione fra scale del testo o con la scala dello schermo.

Sono coperti da test software il fallback GTK, le scale Flutter preesistenti,
lo scaling dello schermo indipendente, gli aggiornamenti e il ripristino al
100%, gli errori del canale, la chiusura e i layout Home/dialoghi al 125% e
150%. I test nativi usano uno schermo GObject sintetico senza display; una
lettura separata del desktop verifica il canale reale senza creare finestre.
Nessuna prova CIE o di accesso ai siti fa parte di questo collaudo.

## Accesso reale ai siti con Firefox su Linux (20 ottobre)

Dopo le istruzioni per registrare `libcie_linux_pkcs11.so` e provare l’accesso
con CIE e PIN completo, l’utente ha comunicato: «Test accesso ai siti con
Mozilla FireFox eseguito con successo».

Il login reale Linux/Firefox è quindi registrato come riuscito sulla base
della conferma dell’utente. Non sono stati acquisiti PIN, dati personali,
certificati o schermate. Non sono state eseguite ulteriori autenticazioni
dall’agente. Il sito effettivamente usato, la versione e il confezionamento
di Firefox e il protocollo TLS non sono stati comunicati né verificati
indipendentemente; non si deducono dal successo della prova.

Restano distinti i test software già eseguiti e i limiti del provider,
compresa l’assenza di RSA-PSS. La prova non attesta compatibilità generale
con TLS 1.3, Snap/Flatpak, altri browser, siti o lettori, né tutti i casi di
errore, rimozione e scadenza della sessione. [Dettagli](LINUX_FIREFOX.md).

## Integrazione Firefox Snap con PIN completo

Il runtime Linux ha un controllo ABI per la base Snap core24 e usa il fallback
sicuro di curl `explicit_bzero`, evitando il requisito glibc 2.43. Il bridge
pubblica solo il certificato DER in una cartella privata dedicata sotto
`snap/firefox/common`; il provider nel contesto Snap legge questa copia
senza aprire l’archivio Web/PIN dell’host o la sua chiave. Pubblicazione,
ripristino e rimozione rispettano la separazione fra carte. Per le CIE già
abbinate il completamento usa i dati pubblici verificati senza autenticare.

Test software su Firefox Snap 158.0-2, revisione 9057, NSS 3.130: provider
reale caricato in memoria con PC/SC bloccato; con carta simulata sono riusciti
selezione del certificato, rifiuto del PIN parziale senza VERIFY e firma con
una sola richiesta di PIN completo sintetico. I dati Web/PIN dell’host
simulato sono inutilizzabili e rimangono invariati. I test di pubblicazione
coprono formato, permessi, link e rimozione selettiva.

Durante queste verifiche software non sono stati modificati profili browser,
permessi Snap o impostazioni di sicurezza; nessuna CIE reale o credenziale
personale è stata usata.

## Accesso reale ai siti con Firefox Snap (20 ottobre)

Su richiesta dell’utente è stato preparato il solo certificato pubblico DER
dai dati già verificati dell’abbinamento ed è stato abilitato il collegamento
`firefox:pcscd` a `:pcscd`, con autenticazione locale. Verificati lettura del
DER dal confinamento Snap, directory 0700 e file 0600, record di abbinamento
e chiave della cache invariati. La preparazione non ha richiesto PIN né
eseguito operazioni sulla carta o modificato profili browser. L’installazione
locale verificata è Firefox Snap 158.0-2, revisione 9057, su Ubuntu 26.10 x86_64.

L’utente ha poi confermato: «Test di accesso ai siti con Firefox Snap eseguito
con successo usando il PIN completo». Il collaudo reale Snap è quindi
registrato come riuscito con PIN completo di otto cifre. L’agente non ha
acquisito il PIN né osservato indipendentemente il login; sito e protocollo
TLS non sono stati comunicati. Non sono state avviate ulteriori autenticazioni.
Restano i limiti del provider e il collaudo separato per altri siti, browser,
lettori e casi di errore. [Dettagli](LINUX_FIREFOX.md).

## Launcher, icone e pacchetto Linux locale di test (20 ottobre)

Il runner imposta il nome dell'app e il nome dell'icona predefinita GTK,
conservando la risorsa incorporata per il bundle portabile. Il launcher
include `TryExec` e parole chiave localizzate. Lo script di packaging crea
`cie-id-desktop` per test locali, con bundle in `/opt/firma-con-cie`, comando
in `/usr/bin`, `.desktop` e nove icone hicolor nelle directory standard.
Le dipendenze sono ricavate da tutti gli ELF con `dpkg-shlibdeps`; programmi
di test e dati utente non fanno parte del payload. Non ci sono script che
avviano l'app, modificano Firefox, collegano Snap o cancellano abbinamenti.

Build del runner con 2 job e pacchetto Ubuntu 26.10 amd64 verificati:
311 file del payload con hash e proprietario root, launcher valido, icona
incorporata e risoluzione dell'icona dal tema GTK, 13 ELF con dipendenze
risolte, manifest nativo e ABI Snap. Installazione, aggiornamento e rimozione
sono riusciti in un root/database dpkg separato, preservando dati utente
sintetici; la simulazione APT sull'host risolve le dipendenze del pacchetto.
Nessuna installazione sull'host, finestra dell'app, prova CIE o modifica del
browser/permessi Snap è stata eseguita. Verifica visiva del menu/icone su
KDE/GNOME e installazione su sistemi puliti restano da completare. DSS/LTA
Linux è escluso; non è una release binaria pronta per redistribuzione.
[Procedura e percorsi, incluso Firefox Snap](LINUX_PACKAGE.md).

Successivamente, su autorizzazione dell'utente, il pacchetto
`0.1.0~test20261020.1` è stato installato su Ubuntu 26.10 amd64 con KDE/Wayland.
APT ha aggiunto il solo `cie-id-desktop`, senza installare altre dipendenze o
rimuovere pacchetti. Verificati i 311 hash del payload, proprietà root,
`dpkg --verify`, launcher eseguibile, registrazione GIO e corrispondenza
dell'application ID. La cache KDE è stata aggiornata: il test del menu colloca
la voce in **Accessori**, e `kiconfinder6` risolve il PNG hicolor installato,
identico alla risorsa del repository. L'utente ha confermato visivamente nel
menu KDE: «Sì, voce e icona corrette». L'agente non ha avviato l'applicazione
né eseguito nuove prove CIE o modifiche al browser. Durante le verifiche è
stato rilevato un processo dell'app dal percorso installato, senza interazione
dell'agente con la finestra o la carta. I collegamenti Snap sono rimasti
invariati. GNOME e l'icona della finestra/taskbar a programma aperto restano
da verificare separatamente.

## Adattamento automatico della finestra Linux (20 ottobre)

Il runner GTK usa ora 1280×720 come dimensione preferita, con finestra
ridimensionabile. L'area utile del monitor e l'altezza della barra del titolo
limitano la dimensione iniziale; quando lo spazio è insufficiente viene
richiesta la massimizzazione al gestore finestre, senza fullscreen. GNOME e
KDE riservano così i pannelli anche sui backend Wayland che non espongono
l'area utile completa. Monitor, area utile e risoluzione sono osservati durante
l'esecuzione; una finestra più piccola viene conservata se entra nella nuova
area. Le coordinate GTK sono già logiche: non si applicano nuovamente fattore
display o scala dei caratteri. Windows e macOS mantengono i rispettivi runner.

Build release con 2 job, due gruppi CTest del runner (sette casi nativi),
200 test Flutter superati e tre test di runtime facoltativi saltati; analisi
senza problemi. I sei nuovi scenari UI attraversano tutte le pagine su
dimensioni fino a 640×400, caratteri fino al 200% e display al 200%, mantenendo
scala, scorrimento e pulsante del dialogo di prova. Una lettura senza finestre
del monitor GNOME/Wayland attivo rileva 1280×800 logici, area utile 1213×771 e
fattore display 2, spiegando perché la precedente larghezza fissa non entrava.

Nuovo pacchetto `0.1.0~test20261020.2` amd64 assemblato e verificato: 311 file
con hash, icone, launcher, 13 ELF risolti, manifest nativo e ABI Firefox Snap.
Installazione, aggiornamento e rimozione sono riusciti nel root dpkg isolato,
preservando dati sintetici; simulazione APT sull'host superata. Nessuna nuova
installazione sull'host, avvio dell'app, prova CIE o modifica browser/Snap è
stata eseguita. La verifica visiva GNOME/KDE della finestra aggiornata resta
manuale. [Pacchetto e procedura](LINUX_PACKAGE.md).

Successivamente l'utente ha installato il pacchetto aggiornato e confermato:
«Ok, pacchetto installato e test adattamento automatico eseguito con successo».
La prova si colloca nella sessione GNOME descritta sopra; l'esito visivo è una
conferma diretta dell'utente, non osservata indipendentemente dall'agente.
La versione installata `0.1.0~test20261020.2` e l'integrità dei file sono state
verificate con `dpkg-query` e `dpkg --verify`, senza avviare l'app o nuove prove
CIE. Il collaudo visivo della nuova gestione della finestra su KDE e i cambi
di monitor durante l'esecuzione restano separati.

## Adattamento finestra macOS/Windows (20 ottobre)

I runner sostituiscono i vincoli fissi con adattamento all'area utile del monitor.
macOS conserva 1080×760 punti come contenuto preferito, usa `visibleFrame` con
cornice e margine, abilita ridimensionamento/zoom senza fullscreen e osserva
i cambi di schermo/backing. Windows converte la preferenza iniziale 1280×720
una volta ai DPI del monitor, limita il rettangolo a `rcWork`, abilita
ridimensionamento/massimizzazione e conserva senza riscalare il rettangolo
`WM_DPICHANGED`. Sono gestite variazioni di area utile e monitor, con minimi
limitati allo spazio disponibile e guardie contro il rientro.

Il calcolo dei rettangoli è un header C comune importato in Swift come modulo
Clang e incluso dal runner Win32. Tre gruppi CTest su Linux verificano il
codice in C, C++ e il modulo Clang. Analisi pulita; 212 test Flutter superati
e tre facoltativi saltati, inclusi 18 scenari di layout su tutte le piattaforme.
`win32_window.cpp` è compilato da Linux come oggetto Windows x64 usando Clang,
header MinGW/header C Flutter upstream estratti solo nel workspace. Questo
non è una build completa della GUI Windows. Swift/AppKit non sono compilati:
su questo host mancano il compilatore Swift e AppKit.

Build complete e collaudo visivo macOS/Windows restano da eseguire sulle
piattaforme corrispondenti. Il `.deb` Linux già installato non viene sostituito.
Nessuna app o prova CIE avviata e nessuna configurazione browser/permessi
modificata. [Comportamento, test e limiti](DESKTOP_WINDOW_SIZING.md).
