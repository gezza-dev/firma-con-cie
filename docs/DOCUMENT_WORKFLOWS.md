# Flussi documentali condivisi

Questa integrazione riguarda il prototipo Flutter, separato da CIE ID Universal.
Il codice UI/Dart e le operazioni C/C++ sono gli stessi su macOS e Windows.
Le prove software non eseguono cambio PIN, sblocco o autenticazione della CIE.

## Firma PDF con segno grafico

Nella pagina **Firma Elettronica**, scegliere o trascinare un PDF, selezionare PAdES e aprire
**Aggiungi firma grafica**, Prosegui e poi **Anteprima e personalizzazione**. L'anteprima usa PDFium localmente: nessun documento
viene caricato su un servizio. Scegliere la pagina, spostare il riquadro con il
mouse o i pulsanti e regolare la dimensione. Il segno predefinito riporta il Nome
e Cognome letti dal certificato della CIE usata per firmare. Un’immagine PNG/JPEG
personalizzata può accompagnare il nome. Confermare prepara la copia temporanea
del PDF e l’eventuale immagine; la firma vera avviene soltanto con il pulsante
**Firma**, dopo il PIN e la conferma della nuova destinazione. Per una CIE abbinata con la procedura v2 l’anteprima usa il nome verificato
salvato; in assenza dei metadati mostra un segnaposto. Il nome effettivo viene
sempre riletto dalla CIE dopo la singola autenticazione di firma, senza altro PIN.
Dati mancanti/ambigui o caratteri non rappresentabili dal font PDF impediscono
la produzione del file, senza sostituire il nome o ritentare il PIN.
Il segno grafico è facoltativo e non cambia il valore dei controlli crittografici.

Le coordinate sono relative alla CropBox visualizzata, dall'angolo superiore
sinistro. SDK e anteprima tengono conto delle rotazioni della pagina. L'immagine
viene controllata prima dell'autenticazione: massimo 10 MiB, 8192 pixel per lato
e 16 megapixel. I documenti hanno un limite di 256 MiB; i PDF protetti da password
non sono supportati da questo flusso. Cambiare documento o passare a CAdES
elimina la preparazione grafica. Anche cambiare la CIE invalida l’anteprima.
Indietro conserva il documento e cancella il PIN; Concludi azzera il lavoro terminato. Le copie temporanee vengono rimosse quando si
chiude o si annulla il flusso; un arresto anomalo può lasciarle nella cartella
temporanea privata dell'utente. Non viene memorizzato il PIN.

## Estrazione P7M

In **Verifica Firma**, scegliere o trascinare un P7M e premere **Estrai documento**.
Non occorrono lettore, carta o PIN. Il nome proposto rimuove solo l'estensione
esterna `.p7m`. La destinazione deve essere nuova: non vengono sovrascritti file.
Il risultato viene pubblicato solo al termine dell'estrazione.

L'estrazione restituisce i byte del contenuto incorporato, senza aprirlo o
eseguirlo. Non certifica la firma: usare separatamente **Verifica Firma**. Contenitori
malformati e firme detached, prive del documento incorporato, vengono rifiutati.
Per contenitori annidati si estrae un livello alla volta.

## Trascinamento

Le pagine Firma e Verifica accettano un solo file locale alla volta; cartelle e
selezioni multiple sono rifiutate. Durante operazioni native o finestre modali
il trascinamento è disabilitato. Scegliere un file non avvia firme o letture CIE.

Su Linux il destinatario GTK preferisce `text/uri-list`; il trasferimento tramite
portale resta disponibile quando la sorgente non offre percorsi URI. Lo stesso
componente condiviso gestisce Firma e Verifica: riferimenti ripetuti allo
stesso percorso contano come un solo documento. Quando il desktop non consegna
un percorso utilizzabile, l'app suggerisce il pulsante di selezione e non
mostra l'avviso riservato alle selezioni multiple. Una chiave temporanea del
portale non viene trattata come nome di un file.

Il percorso aggiornato e i limiti di collaudo sono descritti in [SIGNING_UX3.md](SIGNING_UX3.md).

Il flusso di verifica e l’estrazione aggiornati sono descritti in [VERIFICATION_UX4.md](VERIFICATION_UX4.md).

## Collaudo

- Test ABI: parametri grafici non validi, una sola chiamata al firmatario,
  identità della carta, cancellazione del PIN e salvataggi senza sovrascrittura.
- `cie_document_tests`: certificato sintetico effimero, firme PDF su quattro
  rotazioni e CropBox decentrata; verifica crittografica del risultato, estrazione
  CMS attached byte per byte, rifiuto di detached e contenitori danneggiati.
- Test Flutter: selezione tramite drop, rifiuto cartelle/multipli, estrazione
  separata dall'autenticazione e blocco del drop durante una firma simulata.
- Il certificato sintetico non viene installato nell'archivio di fiducia.
- Le nuove firme grafiche con CIE reale richiedono un successivo collaudo umano,
  distinto dalle precedenti prove PAdES/CAdES già riuscite sui due sistemi.

Dipendenze dell'anteprima e relativi checksum: `native/preview/pdfium.lock.json`.
Avvisi: `LICENSES/preview`, rigenerabili con `scripts/prepare_preview.py` dopo
`flutter pub get --enforce-lockfile`. I pacchetti mantengono le proprie licenze.
