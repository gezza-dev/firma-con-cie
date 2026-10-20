# Interfaccia CIE ID: Home, intestazioni, firma e impostazioni

## Comportamento

- Nella Home, **Abbina un’altra CIE** rimane disponibile quando esistono carte memorizzate. Se è già presente una sola carta nuova viene aperto esplicitamente il dialogo di abbinamento; altrimenti una scheda spiega di sostituire la carta sul lettore. Il monitor continua senza autenticazioni e non apre automaticamente dialoghi PIN. La carta già abbinata non viene riautenticata o sovrascritta. Le altre schede rimangono disponibili e l’azione è annullabile.
- **Ripristina firma testuale predefinita** sostituisce la vecchia etichetta ed è disabilitato quando il segno testuale è già attivo. Dopo un’immagine personalizzata ripristina il segno a quattro righe e le sue dimensioni iniziali.
- Il PNG testuale è ritagliato alla misura del testo con margini ridotti; la larghezza iniziale del riquadro si adegua mantenendo la scala del testo. Il PDF nativo limita il bordo alla larghezza effettivamente occupata dal testo entro i limiti scelti, lasciando inalterata la posizione e adattando il carattere per evitare tagli. Le firme con immagine mantengono il riquadro scelto.
- Le frecce di spostamento usano lo stesso stile nelle quattro direzioni.
- Un’intestazione comune è centrata sull’area della pagina, esclusa la barra laterale. Nella Home mostra **CIE ID** e **La tua Carta di Identità Elettronica**; nelle altre pagine mostra soltanto la voce di menu corrispondente. Il ritorno della procedura di firma rimane a sinistra e non influenza la centratura. Le intestazioni duplicate e il piè di pagina di sviluppo sono rimossi.
- Impostazioni contiene tre schede: **Generali**, **Proxy**, **Log**, con Generali aperta per prima. Le bozze restano disponibili cambiando scheda. Salvare i log non applica un proxy modificato ma non salvato. Le credenziali proxy restano solo nella sessione. Il rapporto diagnostico e gli strumenti avanzati sono nella scheda Log; i controlli sono bloccati durante un’operazione in corso.
- I nomi di sviluppo sono rimossi dai testi della GUI, dalla guida, dai messaggi e dai titoli di finestra/menu. L’app macOS viene assemblata come **CIE-ID.app** (nelle build precedenti **CIE ID.app**), nella cartella dedicata alle build sperimentali. Gli identificativi tecnici di bundle, componenti Web e archivi restano invariati per conservare le configurazioni precedenti.
- Licenze e attribuzioni restano integre. La GUI presenta un accesso alle copie leggibili dei testi originali, compresi gli avvisi distribuiti con l’interfaccia e quelli nativi, da consultare nel visualizzatore del sistema.

## Verifiche

- 111 test Flutter superati, incluse varianti macOS/Windows per abbinamento di una seconda carta simulata, centratura delle intestazioni e pulizia dei testi. Controllati anche conservazione della bozza proxy tra schede, salvataggio indipendente dei log e assenza di spazio trasparente eccessivo nel PNG.
- Analisi statica senza problemi; 20 gruppi CTest macOS superati; 178 controlli documentali sintetici, comprese integrità delle firme, testo, data, rotazioni e salvataggio visibile senza sovrascrittura.
- Backend Windows x64 ricompilato dalle stesse sorgenti. La compilazione incrociata e le varianti grafiche nei test non equivalgono a esecuzione sul PC Windows.
- Nessun nuovo PIN reale inviato, nessun Cambio PIN o Sblocco Carta. Nessuna pubblicazione GitHub o sostituzione della versione CIE ID Universal.

## Artefatti

- App Apple Development Universal: `/percorso/Builds/CIE-ID/macos-ux5/CIE ID.app`.
- Runtime: `native/runtime/macos-ux5` e `native/runtime/windows-ux5`, con DSS/JVM privati e manifest delle sorgenti native.
- Report: `reports/ux5-validation.json`.

## Finestre Apri/Salva e dettagli di firma — 18 ottobre 2026

