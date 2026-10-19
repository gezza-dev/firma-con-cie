# Confronto con CIE ID Universal

Riferimento: release pubblicata [v1.5.2](https://github.com/gezza-dev/cie-id-macos-universal/releases/tag/v1.5.2),
tag annotato `7e4834abf28a0a2f549b65136b35d3403b820e1f`, commit sorgente
`355c9b742268af80466404d80287ad9ce3f8c9b4`.
Questa tabella descrive le funzioni, non una copia della grafica AppKit.
Il prototipo rimane separato dall'app pubblicata e non è una release distribuibile.

## Obiettivo dell’esperienza d’uso — 18 ottobre 2026

La grafica Flutter attuale va mantenuta. Il riferimento per navigazione, nomi,
sequenza delle azioni e comportamento dei flussi è CIE ID Universal: chi usa
già quell’app deve poter ritrovare le operazioni senza imparare una procedura
diversa. La parità funzionale della tabella seguente non basta a soddisfare
questo requisito. UX1 e il codice di UX2/UX3/UX4 sono implementati come descritto nei riepiloghi seguenti; i collaudi con carta dei nuovi flussi restano rinviati e UX5 è il prossimo blocco.

- Home e abbinamento: riconoscimento automatico di lettore/carta, stati di attesa
  chiari e un’unica procedura iniziale con PIN completo. Integrare la preparazione
  dell’accesso Web nello stesso flusso, riusando la lettura autenticata quando
  possibile, senza salvare il PIN o ripetere VERIFY. Un problema del componente
  Web deve avere un recupero comprensibile e non risultare un abbinamento
  completamente riuscito se una parte della configurazione resta incompleta.
- Eliminare dal percorso ordinario «Rileva carta» e le configurazioni tecniche
  separate. Il monitoraggio automatico non deve interrompere firma, abbinamento
  o autenticazione del browser, né aprire transazioni concorrenti sulla carta.
- Firma: riprodurre l’ordine dei passaggi di CIE ID Universal, dalla selezione
  o trascinamento del documento alla scelta della firma, eventuale anteprima,
  richiesta del PIN, salvataggio e conferma. Mostrare solo le scelte pertinenti
  al passaggio corrente; le opzioni di prova non appartengono al flusso ordinario.
- Verifica: selezione/trascinamento, avvio e risultato leggibile; dettagli tecnici
  consultabili su richiesta. Conservare la distinzione fra firma non valida,
  esito indeterminato e servizio non raggiungibile, senza appiattire gli esiti.
- Usare termini e azioni familiari dell’app di riferimento; conservare Guida e
  Assistenza già richieste. Spostare prove del componente, percorsi del backend
  e diagnostica nelle impostazioni avanzate.
- Applicare i flussi condivisi a macOS e Windows, rispettando dialoghi e permessi
  di sistema. Le prove reali di Cambio PIN e Sblocco Carta rimangono rinviate.

Il confronto iniziale e il piano di attuazione sono riportati sotto; le colonne
del confronto descrivono la situazione prima di UX1. Restano da implementare
e collaudare i blocchi successivi. L’accesso Web con app completamente chiusa è una prova distinta dal
login Safari già riuscito durante il collaudo.

## UX1 completato — 18 ottobre 2026

- Mantenuti tema Material 3 e grafica Flutter. Menu condiviso: Home, Firma
  Elettronica, Verifica Firma, Cambia PIN, Sblocca Carta, Guida, Assistenza,
  Informazioni, Impostazioni. Nuova pagina Informazioni con versione, licenze
  e dettagli tecnici consultabili su richiesta.
- Controller di navigazione e stati dei documenti condivisi. Indietro conserva
  il documento ma azzera i campi PIN; navigazione bloccata durante un’operazione.
  Concludi chiude firma/verifica riuscite. Cambio documento o carta invalida i
  risultati e l’anteprima dipendenti dai dati precedenti.
- Requisito aggiunto dall’utente: l’etichetta PAdES contiene Nome e Cognome del
  certificato letto dalla CIE durante la singola autenticazione di firma.
  Nessun nome libero, sostituto dal commonName o riuso da un’altra carta.
  Anche l’immagine personalizzata riceve il nome come didascalia. Il nome
  nell’anteprima è ancora un segnaposto; i metadati pubblici per carta di UX2
  consentiranno di mostrarlo prima dell’inserimento del PIN.
- 61 test Flutter, varianti di navigazione macOS/Windows, analisi senza problemi;
  18 gruppi CTest macOS, inclusi 108 controlli documentali con nomi sintetici,
  accenti/apostrofi e quattro rotazioni. Backend Windows x64 compilato dalle
  stesse sorgenti; esecuzione della nuova build sul PC ancora da ripetere.
- Bundle macOS Universal firmato Apple Development; controllo visivo di menu,
  Informazioni e pagine documentali. Nuovo segno con CIE reale da collaudare.

UX1 prepara la gestione dei passaggi. La Home automatica e l’abbinamento unico
sono sviluppati in UX2; la firma a tappe è ora sviluppata in UX3, e la verifica all’apertura del documento è sviluppata in UX4. Nessuna prova reale di Cambio PIN o Sblocco Carta.

## UX2 implementato, collaudo reale rinviato — 18 ottobre 2026

Home automatica condivisa, nessun «Rileva carta» o «Configura accesso ai siti»
nel percorso ordinario con runtime v2. Riconoscimento pubblico solo a carta
libera, senza reset, con cache per epoca di presenza e sospensione durante
operazioni/dialoghi/inattività. Nessuna navigazione automatica o scelta ambigua.
Il vecchio percorso manuale resta solo per compatibilità con runtime precedenti.

Nuovo ingresso nativo con un VERIFY e lo stesso certificato verificato nel SOD;
Nome/Cognome e DER in archivio pubblico protetto separato dal prefisso. La Home
mostra le CIE anche senza lettore; l’anteprima PAdES può usare il nome verificato
salvato, mentre la firma rilegge sempre quello della CIE effettiva. Abbinamenti
precedenti preservati; aggiornamento esplicito con PIN completo, recupero Web
senza PIN quando i dati v2 sono disponibili e rimozione coordinata delle sole
registrazioni del prototipo. Stati di firma, pubblicazione, componente e identità
osservata distinti: nessuna dichiarazione implicita di login riuscito.

73 test Flutter e 20 gruppi CTest macOS superati; backend Windows x64 compilato
dalle stesse sorgenti. Test software e build separati dal collaudo con carta: [PAIRING.md](PAIRING.md)
e [VALIDATION.md](VALIDATION.md). Registrazione KSP Windows, prima configurazione
unica, convivenza Safari e nuova firma grafica restano da provare sui sistemi.
Non sono stati eseguiti Cambio PIN o Sblocco Carta. Il successivo blocco UX3 è descritto qui sotto; la verifica immediata di UX4 è descritta più avanti.

## UX3 implementato, collaudo reale rinviato — 18 ottobre 2026

Firma a tappe S01–S10, scelta CIE/senza abbinamento e preparazione documento
senza lettore. Preflight PDF/CMS sul contenuto reale; PIN automatico 4/8 e
fallback esplicito, salvataggio dopo il PIN con annullamento senza autenticazione,
stati dedicati di firma/esito, cofirma contestuale e immagini per CIE con
migrazione facoltativa della precedente immagine globale. Nome e Cognome finali
continuano a provenire direttamente dalla CIE. Copie private e parametri fissati
impediscono che documento/carta/formato cambino durante il salvataggio.

86 test Flutter e 20 gruppi CTest macOS superati; analisi senza problemi,
app macOS Apple Development compilata e backend Windows x64 compilato dalle
stesse sorgenti. Controllo visivo macOS senza PIN; esecuzione Windows e nuove
prove reali di firma ancora rinviate. [Flusso, artefatti e limiti UX3](SIGNING_UX3.md).
Nessuna modifica all’app di riferimento pubblicata, a PIN/PUK o alle attivazioni Web.

## UX4 implementato — 18 ottobre 2026

Verifica avviata alla scelta/drop, risultati per firmatario con esiti distinti,
dettagli tecnici e DSS espandibili, annullamento/scarto dei risultati superati,
ripetizione e nuova selezione. L’estrazione appare soltanto per P7M analizzati
e strutturalmente leggibili, anche con firma non valida, e usa gli stessi byte
verificati con salvataggio senza sovrascrittura. Nessuna dipendenza dalla
presenza della carta né tentativi di autenticazione.

100 test Flutter, 3 integrazioni sul runtime reale macOS e 135 controlli del
generatore nativo di documenti sintetici superati. Analisi senza problemi;
app macOS Universal Apple Development. Il backend C/C++ rimane quello di UX3.
Il nuovo percorso sul PC Windows resta da collaudare; nessuna prova reale
PIN/PUK o firma sulla carta. [Flusso, architettura e limiti UX4](VERIFICATION_UX4.md).

## Metodo e perimetro del confronto

Analisi statica di storyboard, controller e widget il 18 ottobre 2026, integrata
con gli screenshot forniti dall’utente e con il collaudo Web del 17 ottobre.
Non è un collaudo visivo/manuale completo delle due applicazioni. Otto file
rilevanti sono stati recuperati dal tag pubblicato v1.5.2 via API GitHub e
confrontati byte per byte con la copia locale: tutti coincidono. Il solo HEAD
della copia locale punta ancora all’upstream e non identifica il fork pubblicato;
per questo il riferimento è stato verificato sul tag, senza modificare quel repository.
Inventario locale: `reports/ux-reference-comparison-20261018.json`.

Fonti principali:

- Riferimento: [storyboard v1.5.2](https://github.com/gezza-dev/cie-id-macos-universal/blob/v1.5.2/CIE%20ID/Base.lproj/Main.storyboard),
  [MainViewController](https://github.com/gezza-dev/cie-id-macos-universal/blob/v1.5.2/CIE%20ID/MainViewController.mm),
  [CarouselView](https://github.com/gezza-dev/cie-id-macos-universal/blob/v1.5.2/CIE%20ID/Carousel/CarouselView.m),
  `IntroViewController`, `AppDelegate` e `VerifyCell` dello stesso tag.
- Flutter: [main.dart](../lib/main.dart), [abbinamento](../lib/pairing_view.dart),
  [accesso Web](../lib/web_access.dart), [anteprima](../lib/signature_appearance.dart),
  [verifica](../lib/verification_view.dart), [PIN/PUK](../lib/pin_management.dart),
  [preferenze](../lib/preferences_view.dart) e [impostazioni](../lib/settings_view.dart).
- Backend: [adapter carta](../native/src/cie_card_adapter.cpp),
  [ponte condiviso](../native/src/cie_bridge.cpp), [motore Web](../native/src/cie_web.cpp),
  [adapter CryptoTokenKit](../native/platform/macos/web/CIEPrototypeToken.mm).

La navigazione effettiva prevale sul nome delle view: `SELECT_OP_PAGE` contiene
«Firma / Verifica», ma `chooseSignOrVerifyFileOperation` passa direttamente
alla firma o alla verifica secondo l’ingresso scelto. Non aggiungere una nuova
scelta intermedia solo perché esiste nello storyboard. Il riferimento non ha
un pulsante manuale «Rileva carta» nel percorso ordinario; ciò non dimostra che
usi già un monitor continuo degli eventi PC/SC. Il monitor automatico qui è
un miglioramento richiesto dall’utente, da implementare e misurare.

## Confronto schermata per schermata

Tutte le destinazioni sotto conservano tema Material 3, colori, tipografia,
card, icone e comportamento adattivo della grafica Flutter attuale. «Replicare»
indica sequenza e significato delle azioni, non copiare coordinate AppKit.
Gli ID servono a collegare confronto, implementazione e collaudo.

| ID / schermata o stato | CIE ID Universal v1.5.2 | Flutter attuale | Intervento pianificato |
| --- | --- | --- | --- |
| N01 — struttura e menu | Home, Firma Elettronica, Verifica Firma, Cambia PIN, Sblocca Carta, Tutorial, Aiuto, Informazioni, Impostazioni. | Carta, Firma e Verifica hanno nomi abbreviati; Guida e Assistenza presenti; informazioni/licenze meno riconoscibili. | Home, Firma Elettronica, Verifica Firma, Cambia PIN, Sblocca Carta, Guida, Assistenza, Informazioni, Impostazioni. Guida/Assistenza restano come richiesto. Stessa barra Flutter, senza aggiungere una seconda navigazione. |
| N02 — avvio e introduzione | Breve introduzione con preferenza per non mostrarla più; accesso alla Home. | Intestazione tecnica, stato «Middleware caricato» e avvertenze del prototipo persistenti. | Home subito utilizzabile; eventuale breve introduzione ignorabile, consultabile dalla Guida. Conservare l’identificazione come prototipo sperimentale, spostando spiegazioni estese e stato del backend in Informazioni/Avanzate. |
| H01 — primo abbinamento | «Abbina la tua CIE», istruzioni e otto cifre del PIN, «Abbina» / «Annulla». | Prima Rileva carta, poi card tecnica del lettore e dialogo Abbina. | Stessa intenzione della Home originale: carta rilevata automaticamente, un solo ingresso Abbina e PIN completo. Nessuna scelta di certificato/driver nel percorso normale. Un solo invio esplicito: niente autenticazione automatica alla digitazione dell’ottava cifra. |
| H02 — nessun lettore/carta, carta diversa o occupata | Le istruzioni precedono l’azione; gli errori emergono quando si opera. | Elenco dei lettori, identificativo tecnico e rilevamento manuale. | Stati automatici «Collega il lettore», «Appoggia la CIE», «La carta non è una CIE», «Carta in uso: attendi». Non cambiare schermata all’inserimento, non azzerare documenti/preferenze e non interrogare continuamente i dati protetti. Scelta del lettore solo se ci sono più CIE utilizzabili. |
| H03 — abbinamento in corso | Schermata dedicata con avanzamento. | Indicatore globale e messaggio; preparazione Web separata con un secondo PIN. | Un unico progresso «Abbinamento in corso», includendo archivio protetto e predisposizione Web. I dettagli tecnici sono espandibili; un solo VERIFY e nessun reinvio del PIN. |
| H04 — fine abbinamento | «Abbinamento terminato con successo» e «Concludi», poi elenco delle CIE. | Aggiornamento della lista, senza schermata equivalente; stato Web distinto. | Esito dedicato con Concludi. Successo completo solo quando le parti richieste sono pronte. Esito parziale esplicito se la firma è disponibile ma l’accesso Web richiede un passaggio di sistema; recupero senza nuovo PIN quando resta solo da pubblicare il certificato già verificato. |
| H05 — Home con carte abbinate | Carte riconoscibili con intestatario/numero; aggiunta, selezione e rimozione. | Lista di identificativi, aggiornamento manuale, pulsante Ripeti abbinamento. | Card Flutter con metadati verificati, carta selezionata, presenza e stato di configurazione. Aggiornamento automatico, «Aggiungi CIE», «Rimuovi» e scelta tra più carte. Non inventare nomi dai soli identificativi; per vecchi record offrire aggiornamento esplicito. |
| H06 — rimozione carta/tutte | Conferma di rimozione della CIE o di tutte le CIE. | Disabbinamento documenti e rimozione Web sono due operazioni indipendenti. | Una conferma comprensibile «Rimuovi CIE da questo computer», con rimozione coordinata dei soli record del prototipo: prefisso, metadati, immagine per carta e configurazione pubblica Web. Preservare altri componenti. In caso di rimozione incompleta, mostrarla e consentire di completarla senza PIN. |
| S01 — ingresso alla firma / scelta CIE | Con carte abbinate mostra prima la selezione; disponibile firma senza abbinamento con PIN completo. Senza abbinamenti si può scegliere il documento. | UX3: scelta logica della CIE abbinata o firma senza abbinamento; il documento è preparabile senza lettore. | Conservare i rami del riferimento. Ricordare la carta abbinata scelta, selezione rapida per più carte e «Firma senza abbinamento». Il documento può essere preparato prima di appoggiare la carta; la presenza diventa necessaria al momento di firmare. |
| S02 — scelta documento | Ampia area di trascinamento e «Seleziona un documento». | UX3: area drop ampia, selettore nativo e passaggio al formato. Documento di prova spostato negli strumenti di collaudo. | Area drop evidente nello stile Flutter, un solo documento, dialogo nativo. Passaggio automatico alla scelta del tipo dopo selezione. Rimuovere il documento di prova dal percorso normale e mantenerlo solo negli strumenti di collaudo. |
| S03 — scelta Firma / Verifica | View esistente, ma il controller attuale instrada direttamente secondo il menu scelto. | Firma e Verifica restano ingressi distinti nel menu. | Mantenere ingressi distinti e componente selezione comune; nessuna scelta duplicata dopo il documento. |
| S04 — tipo di firma | «Firma CADES» / «Firma PADES», descrizioni, «Aggiungi firma grafica», Prosegui e Annulla. | UX3: PAdES/CAdES dopo il documento; parser PDF/CMS nativo indipendente dall’estensione e grafica facoltativa. | Dopo il documento mostrare scelte spiegate «Firma PAdES · PDF» e «Firma CAdES · P7M» con le azioni Prosegui/Annulla. PAdES solo per PDF effettivamente supportati. L’estensione del file da sola non basta alla validazione. |
| S05 — personalizzazione immagine | Personalizza/Aggiorna e Crea firma; immagine predefinita collegata alla CIE con nome dell’intestatario. | UX3: immagine per CIE, creazione/ripristino Nome e Cognome, migrazione globale esplicita; nome finale letto dalla CIE. | Personalizza raggiungibile dal flusso firma, con anteprima, scelta immagine e ripristino. Per fedeltà introdurre immagine/metadati per CIE e creazione del segno dal nome verificato, usando risorse con licenza già compatibile. Conservare l’immagine globale esistente come opzione di migrazione, senza cancellarla. |
| S06 — anteprima PAdES grafica | Pagina documento, posizione trascinabile, cambio pagina e Prosegui. Saltata per firma invisibile/CAdES. | UX3: tappa grafica con editor esistente e ripristino di pagina/posizione; invalidazione cambiando documento. | Riutilizzare renderer/editor e coordinate condivise dentro una tappa del flusso; niente riscrittura del motore PDF. Conservare posizione tornando indietro; invalidarla se cambia il documento. Per carte non abbinate, la grafica disponibile è una scelta esplicitamente diversa dal riferimento, che la nasconde in quel ramo. |
| S07 — PIN di firma | «Inserisci le ultime 4 cifre del PIN» per carta abbinata, otto per firma senza abbinamento; Firma/Annulla. | UX3: PIN dopo le scelte, quattro cifre automatiche per abbinamento disponibile, otto senza abbinamento, fallback esplicito. | Schermata PIN dopo le scelte. Quattro cifre automaticamente se l’archivio protetto e la CIE selezionata lo consentono; otto per firma senza abbinamento. Nessun interruttore ordinario; fallback esplicito al PIN completo se archivio non leggibile, mai reinvio automatico con altra modalità. |
| S08 — salvataggio | Premendo Firma dopo il PIN si apre Salva file firmato; annullamento non avvia la firma. | UX3: Firma apre Salva; annullamento cancella il PIN senza operazioni private. Una sola firma dopo conferma di nuova destinazione. | Stesso ordine del riferimento: Firma apre il dialogo nativo con nome proposto ed estensione corretta; conferma avvia l’operazione. Annulla azzera il PIN senza VERIFY e permette di continuare il flusso. Il PIN resta solo nell’operazione corrente, senza archiviazione o ripristino da un passaggio precedente. |
| S09 — firma in corso e risultato | Progresso, «File firmato con successo», Concludi che riporta alla selezione del documento. | UX3: progresso ed esito dedicati, verifica espandibile e Concludi verso la scelta documento. | Stato dedicato con comandi disabilitati durante la firma; conferma principale e Concludi. Mostrare a richiesta il risultato della verifica successiva; se il file è scritto ma la revoca non è determinabile, distinguere chiaramente file salvato e verifica incompleta. |
| S10 — firma aggiuntiva P7M | Non espone il nuovo flusso di cofirma condiviso del prototipo come scelta dedicata. | UX3: Aggiungi una firma solo per CMS attached idonei; nessuna busta annidata; controlli prima e dopo la firma. | Conservare la funzionalità come «Aggiungi una firma» solo dopo aver scelto un P7M idoneo. Spiegazione breve e stesso percorso PIN/salvataggio. Non confondere cofirma e nuova busta annidata né perdere le firme esistenti. |
| V01 — selezione per verifica | Verifica Firma porta alla selezione; scelta/drop avvia la verifica senza PIN/carta e senza un’ulteriore scelta Firma/Verifica. | UX4: scelta/drop avvia la verifica, con progresso, annullamento, cambio documento e Ripeti verifica. Nessuna carta o PIN. | Avviare la verifica dopo la scelta/drop, con progresso e possibilità di ripeterla dall’esito se serve aggiornare i controlli online. Nessuna dipendenza dal monitor carta e nessuna richiesta di PIN. |
| V02 — risultato per firmatario | Numero di sottoscrittori, nome/data, firma, certificato e revoca, Estrai e Concludi. | UX4: schede per firmatario con firma, certificato, revoca e data distinta dalla marca; dettagli nativi e DSS separati ed espandibili. | Schede Flutter per firmatario con riepilogo di firma, certificato/revoca e data qualificata correttamente. Dettagli espandibili per catena, marca e prove storiche. Non presentare firma integra come automaticamente attendibile o qualificata; mantenere esito indeterminato quando mancano prove. |
| V03 — documento senza firme / errori | Esiti e messaggi dedicati. | UX4: nessuna firma, documento non leggibile e verifica non completata distinti; dati mancanti indeterminati; codici nei dettagli. | «Nessuna firma trovata», «Documento non leggibile», «Verifica non completata» con azione pertinente. Errori di rete non diventano «firma non valida». Codici solo nei dettagli; messaggi integralmente visibili e focus sull’azione utile. |
| V04 — estrazione P7M | Estrai disponibile nel risultato, dialogo Salva e conferma. | UX4: estrazione solo dopo analisi strutturale P7M, anche con firme non valide; stessa copia verificata, salvataggio atomico senza sovrascrittura. | Rendere Estrai riconoscibile nel risultato del P7M analizzato, senza PIN. Nuovo file, nessuna apertura automatica e nessuna deduzione di validità dall’estrazione. Conservare la possibilità di estrazione anche se la firma non è valida, quando la struttura è leggibile. |
| P01 — Cambia PIN | PIN Corrente, Nuovo PIN, Conferma Nuovo PIN, azione e pagina di successo/Concludi. | Campi simili, selezione carta esterna, conferma esplicita e risultato inline. | Carta riconosciuta nella pagina; stessi nomi e ordine, pulsante Cambia PIN, progresso/esito dedicati. Conservare la conferma esplicita e i controlli già implementati. Prove con backend simulato, nessuna modifica reale alla CIE. |
| P02 — Sblocca Carta | PUK, Nuovo PIN e conferma, Sblocca, successo/Concludi e avviso sul riabbinamento. | Modulo simile con «Sblocca e imposta il PIN» e risultato inline. | Lessico e percorso familiari, mantenendo avviso sull’effetto e conferma. Dopo esito certo, abbinamento da aggiornare senza usare il vecchio prefisso; esiti incerti restano distinti e non si ritentano. Anche queste prove reali restano rinviate. |
| G01 — Guida | Tutorial incluso e collegamenti esterni nel browser. | Guida offline già presente, descrive i passaggi tecnici attuali. | Mantenere Guida e aggiornarla ai flussi effettivamente consegnati. Nessuna documentazione di un’automazione prima che funzioni su quella piattaforma. |
| A01 — Assistenza | Aiuto remoto e riferimenti ufficiali. | Pagina Assistenza richiesta dall’utente con FAQ/contatti e distinzione del fork. | Mantenerla sotto Guida; risposte per attività comuni e collegamenti esterni nel browser predefinito. Riferimenti al fork distinti dall’assistenza ufficiale. |
| I01 — Informazioni/licenze | Voce Informazioni dedicata. | Licenze registrate in Flutter ma percorso poco evidente dal menu principale. | Voce Informazioni con versione, progetto indipendente, piattaforma e licenze; dettagli del runtime in Avanzate. Non eliminare attribuzioni o l’indicazione sperimentale. |
| T01 — Impostazioni e firma grafica | Preferenze di avvio/background, proxy, log e personalizzazione nel flusso firma. | Preferenze firma e rete/diagnostica una sotto l’altra. | Sezioni chiare Preferenze / Connessione / Avanzate. Personalizzazione raggiungibile anche dalla firma; niente reset generale che cancelli abbinamenti. Introduzione e background hanno contratti diversi su macOS/Windows: implementarli solo con comportamento definito, senza dichiararli già presenti. |
| T02 — diagnostica e recupero | Raccolta/eliminazione log, livelli distinti app/libreria e modifica proxy. | Rapporto filtrato, credenziali di rete di sessione, prova connessione e componenti Web nella Home. | Avanzate raccoglie prova componente, stato Web e rapporto filtrato. Preservare la diagnostica senza segreti, i limiti delle credenziali e la configurazione proxy del prototipo; non copiare i log raw o la persistenza credenziali del riferimento. |
| B01 — accesso ai siti | Dopo configurazione l’utente opera dal browser, senza conoscere il middleware. | Configura/Rimuovi/Prova componente esposti come azioni quotidiane; Safari provato con app aperta. | Preparazione Web nell’abbinamento; in Home solo stato semplice e recupero quando necessario. Browser e finestra PIN di sistema restano esterni. Verificare login con app chiusa, nuova connessione dopo inattività e cambio carta; il limite di 30 secondi del prototipo è un tema da risolvere/collaudare, non un conto alla rovescia da insegnare all’utente. |

### Navigazione e flussi proposti

**Menu:** Home → Firma Elettronica → Verifica Firma → Cambia PIN → Sblocca Carta
→ Guida → Assistenza → Informazioni → Impostazioni. Le due voci Guida/Assistenza
mantengono la decisione già presa per il fork. Nessuna nuova pagina tecnica principale.

**Home:** attesa lettore/carta → Abbina (PIN completo) → configurazione unica →
esito → Concludi → CIE abbinate. Se sono già presenti abbinamenti, aprire
l’elenco anche quando la carta non è appoggiata. Il monitor non deve spostare
l’utente da Firma/Verifica alla Home quando arriva un evento del lettore.

**Firma:** scelta CIE abbinata quando applicabile, oppure firma senza abbinamento
→ documento → tipo di firma → anteprima solo se grafica → PIN corretto per la
modalità → Firma → dialogo Salva → firma singola → esito → Concludi.
Tornare indietro conserva documento/scelte compatibili ma cancella sempre il PIN.
Una sostituzione di documento/carta invalida esito e preparazione non più validi.

**Verifica:** documento → verifica automatica con avanzamento → risultato per
firmatario → dettagli facoltativi / Estrai se P7M → Concludi. Un annullamento o
una nuova selezione rende irrilevanti le risposte della richiesta precedente.

**Web:** abbinamento unico già completato → lettore/CIE → browser → Entra con CIE
→ finestra PIN del sistema → consenso del sito → area riservata. Il programma
non conferma il consenso sul sito al posto dell’utente. Il PIN Web macOS resta
completo finché l’adapter non supporta e collauda esplicitamente altro comportamento;
non promettere le ultime quattro cifre per analogia con la firma documenti.

## Interventi sul codice condiviso

Separare il coordinamento dei flussi oggi concentrato in `main.dart` dai widget,
con controller Dart condivisi e stati espliciti per Home, abbinamento, firma e
verifica. Si possono usare `ChangeNotifier`/classi già compatibili con il progetto;
non è necessario introdurre un nuovo framework di stato per questo lavoro.

| Area | Intervento / contratto | Punti esistenti da riusare |
| --- | --- | --- |
| Navigazione | Destinazioni e ritorni espliciti, una cronologia del flusso, stato invalidato per documento/carta cambiati. | `main.dart`, `document_model.dart`, `document_drop_zone.dart`. |
| Presenza carta | Watcher di stato PC/SC, una scansione iniziale limitata, identificazione pubblica solo quando necessaria, selezione automatica solo se non ambigua. Nessun loop di lettura certificato o VERIFY. | `native_bridge.dart`, `cie_bridge.cpp`, `card_identification.h`; `SCardGetStatusChange` e cancellazione nel solo contesto posseduto dal watcher. |
| Concorrenza | Il watcher è leggero; sospendere accessi APDU mentre operano firma/abbinamento/PIN. Per browser/CTK e KSP in processi separati rispettare l’occupazione del lettore e differire le letture: un mutex Dart da solo non coordina quei processi. Mai forzare reset per aggiornare la Home. | Timeout e isolamento già introdotti, trasporto di `cie_web.cpp`, gestione sensibile CTK 0.1.9. |
| Abbinamento unico | Nuovo ingresso nativo versionato/capability che esegue un VERIFY, verifica SOD e legge certificato/metadati nella stessa sessione, conserva il solo prefisso nell’archivio protetto e restituisce dati pubblici verificati. Non concatenare gli attuali `pair()` e `enrollWeb()`: sono due autenticazioni. | `cie_card_pair_authenticate`, `cie_card_web_enroll` e `PairMaterial`; `cie_bridge_pair` / `cie_bridge_web_enroll` sono oggi separati. |
| Pubblicazione nel sistema | Dart coordina il risultato pubblico con adapter macOS/Windows senza condividere PIN con i widget. Pubblicazione idempotente e recuperabile dal certificato già verificato dopo riavvio; stato per carta distinto per firma e Web. | `MainFlutterWindow.swift`, `web_cert_store.cpp`, `web_access.dart`; CSP/KSP/minidriver Windows e App Group CTK macOS. |
| Carte già abbinate | Rilevare stato vecchio (solo prefisso) e stato completo, senza invalidare gli abbinamenti funzionanti. Una nuova lettura protetta richiede una sola azione esplicita con PIN completo; non usare di nascosto il PIN parziale per completare il Web. | `paired_store.*`, elenco abbinamenti, nuove informazioni pubbliche versionate. Nessuna importazione automatica dall’app originale. |
| Firma e anteprima | Controller a tappe con gli stessi metodi FFI di firma. Parametri immutabili per l’operazione, un invio del PIN, validazione di file/destinazione prima delle operazioni private. Eliminare copia temporanea quando non più necessaria; nessuna scrittura sull’originale. | `signature_appearance.dart`, `signature_image.dart`, `document_operations.cpp`, `service.sign` e cofirma condivisa. |
| Risultati | Modello di presentazione condiviso, separato dai dati crittografici. Sintesi per firmatario; controlli attuali, tempo dichiarato, marca attendibile, storia e DSS/LTA restano distinguibili. | `verification_view.dart`, `long_term_view.dart`, backend già collaudato. |
| Errori | Catalogo italiano per messaggio, azione e dettaglio tecnico. Un errore non cambia significato quando viene presentato in una schermata più breve. | `ErrorNotice`, mapping dei codici bridge, limiti e timeout già presenti. |
| GUI e sistema | Widget e regole del flusso sono gli stessi; dialoghi file restano nativi. Solo accesso al portachiavi/credenziali, pubblicazione Web, permessi, menu/tray e apertura esterna restano adapter di piattaforma. | Canali macOS e FFI Windows esistenti. Non sdoppiare Home/Firma/Verifica per sistema operativo. |

### Abbinamento unico: esiti e recupero

1. Prima del PIN controllare disponibilità runtime, archivio protetto e componente
   di sistema quanto possibile. Driver/permessi mancanti richiedono un’istruzione
   concreta; niente PIN chiesto inutilmente o installazioni privilegiate silenziose.
2. L’azione Abbina autorizza in modo comprensibile firma e predisposizione Web.
   Il prefisso è custodito dal componente nativo; PIN completo e ultime quattro
   cifre non vengono memorizzati, esportati o scritti nei log.
3. Dopo VERIFY e SOD riusciti, conservare i dati pubblici necessari al recupero.
   Gli store nativi e la pubblicazione OS non formano una singola transazione
   atomica: registrare le fasi e gestire gli errori parziali, senza fingere rollback
   completo o perdere un abbinamento precedente durante un aggiornamento.
4. Distinguere `readyForSigning`, `webProvisioned`, `systemComponentAvailable` e
   `webIdentityObserved`. Nessuno di questi da solo significa che un sito accetterà
   il login. «Carta pronta» completo solo quando i prerequisiti locali sono accertati.
5. Se la pubblicazione OS fallisce dopo l’abbinamento: «CIE abbinata per firmare.
   Completa la configurazione per accedere ai siti» e azione Completa. Se bastano
   il DER verificato e un permesso/registrazione di sistema, non richiedere un nuovo
   PIN. Se la prova pubblica non è disponibile, spiegare la rilettura esplicita.
6. Windows: preservare il controllo di conflitto del certificato associato a un
   altro componente in `CurrentUser\MY`; non sostituirlo per rendere verde lo stato.
   Registrazione/attivazione KSP e requisiti di firma Windows restano dipendenze
   reali. Non dichiarare la preparazione completamente automatica finché mancano.
7. macOS: ripubblicare il token fisico senza riaprire autenticazioni né usare token
   software sintetici. Verificare cosa si può aggiornare automaticamente e cosa
   richiede una sola rimozione/riappoggio; se serve, guidare l’utente. Non proporre
   riavvii di servizi o manipolazioni PlugInKit come operazioni ordinarie.

## Piano di attuazione

Ogni blocco resta nel prototipo separato. Le dipendenze seguenti sono tecniche,
non richieste di eseguire ora test con PIN o modifiche alla carta.

| Blocco / priorità | Schermate | Lavoro e dipendenze | Criterio di completamento |
| --- | --- | --- | --- |
| UX0 — riferimento e contratti, P0 | Tutte | Questo confronto, glossario, stati/ritorni e separazione dei collaudi. | Piano documentato; distinguere comportamento osservato, proposta e limiti. **Completato con questa analisi**, senza interventi runtime. |
| UX1 — struttura condivisa, P0 **completato** | N01–N02, struttura di tutte le altre | Estrarre controller/stati, mantenere tema e widget Flutter, allineare menu e messaggi di base. Preparare test di navigazione senza hardware. | Stessa grafica e stessi flussi su macOS/Windows; menu familiari, nessuna regressione su servizi di firma/verifica. |
| UX2 — Home e abbinamento unico, P0 **codice implementato; collaudo reale rinviato** | H01–H06, B01 | Watcher e coordinamento carta; nuovo ingresso nativo con dati pubblici; pubblicazione OS e recupero; metadati/versionamento. Richiede UX1 e contratto del backend. | Prima configurazione con una sola autenticazione; nessun Rileva carta/Configura Web ordinario; rimozione coerente; recupero senza nuovo PIN dove possibile. Su Windows lo stato completo resta bloccato dall’attivazione KSP finché non collaudata. |
| UX3 — firma guidata, P1 **codice implementato; collaudo reale rinviato** | S01–S10 | Tappe, carta abbinata/senza abbinamento, PIN automatico 4/8, salvataggio nel punto atteso, anteprima e immagine per carta; cofirma contestuale. UX1 permette parte del lavoro; il collaudo end-to-end usa UX2. | PDF invisibile/grafico e P7M seguono il percorso del riferimento; annullamento non firma; file originale preservato; risultati chiari. Test reali di grafica e cofirma separati da quelli già riusciti per PDF/P7M semplici. |
| UX4 — verifica immediata, P1 **codice implementato; collaudo PC Windows da eseguire** | V01–V04 | Avvio alla selezione, risultati sintetici, dettagli e Estrai; cancellazione/scarto dei risultati superati. Può avanzare da UX1 senza attendere il lettore. | Verifica completa senza carta/PIN e senza blocchi del watcher; errori di revoca non mascherati; più firmatari gestiti; dettagli integri. |
| UX5 — schermate di supporto, P2 | P01–P02, G01, A01, I01, T01–T02 | Nomi, esiti e ritorni familiari; Informazioni/licenze; impostazioni ordinate, strumenti tecnici in Avanzate; aggiornare Guida ai nuovi flussi. | Navigazione coerente, errori lunghi leggibili, licenze accessibili. PIN/PUK provati solo con simulatori. Intro/background/tray da completare come voci esplicite di parità, con semantica OS definita. |
| UX6 — collaudo della nuova esperienza, P0 per il rilascio | Tutte | Regressione condivisa e scenari reali sui due sistemi. Login senza app aperta, lease CTK inattivo, conflitti e recupero. Installer/aggiornamento restano un progetto di distribuzione distinto. | Superare la matrice sotto; non dichiarare parità completa o rilascio finché rimangono percorsi quotidiani non verificati. Linux e prove reali PIN/PUK non inclusi. |

Ordine consigliato: UX1 → UX2 → UX3; UX4 può essere sviluppato dopo UX1 in modo
indipendente; UX5 allinea i flussi consegnati; UX6 convalida ogni blocco e poi
l’insieme. Prima modifica di prodotto suggerita: Home/abbinamento unico, perché
rimuove la duplicazione più onerosa, dopo aver predisposto gli stati condivisi.

### Criteri comuni di accettazione

- Un utente di CIE ID Universal ritrova nomi e ordine delle azioni principali;
  nessuna richiesta di conoscere CryptoTokenKit, KSP, DER, SOD o ABI per firmare,
  verificare o completare un normale abbinamento.
- Colori, Material 3, tipografia, card e impaginazione adattiva Flutter conservati;
  verifica visiva durante l’implementazione a finestra ampia e stretta, con testo
  ingrandito. Tastiera, focus iniziale, ritorno focus e lettori di schermo collaudati.
- Ogni operazione privata parte da un’azione esplicita; nessun doppio invio per
  doppio clic, evento carta, riapertura finestra o cambio schermata. Nessun retry
  automatico di PIN/PUK, nessuna persistenza del PIN completo.
- Attese, errori e avvisi sono visibili per intero, con azioni di recupero coerenti.
  La navigazione indietro/Annulla non fa perdere inutilmente il documento, ma
  cancella sempre i campi segreti; una firma già avviata non è dichiarata annullata
  se non è stata realmente interrotta.
- Il watchdog della carta non resetta una sessione del browser e non rallenta la
  verifica documentale; rilevamento sospeso/differito durante operazioni protette.
- Il successo di salvataggio, firma integra, fiducia/revoca, validità storica e
  login al sito restano concetti distinti nei risultati, anche nella sintesi.
- Le funzioni già disponibili (cofirma, DSS/LTA, proxy, rapporto filtrato, licenze)
  restano raggiungibili senza dominare il percorso principale.

### Matrice di collaudo da eseguire durante l’implementazione

M = macOS, W = Windows. «Reale» implica intervento personale per il PIN;
il piano non avvia oggi alcuna prova hardware. I casi PIN/PUK qui sono simulati.

| Caso | Software condiviso | Verifica reale M / W | Esito atteso |
| --- | --- | --- | --- |
| Q01 — avvio senza lettore e senza abbinamenti | Stati Home e navigazione | M + W | Istruzioni semplici; Verifica/Guida/Assistenza disponibili. |
| Q02 — inserimento/rimozione, due carte e lettore occupato | Eventi sintetici, stato/generazione, concorrenza | M + W | Aggiornamento senza pulsante, selezione non ambigua, nessun reset di sessioni altrui. |
| Q03 — primo abbinamento completo e riavvio | Conteggio VERIFY = 1, DER/SOD e store simulati, test namespace isolato | M + W, Web W subordinato a KSP | Una sola autenticazione, prefisso protetto e dati pubblici persistenti, stato locale corretto. |
| Q04 — PIN errato, carta cambiata, SOD fallito, store non disponibile | Iniezione degli errori, nessuna ripetizione | Errori PIN solo simulati | Nessun retry; nessun falso successo o prefisso associato a carta diversa. |
| Q05 — Web non pubblicato, permesso negato o conflitto certificato | Fasi persistite e recupero idempotente | M + W senza alterare componenti estranei | Configurazione parziale riconoscibile; Completa non reinvia PIN; conflitto non sovrascritto. |
| Q06 — vecchio abbinamento / rimozione singola e totale | Versioni store e rollback/recupero, solo dati sintetici | M + W su record del prototipo autorizzati | Nessuna migrazione nascosta; rimozione completa dei soli dati propri o esito parziale esplicito. |
| Q07 — firma abbinata e senza abbinamento | PIN richiesto 4/8, scelta carta e snapshot input | PDF e P7M su M + W | Stesso ordine del riferimento, una firma per azione, risultato verificato. |
| Q08 — anteprima e immagine | Pagine/rotazioni, indietro e cambio file/carta | PDF grafico su M + W | Immagine/posizione attese, originali preservati; nessuna firma dalla sola anteprima. |
| Q09 — cofirma P7M | CMS pre/post e preservazione prove | M + W | Scelta contestuale, firme precedenti conservate, nuovo output. |
| Q10 — annullamento e destinazione non valida | File dialog annullato, conflitto output, doppio clic, permessi | M + W | Nessun VERIFY se annullato prima dell’invio; sostituzione confermata soltanto dopo firma e verifica riuscite, conservando il file precedente in caso di errore; nessuna firma duplicata. |
| Q11 — verifica immediata senza carta | PDF/P7M, firme multiple, selezioni ravvicinate | Dialoghi e drop M + W | Avvio automatico, nessun PIN, esito relativo solo al documento corrente. |
| Q12 — rete/revoca/storia/DSS | Fixtures valide, invalide, insufficienti; timeout/proxy | Connettività M + W | Indeterminato distinto da invalido, timestamp distinto da data dichiarata; dettagli consultabili. |
| Q13 — estrazione e documenti non firmati/malformati | P7M annidato, contenuto malformato, nessuna firma | Dialoghi M + W | Nessuna esecuzione automatica del contenuto; Estrai non certifica la firma; errori comprensibili. |
| Q14 — Cambio PIN e Sblocco Carta | Moduli, conferma, codici e risultati con fake backend | **Rinviato su entrambi** | Nessun comando reale sulla CIE; esito incerto non ritentato; prefisso vecchio invalidato solo secondo esito reale. |
| Q15 — browser con app aperta/chiusa | Policy di sessione, assenza cache PIN e stato OS | Safari M; browser/KSP W da convalidare | Login dal browser senza finestra app; nessuna necessità di aprire test componente o reinserire configurazioni. Nessun cambiamento alle impostazioni TLS/fiducia. |
| Q16 — browser dopo pausa/cambio carta e app che rileva in parallelo | Timeout, rilascio risorse e concorrenza | M + W | Nessun obbligo di premere un consenso entro 20 secondi; se serve nuova autenticazione, richiesta di sistema comprensibile, nessun retry di un PIN fallito. Il recupero dopo lease CTK scaduta è ancora da progettare/collaudare. |
| Q17 — supporto, impostazioni e accessibilità | Widget, testi lunghi, licenze, stato preferenze | Tastiera, finestra ridotta, ingrandimento M + W | Nessun testo tagliato; azioni tecniche in Avanzate; esportazione diagnostica senza dati personali/segreti. |

### Differenze intenzionali e limiti da non nascondere

- Guida e Assistenza conservano i nomi richiesti dall’utente, pur sostituendo
  Tutorial/Aiuto del riferimento. Il codice della verifica mantiene controlli
  ed esiti più ricchi: cambierà la presentazione, non la policy crittografica.
- L’eventuale grafica PDF per firma senza abbinamento e la cofirma sono estensioni
  già presenti nel prototipo. Vanno collocate senza introdurre decisioni extra
  nei percorsi corrispondenti all’originale.
- Identità visive/cards sono ricostruite con dati verificati e risorse Flutter;
  nome dell’intestatario e immagine per carta richiedono metadati nuovi. Nessun
  riuso silenzioso dell’archivio dell’app originale.
- Windows ha firme documentali e abbinamento reali riusciti, ma registrazione e
  autenticazione Web KSP non sono ancora convalidate su carta reale. Una nuova
  interfaccia comune non rimuove questa dipendenza.
- Il login Safari riuscito su un portale non convalida altri siti/browser né
  la ripresa dopo una pausa lunga. Il limite di inattività della build di prova
  deve essere gestito nel prodotto; non si promette che sia già risolto.
- Distribuzione/installer, scelta del nome definitivo del prodotto e Linux
  restano separati dal riallineamento dell’esperienza d’uso. Per le opzioni
  background/tray non presenti va dichiarato il divario, senza simularne gli effetti.

## Parità funzionale

| Funzione | Prototipo Flutter macOS / Windows | Passo necessario |
| --- | --- | --- |
| Rilevamento lettore e CIE | Condiviso, provato su hardware reale; percorso rapido IAS | Mantenere le misure di regressione |
| Firma PAdES senza grafica e CAdES | Riuscita con CIE reale su entrambi | Ampliare i documenti di prova |
| Segno grafico PAdES, immagine personalizzata, pagina/posizione | Implementato con anteprima locale e test sintetici | Collaudo di firma grafica con CIE sui due sistemi |
| Apertura/salvataggio e trascinamento | Dialoghi nativi e drop singolo condivisi | Collaudo manuale del drop, ergonomia e accessibilità |
| Estrazione documento P7M | Implementata nel backend condiviso e UI | Collaudo di file diversi e percorsi utente |
| Verifica integrità, certificati e revoca | Implementata; esiti separati e indeterminati conservati | Ampliare regressioni documentali |
| Marche temporali, prove storiche e DSS/LTA | Implementate, con limiti documentati | Ulteriori campioni con prove archivistiche complete |
| Cambio PIN e sblocco PUK | UI e backend condivisi, test software | Prove reali rinviate dall'utente |
| Firma aggiuntiva di un P7M già firmato | Cofirma condivisa, preflight e preservazione CMS; prove sintetiche | Collaudo con CIE reale |
| Abbinamento/disabbinamento e PIN parziale | Implementati con archivio nativo separato, elenco/rimozione e firma con ultime quattro cifre | Abbinamento, riavvio e firme con ultime quattro cifre riusciti su macOS e Windows; rimozione verificata via software/archivio protetto; nessuna migrazione automatica |
| Immagine di firma persistente e preferenze | Formato predefinito, immagine copiata, rimozione e ripristino | Collaudo ergonomico; eventuali altre preferenze |
| Impostazioni, proxy e diagnostica | Configurazione condivisa HTTP/HTTPS, credenziali di sessione, prova connessione e rapporto diagnostico filtrato | Ampliare il collaudo su proxy aziendali; opzioni di avvio/background e PAC/NTLM non implementati |
| Tutorial offline, Aiuto e Informazioni/licenze | Guida inclusa, Assistenza con FAQ/contatti ufficiali, link esterni e Informazioni/licenze | Mantenere guida e avvisi coerenti con i nuovi flussi |
| Accesso a siti con CIE | Motore IAS comune, certificato pubblico, CryptoTokenKit macOS e minidriver Windows CSP/KSP; firma locale e accesso al portale ufficiale CIE con Safari riusciti su Mac Apple Silicon | Altri siti/browser; attivazione e prova KSP reale su Windows; distribuzione/firma Windows ancora aperte |
| Distribuzione/aggiornamenti | Bundle di test separati | Firma, notarizzazione/Authenticode, installer e collaudo upgrade/disinstallazione |
| Linux | Backend già compilato senza hardware; nuovi flussi da collaudare | Ambiente Linux, build Flutter e lettore reali |

## Sequenza successiva

La sequenza operativa aggiornata è UX1 → UX2 → UX3/UX4 → UX5 → UX6, descritta
nel piano sopra. Le attività della matrice funzionale non completate restano
valide e vengono collaudate nel flusso corrispondente: firma grafica, cofirma,
proxy aziendali, accesso Web Windows, distribuzione e Linux. La semplificazione
non autorizza a dichiararle già convalidate.

Le prove reali PIN/PUK restano sospese fino a una richiesta dell'utente.
Nessuna voce “implementata” equivale automaticamente a un collaudo hardware o
all'idoneità alla distribuzione. Esiti effettivi in `VALIDATION.md` e nei report.

Dettagli del nuovo blocco: [cofirma, guida e preferenze](COSIGN_GUIDE_PREFERENCES.md).

Dettagli di rete, diagnostica e assistenza: [impostazioni condivise](SETTINGS_DIAGNOSTICS_PROXY.md).
