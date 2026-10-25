# UX3 — Firma guidata condivisa

Implementato il 18 ottobre 2026 nel prototipo Flutter separato. La grafica Material 3 rimane quella del prototipo; ordine e nomi seguono CIE ID Universal. UI Dart e operazioni C/C++ sono condivise tra macOS e Windows.

## Percorso dell’utente

1. Se ci sono carte abbinate, scegliere la CIE oppure **Firma senza abbinamento**. La scelta rimane disponibile per i documenti successivi. Senza abbinamenti si entra direttamente nella selezione del documento.
2. Trascinare un solo file o premere **Seleziona un documento**. Non occorre ancora avere carta e lettore collegati.
3. Scegliere **Firma PAdES · PDF** oppure **Firma CAdES · P7M** e premere **Prosegui**. Il parser nativo controlla il contenuto effettivo: cambiare l’estensione non rende un file un PDF supportato.
4. Per PAdES, **Aggiungi firma grafica** è selezionata inizialmente e porta all’anteprima locale. Si possono scegliere pagina, posizione, dimensioni e immagine. **Ripristina firma testuale predefinita** ripristina il segno testuale ed è disabilitato quando è già attivo. Nome e Cognome finali vengono sempre letti direttamente dalla CIE autenticata, anche quando viene aggiunta un’immagine personalizzata. Tornando indietro si conservano le scelte; cambiando documento l’anteprima viene invalidata. La grafica senza abbinamento è un’estensione esplicita rispetto al riferimento.
5. Appoggiare la CIE scelta al lettore. L’app richiede automaticamente quattro cifre per l’abbinamento disponibile nell’archivio protetto, otto per la firma senza abbinamento. Se l’abbinamento non è disponibile, **Usa PIN completo** è una scelta esplicita; non viene tentata automaticamente un’altra modalità.
6. **Firma** apre il salvataggio nativo con nome ed estensione proposti. Annullare cancella il PIN e non invia autenticazioni alla carta. Confermare una destinazione avvia una sola operazione. La finestra di sistema consente la sostituzione di un file esistente dopo conferma: il risultato viene prodotto da una copia privata del documento, verificato e solo allora pubblicato atomicamente. In caso di errore il file precedente resta intatto.
7. Una pagina dedicata conferma **File firmato con successo**. **Dettagli della verifica** espande gli esiti tecnici; salvataggio e integrità non equivalgono a fiducia, revoca o validità storica confermate. **Concludi** torna alla scelta del documento.

Un P7M idoneo presenta solo **Aggiungi una firma**: l’integrità delle firme e il contenuto incorporato vengono verificati prima di chiedere il PIN. Non viene creata una nuova busta annidata. Il backend mantiene i controlli successivi di integrità e conservazione delle firme precedenti.

## Dati e coordinamento

- Selezione, controllo del formato, anteprima e firma usano la stessa copia privata del documento. Eventuali modifiche successive al file originale non cambiano i byte già selezionati; per includerle occorre selezionarlo nuovamente. Limite 256 MiB, cartelle temporanee macOS con permessi 0700. Le copie vengono eliminate annullando/concludendo o chiudendo il widget dopo il completamento di un’operazione. Un arresto forzato può lasciare temporanei.
- Documento, formato, carta e aspetto vengono fissati prima del dialogo Salva. La navigazione e le altre azioni sono bloccate finché la firma termina; il monitor carta viene sospeso e drenato prima delle operazioni. La carta attesa viene ricontrollata dal componente nativo prima del PIN.
- Il PIN non entra nella cronologia, nelle preferenze o nella diagnostica; il campo viene svuotato prima del salvataggio e a ogni ritorno/navigazione/cambio carta. Il backend recupera il prefisso protetto: Dart riceve solo le quattro cifre digitate. Nessun tentativo automatico dopo un errore.
- Le immagini personalizzate delle CIE abbinate vengono copiate in sottocartelle separate dell’archivio delle preferenze del solo prototipo. La chiave di cartella è l’identificativo codificato in esadecimale UTF-8, non un hash né un dato anonimo. Nessun nome o PIN è scritto nei metadati delle immagini; il nome verificato resta nei dati pubblici dell’abbinamento v2.
- Il ripristino delle preferenze globali lascia le immagini delle singole CIE; **Rimuovi CIE** ne elimina la copia associata. Il file originale dell’immagine rimane intatto. Le immagini globali precedenti sono conservate e possono essere migrate esplicitamente come copia per la CIE scelta.
- **Usa documento di prova** è disponibile solo in Impostazioni → Strumenti di collaudo. La verifica documentale rimane separata dalla firma; la sua semplificazione è il blocco UX4.
- Nuova API C ABI additiva `cie_bridge_signing_info`: controlla PDF/CMS senza carta, PIN o connessioni. Richiede il runtime UX3; non modifica la versione ABI esistente né il comportamento CryptoTokenKit già collaudato.