- Una riga di spazio (24 punti) separa **Firma senza abbinamento** dalla spiegazione.
- **Seleziona un documento** parte dal Desktop sia in Firma Elettronica sia in Verifica Firma, anche dopo aver usato un’altra cartella. macOS usa la cartella di sistema; Windows usa `FOLDERID_Desktop`, incluso il Desktop reindirizzato a OneDrive.
- **Indietro** rimane visibile e disabilitato nel primo passaggio della procedura di firma. Continua a operare solo sulla procedura.
- Il titolo nativo macOS **CIE ID** è centrato sulla finestra con vincoli di layout, come nell’app di riferimento.
- L’icona di firma riuscita è verde; l’icona dell’operazione fallita è rossa. Dopo un errore il PIN rimane vuoto e non partono nuovi tentativi.
- **Salva** accetta la sostituzione confermata dal dialogo di sistema, compreso il documento scelto inizialmente: si firma sempre la copia privata immutabile. Il backend conserva il file precedente fino al completamento della firma e della verifica, controlla che la destinazione non sia stata modificata durante l’operazione e pubblica il risultato con una sostituzione atomica. Errori PIN e controlli crittografici falliti non modificano il file precedente. Cartelle e collegamenti non sono accettati come destinazione. I file pubblicati restano visibili. Le vecchie API native e l’estrazione P7M mantengono il comportamento senza sovrascrittura.
- Collaudo: 116 test Flutter, 3 integrazioni documentali, analisi statica senza problemi, 20 gruppi CTest macOS e 187 controlli documentali. Prove sintetiche di sostituzione PDF/P7M con PIN completo/parziale, conservazione dopo errore e visibilità sul Desktop. Titolo, spaziatura, primo Indietro e i due dialoghi Apri controllati nell’app macOS. Backend Windows ricompilato con manifest delle stesse 551 sorgenti; esecuzione sul PC Windows e nuove firme con CIE reale da collaudare separatamente.
- App aggiornata Apple Development Universal: `/percorso/Builds/CIE-ID/macos-ux5-dialogs/CIE ID.app`.
- Runtime: `native/runtime/macos-ux5-dialogs` e `native/runtime/windows-ux5-dialogs`; report `reports/ux5-dialogs-validation.json`.

## Nome del firmatario sopra agli identificativi — 18 ottobre 2026

Nei risultati della verifica il Nome e Cognome provenienti dal certificato del singolo firmatario precedono, su una riga separata, il Common Name originale (per le CIE: codice fiscale/numero della carta). Lo stesso componente è usato nei dettagli successivi alla firma PDF/P7M e nella pagina Verifica Firma su macOS e Windows. Non viene usato il nome della carta collegata o abbinata, che potrebbe appartenere a una persona diversa dal firmatario. Un Common Name già uguale al nome non viene duplicato; certificati privi di Nome e Cognome conservano l’identificazione disponibile. L’esito dei controlli crittografici, della fiducia e della revoca resta distinto dall’identità dichiarata nel certificato.

App Apple Development Universal: `/percorso/Builds/CIE-ID/macos-ux5-identities/CIE ID.app`. Backend nativo e componente CryptoTokenKit invariati rispetto a `macos-ux5-dialogs`; modifica nel solo codice Dart condiviso.

## Schede CIE della Home e miniatura nella barra laterale — 18 ottobre 2026

Le carte abbinate mostrano l’illustrazione originale CIE a sinistra (144 punti di larghezza), Nome e Cognome in alto a destra e il numero stampato sulla carta sulla riga successiva. La barra laterale usa la stessa illustrazione a 64 punti in sostituzione dell’icona generica. Le varianti originali 1x/2x/3x sono riutilizzate senza modifiche e con gli avvisi IPZS inclusi; lo screenshot dell’utente non è distribuito con l’app.

Il numero è ricavato dal campo Subject serialNumber del certificato pubblico già conservato (`IDCIT-` seguito dal numero del documento). Non viene confuso con il PAN/IdServizi, il codice fiscale o il numero seriale del certificato X.509. L’API pubblica di lettura dei dati del certificato e i risultati dell’archivio aggiungono `cardNumber`, senza modificare il formato dell’archivio, gli abbinamenti, i prefissi PIN o le registrazioni Web. Il recupero dei vecchi metadati usa prima il certificato autenticato del relativo record, poi l’eventuale copia pubblica già conservata dal componente Web. Non comporta autenticazione, lettura della carta o importazione dei dati dell’app Universal. Certificati senza un numero riconoscibile mostrano **Numero carta non disponibile**; non vengono generati numeri sostitutivi.

Controlli: 116 test Flutter, analisi statica senza problemi, 20 gruppi CTest macOS e 203 controlli documentali, inclusi rifiuto di numeri ambigui/malformati e separazione dal codice fiscale/PAN. Backend Windows x64 ricompilato con manifest delle stesse 552 sorgenti; esecuzione sul PC Windows non effettuata in questa revisione. Nessun tentativo PIN/PUK reale.

App Universal Apple Development: `/percorso/Builds/CIE-ID/macos-ux5-home/CIE ID.app`. Runtime: `native/runtime/macos-ux5-home` e `native/runtime/windows-ux5-home`.