## Verifiche eseguite

- `flutter analyze --no-pub`: nessun problema.
- `flutter test --no-pub`: 86 test superati, inclusi varianti grafiche macOS/Windows, preparazione senza carta, scelta della CIE distinta da quella fisicamente presente, PIN parziale automatico e fallback esplicito, annullamento salvataggio senza autenticazione, destinazione esistente rifiutata, parametri immutabili durante Salva, stato occupato, nessun retry, cofirma contestuale e immagini per CIE persistenti/isolate.
- 20 gruppi CTest macOS superati. I controlli del nuovo preflight usano veri PDF e CMS con certificati sintetici effimeri, file con estensioni ingannevoli, CMS attached/detached e firme alterate. Nessuna chiave/certificato di test viene installato nello store di sistema.
- Backend e SDK Universal macOS compilati; backend Windows x64 compilato dalle stesse sorgenti con MinGW. La compilazione incrociata Windows non costituisce esecuzione dei test su Windows.
- Controllo visivo macOS: scelta CIE/senza abbinamento, selettore nativo, formato, anteprima PDF e annullamento; nessun PIN e nessuna operazione privata sulla carta.

## Artefatti locali

- App macOS con firma Apple Development, runtime DSS/LTA privato ed estensione CryptoTokenKit esistente: `/percorso/build/macos-ux3/CIE ID Flutter Prototype.app`.
- Runtime macOS: `native/runtime/macos-ux3`; runtime Windows: `native/runtime/windows-ux3`. Sono output locali esclusi da Git, con manifest/checksum dei binari e delle sorgenti native corrispondenti.
- Nessuna pubblicazione GitHub, notarizzazione o sostituzione dell’app CIE ID Universal. L’attivazione del componente Web non viene modificata durante il controllo UX3.

## Collaudo ancora rinviato

Firma reale PDF invisibile/grafica, P7M e cofirma con questo nuovo percorso; abbinamenti UX2 aggiornati, dialoghi Salva e renderer sul PC Windows. Le precedenti prove reali PDF/P7M con PIN completo/parziale restano valide per le build allora provate, senza estenderle automaticamente a UX3. Cambio PIN e Sblocco Carta reali restano esclusi.


## Correzioni dopo il collaudo della procedura guidata (18 ottobre 2026)

- **Indietro** compare solo nella procedura di Firma Elettronica, a sinistra del titolo CIE ID e allineato al margine del contenuto. Torna a un passaggio precedente della stessa procedura, conservando le scelte e svuotando il PIN; non percorre più la cronologia delle sezioni dell’app. I quattro indicatori CIE → Documento → Tipo di firma → PIN e salvataggio restano visibili; il posizionamento grafico appartiene al terzo passaggio.
- Le carte memorizzate mostrano Nome e Cognome dai dati pubblici verificati dell’abbinamento. Per le configurazioni precedenti viene recuperato, quando disponibile, il soggetto del certificato pubblico già conservato dal solo prototipo. La API additiva `cie_bridge_certificate_name` legge esclusivamente `givenName` e `surname`, rifiuta certificati malformati e campi mancanti/ambigui, non usa CN come sostituto e non autentica la carta. Questo recupero aggiorna solo il nome visualizzato: non promuove fiducia, abbinamenti o configurazioni Web. Se manca il certificato viene mostrato “Carta abbinata” con il percorso di completamento esistente, senza usare il numero tecnico come nome. Certificati e nomi non entrano nei log diagnostici.
- Il segno grafico PDF usa il Nome e Cognome del certificato della CIE effettivamente autenticata. La seconda riga riporta data e ora UTC del momento di preparazione della firma, identiche alla data nei metadati della firma PDF. Non costituisce una marca temporale certificata. Il bordo tratteggiato è disegnato sia nell’anteprima sia nel PDF, anche con immagine personalizzata. L’anteprima indica che la data finale sarà determinata durante la firma.
- Il salvataggio atomico con hard link conservava il flag macOS `UF_HIDDEN` del file temporaneo. Prima della pubblicazione viene rimosso solo l’attributo nascosto (anche Windows); i byte, gli altri flag e il controllo contro la sovrascrittura restano invariati. La stessa correzione si applica all’estrazione P7M. Il PDF segnalato dall’utente è stato reso visibile senza modificarne i byte, con confronto SHA-256 prima/dopo.
- Verifiche software: 104 test Flutter superati, 20 gruppi CTest macOS superati, 166 controlli documentali con certificati sintetici, prova visiva PDF con nome accentato/data/bordo, tre integrazioni documentali sul runtime reale. Backend Windows x64 ricompilato dalle medesime sorgenti; questa compilazione non equivale a esecuzione sul PC Windows. Nessun nuovo tentativo PIN o test reale di Cambio PIN/Sblocco Carta.
- App macOS Apple Development: `/percorso/build/macos-ux4-signing-fixes/CIE ID Flutter Prototype.app`. Runtime: `native/runtime/macos-ux4-signing-fixes` e `native/runtime/windows-ux4-signing-fixes`. Il codice CryptoTokenKit non è stato modificato; l’estensione è stata ricompilata con le librerie aggiornate senza attivarne una nuova registrazione durante i test.