## Miniatura nella scelta della CIE per la firma — 18 ottobre 2026

Anche l’elenco **Scegli la CIE con cui firmare** usa l’illustrazione originale della CIE, a sinistra di Nome e Cognome. La miniatura misura 72 punti di larghezza e mantiene le proporzioni originali; riusa lo stesso asset della Home e della barra laterale, senza modificare selezione della carta o procedura di firma. Il widget è condiviso tra macOS e Windows.

App Universal Apple Development: `/percorso/Builds/CIE-ID/macos-ux5-card-list/CIE ID.app`. Runtime nativo e componente CryptoTokenKit invariati rispetto a `macos-ux5-home`.

## Numero carta nella scelta della CIE e finestra fissa — 18 ottobre 2026

Le CIE elencate in **Firma Elettronica** mostrano, accanto alla miniatura, Nome e Cognome, il numero stampato sulla carta nella riga successiva e l’indicazione del PIN parziale sotto. Il numero proviene dallo stesso record della Home; non viene sostituito con il PAN se manca.

La finestra macOS usa un contenuto fisso di 1080 × 760 punti, senza ridimensionamento manuale, zoom o schermo intero. Il ripristino delle vecchie dimensioni della finestra è disattivato; restano disponibili spostamento, chiusura e riduzione a icona. La finestra Windows conserva le dimensioni iniziali previste dal runner: sono rimossi il bordo ridimensionabile e la massimizzazione e vengono ignorati i comandi di sistema di ridimensionamento/ingrandimento. I cambi di DPI del sistema continuano a essere gestiti. Il runner GTK imposta anch’esso `resizable = false`.

Aggiornamento Linux del 20 ottobre: il vincolo GTK fisso è stato sostituito
dall'adattamento all'area utile GNOME/KDE, con finestra ridimensionabile e
massimizzazione se necessaria. La dimensione preferita resta 1280×720 in
coordinate logiche, senza doppio scaling. I vincoli macOS/Windows di questa
sezione descrivono la versione di quel momento. [Dettagli e test Linux](LINUX_PACKAGE.md).

Nella successiva modifica del 20 ottobre anche macOS e Windows sostituiscono
i vincoli fissi con adattamento all'area utile, ridimensionamento e zoom o
massimizzazione. I caratteri mantengono la scala del sistema; il comportamento
macOS resta senza fullscreen. Test software su Linux superati; build complete
e verifiche visive delle due piattaforme ancora da eseguire.
[Dettagli multipiattaforma](DESKTOP_WINDOW_SIZING.md).

App Universal Apple Development: `/percorso/Builds/CIE-ID/macos-ux5-fixed-window/CIE ID.app`. Il backend nativo e l’estensione CryptoTokenKit non cambiano. Verifica GUI macOS, 19 test di firma e analisi statica; i runner Windows/Linux richiedono collaudo sulle rispettive piattaforme.


## Messaggi Home e diagnostica — 18 ottobre 2026

Il rilevamento mostra **CIE presente nel lettore**. Ogni carta memorizzata indica
separatamente **CIE abbinata. Puoi firmare documenti** e, soltanto quando dati
pubblici, pubblicazione e componente risultano configurati, **Accesso ai siti
configurato: apri il sito nel browser**. L’osservazione dell’identità da parte
del sistema non modifica più questi messaggi e non costituisce una prova di login.
Configurazioni incomplete mantengono le azioni necessarie, senza essere mostrate
come complete.

**Impostazioni → Log → Diagnostica accesso ai siti** espone abbinamento,
dati pubblici, pubblicazione del certificato, disponibilità del componente e
identità osservata/non osservata. Qui è stato spostato anche l’aggiornamento
manuale dello stato, prima in Dettagli e recupero nella Home. Il rapporto JSON
contiene soltanto flag booleani per le carte, senza nomi, identificativi,
certificati o PIN, anche quando la raccolta eventi è disattivata.

L’assenza di un’identità osservata non genera suggerimenti di reinserimento.
Nella Home l’invito a rimuovere e riappoggiare la carta è limitato agli espliciti
avvisi PC/SC di connessione resettata o carta non alimentata (0x80100068/67),
quando non vi è una CIE già identificata o un lettore occupato. Carta assente,
carta di tipo diverso, errori generici e controlli Web non confermati non attivano
questo invito. Anche i risultati della configurazione avanzata e della prova
CryptoTokenKit generica non lo suggeriscono più indiscriminatamente.

L’interfaccia e le regole sono condivise tra macOS e Windows; nessun nuovo
controllo di stato firma richieste o invia PIN/PUK alla carta.