## Seconda revisione dopo il collaudo (18 ottobre 2026)

La prima correzione degli attributi non era sufficiente nel caso segnalato: rimuoveva il flag sul temporaneo mantenendo ancora un nome nascosto e la pubblicazione tramite hard link. Il salvataggio ora crea una directory privata esclusiva con nome non nascosto nella cartella di destinazione e vi produce `documento.pdf`/`documento.p7m`. Dopo la verifica crittografica, su macOS `renamex_np(RENAME_EXCL)` sposta il file atomicamente senza sovrascrivere; su Windows viene usato `MoveFileExW` senza sostituzione. Linux conserva link esclusivo e rimozione del temporaneo. Nessun percorso del file prodotto ha più un nome che inizia con punto. Gli attributi sono corretti sul nome finale, preservando gli altri flag e i metadati: vengono rimossi `UF_HIDDEN` e il solo bit invisibile del Finder su macOS, il solo attributo Hidden su Windows. Anche l’estrazione P7M usa questo percorso. Un errore successivo alla pubblicazione conserva il documento prodotto.

La prova del backend sintetico imposta esplicitamente flag nascosto e FinderInfo invisibile, quindi controlla il file finale e la conservazione degli altri attributi e dei byte. La prova viene ripetuta anche sul Desktop; un controllo differito verifica che il flag non ricompaia. Il documento `Guida_Prana-firmato2.pdf` segnalato dall’utente è stato reso visibile con SHA-256 invariato.

Gli indicatori usano l’allineamento verticale centrale, senza padding diseguale sulle frecce. Quando è selezionata **Aggiungi firma grafica** per PAdES viene di nuovo visualizzato il passaggio **Firma grafica**, con evidenziazione autonoma, tra Tipo di firma e PIN e salvataggio. Le frecce collegano anche il passaggio aggiuntivo.

Il segno comprende ora quattro righe: **Firmato digitalmente da/Signed by:**, Nome e Cognome del certificato, **In Data/On Date:**, data e ora UTC. Le due etichette sono più piccole sia del nome sia della data, con colore azzurro chiaro `#64B5F6`; i dati restano neri. La stessa composizione è usata nel PDF finale, nell’anteprima testuale e nella didascalia delle immagini personalizzate. La misura si adatta alla larghezza, include tutte le righe e conserva il bordo tratteggiato.

Artefatti di questa revisione: app Apple Development in `/percorso/build/macos-ux4-signing-r2/CIE ID Flutter Prototype.app`, runtime `native/runtime/macos-ux4-signing-r2` e `native/runtime/windows-ux4-signing-r2`. La revisione precedente resta disponibile ma non contiene queste correzioni. Nessuna nuova autenticazione reale sulla CIE né modifica a PIN/PUK; l’estensione Web è ricompilata dalle stesse librerie, senza cambiamenti al codice delle sessioni CryptoTokenKit.


Verifica della seconda revisione: 105 test Flutter e analisi statica senza problemi; 20 gruppi CTest macOS; 178 controlli documentali nativi, comprese etichette bilingui, data coerente, PDF ruotati e pubblicazione senza sovrascrittura; tre integrazioni con il runtime documentale reale. La prova del backend sintetico sul Desktop conferma flag Hidden assente subito e dopo 1, 3 e 6 secondi, con byte invariati. Controllati visivamente il PDF a quattro righe e gli indicatori con cinque passaggi nell’app macOS. Backend Windows ricompilato dalle stesse sorgenti: test runtime su Windows e firma reale con CIE restano da ripetere con questa revisione.
