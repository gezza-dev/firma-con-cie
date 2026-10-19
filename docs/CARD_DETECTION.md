# Rilevamento della CIE

Il rilevamento del prototipo legge soltanto i dati pubblici della carta. Usa lo
stesso adattatore C++ su macOS e Windows, senza abbinamento o cache dell'identità.

Il percorso precedente costruiva una sessione completa per la firma: reset,
selezione IAS, lettura PAN, selezione CIE, identificativo servizi e reset alla
disconnessione. Ora seleziona prima il parent MF/IAS previsto per la famiglia
della carta, poi l'applicazione CIE e legge l'identificativo servizi con gli
stessi metodi IAS già usati dal middleware. Non legge il PAN e non resetta.

La transazione PC/SC protegge la selezione e la lettura da altri client.
Alla chiusura, anche in caso di eccezione, termina la transazione e disconnette
con `SCARD_LEAVE_CARD`. L'ATR deve appartenere ai tipi CIE riconosciuti dal
middleware. Il callback ammette solo SELECT, READ BINARY e GET RESPONSE con
CLA 00, fino a 16 comandi; rifiuta reset, autenticazione e scritture. Non
riconnette o ritenta dopo un errore del trasporto. Restano consentite le
normali correzioni della lunghezza di lettura previste dal protocollo IAS.

Firma, Cambio PIN e Sblocco Carta conservano le proprie sessioni complete,
con nuova verifica dell'identità prima dell'autenticazione. Non usano
l'identificativo precedentemente rilevato come prova di autorizzazione.

## Misure iniziali sul Mac — 17 ottobre 2026

Queste misure riguardano la prima variante con selezione diretta CIE. La
successiva prova Windows ha richiesto di aggiungere la selezione parent MF/IAS
descritta sotto. Non sono nuove misure hardware della variante corretta.

Lettore miniLector AIR DI v3, interfaccia contactless, CIE reale. Nessun PIN o
PUK inviato, nessuna modifica alla carta. Le sonde macOS erano firmate Apple
Development con entitlement smart card; le precedenti sonde CLI prive di tale
firma restituivano zero lettori e non sono misure valide delle prestazioni.

| Percorso | Prima, mediana | Dopo, mediana | Prove per versione |
| --- | ---: | ---: | ---: |
| Connessione e identificazione pubblica | 922 ms | 208 ms | 3 |
| Rilevamento completo attraverso il ponte C | 1.784 ms | 547 ms | 12 |

Il confronto del ponte C alterna tre processi per versione, con quattro
rilevamenti ciascuno. Intervalli: 1.556–2.025 ms prima, 514–656 ms dopo.
Il caricamento delle librerie è misurato separatamente ed escluso dalla tabella.
La sonda candidata invia quattro APDU sulla carta provata; l'identificativo
restituito dall'adattatore finale coincide con quello del percorso precedente.

Sono misure a lettore già collegato, su un solo modello di carta e lettore.
Non misurano il tempo di prima inizializzazione dopo l'inserimento USB, né
garantiscono lo stesso miglioramento su altre carte o sistemi. La GUI aggiornata
è stata controllata separatamente: mostra la CIE riconosciuta e l'interfaccia
a contatto vuota. I tempi della tabella sono nativi, non tempi ricavati dalle
osservazioni dell'interfaccia.

Otto gruppi CTest macOS superati, inclusi 32 controlli iniziali della policy di lettura,
32 casi PIN/PUK simulati, confini ABI, middleware, SDK e sicurezza. Bundle e
librerie Universal firmati Apple Development, checksum verificati. Nessuna
modifica Dart, al worker DSS o alle dipendenze. La compilazione incrociata
Windows x64 passa con 494 fingerprint nativi/script identici; questa specifica
ottimizzazione è stata quindi trasferita al PC Windows per il confronto reale.

## Correzione dopo la prima prova Windows

La prima variante restituisce `6A82` alla selezione diretta CIE sul PC Windows:
la connessione T=1, la transazione e la lettura ATR riescono, il tipo CIE è noto,
ma l'applicazione non viene selezionata. La baseline riconosce invece la carta
in 12/12 letture (mediana 212 ms). Le letture fallite della prima variante non
costituiscono un miglioramento delle prestazioni.

Il percorso condiviso corretto esegue sempre `SelectAID_IAS()` prima di
`SelectAID_CIE()`: il middleware sceglie MF oppure IAS secondo la famiglia della
carta. Non introduce fallback, reset, lettura PAN o autenticazione. Il test
di regressione simula la selezione diretta rifiutata e verifica la navigazione
dal parent sia con parent già selezionato sia da un precedente EF. I controlli
di identificazione diventano 37; gli otto gruppi CTest Mac passano e Windows
compila dagli stessi 494 fingerprint. Il collaudo hardware Windows della
correzione è registrato separatamente dalle misure iniziali del Mac.

## Misure Windows della correzione — 17 ottobre 2026

Sul PC PC Windows di collaudo Windows x64, con lettore e CIE reali, il confronto corretto
usa la precedente build PIN/PUK come baseline e lo stesso codice condiviso
MF/IAS → CIE del nuovo runtime Mac. Tre processi alternati per versione,
quattro rilevamenti ciascuno: 12/12 campioni validi per entrambe le versioni.

| Rilevamento completo via ABI | Mediana | Minimo | Massimo |
| --- | ---: | ---: | ---: |
| Baseline PIN/PUK | 223,756 ms | 209,562 ms | 230,082 ms |
| Identificazione pubblica con parent MF/IAS | 72,864 ms | 67,504 ms | 79,598 ms |

Riduzione della mediana: 67,4%. Hash del runtime verificati, carta stabile
all'interno di ciascuna serie; nessuna autenticazione PIN/PUK o scrittura.
I tempi escludono caricamento librerie, prima inizializzazione USB e latenza
della GUI. È una misura su un solo lettore e una sola CIE, non una garanzia
di prestazioni per ogni configurazione. Passano anche i 37 controlli della
policy/navigazione e i 32 casi PIN/PUK sintetici sul runtime corretto.

La nuova GUI Windows è stata compilata in Release e riconosce la CIE dopo un
solo clic; gli identificativi non sono inclusi nei report. Passano analisi Dart,
26 test Flutter, 78 controlli di sicurezza e fixture SDK/handle. Sono verificati
494 fingerprint nativi/script e 567 hash runtime sia nel progetto sia nella
build. I 378 file del motore LTV sono invariati. Il caricamento delle librerie,
separato dal rilevamento, ha mediane 86,626 e 91,557 ms (tre processi per versione,
differenza +4,931 ms). L'errore iniziale e un errore transitorio di pulizia della
cartella temporanea smoke, seguito da una ripetizione riuscita, sono conservati
nelle evidenze Windows. Riepilogo locale: `reports/windows-detection-validation-summary.json`.

## Misure Mac del backend corretto — 17 ottobre 2026

Il lettore e la CIE sono stati riportati sul Mac. La nuova prova confronta
la baseline PIN/PUK con il backend MF/IAS → CIE corretto, identico ai 494
fingerprint nativi/script collaudati sul PC Windows. Il precedente prototipo
è chiuso durante il confronto. La sonda ARM64 è firmata Apple Development con
entitlement smart card e chiama la stessa ABI usata dall'app.

Tre processi alternati per versione, quattro rilevamenti per processo:
12/12 campioni validi per entrambe le versioni, identità stabile in ciascuna
serie e identificativo uguale tra i due adattatori (confrontato solo in memoria).

| Rilevamento completo via ABI | Mediana | Minimo | Massimo |
| --- | ---: | ---: | ---: |
| Baseline PIN/PUK | 2.015,360 ms | 1.805,820 ms | 2.086,330 ms |
| Backend corretto con parent MF/IAS | 625,687 ms | 590,819 ms | 635,658 ms |

Riduzione della mediana: 69,0%. Caricamento librerie separato: mediane circa
9,188 e 11,659 ms, tre misure per versione. Non sono misurati la prima
inizializzazione dopo il collegamento USB o il tempo della GUI. Una sola CIE
e un solo lettore non garantiscono gli stessi tempi su ogni configurazione.

La GUI della build `macos-detection-fixed` riconosce la CIE dopo un solo clic,
con una interfaccia contactless occupata e l'interfaccia a contatto vuota.
Gli otto gruppi CTest sono stati ripetuti e superati, inclusi i 37 controlli
identificazione/navigazione e i 32 casi PIN/PUK simulati. Firma Apple Development
e 579 hash del runtime incorporato verificati; ponte C e middleware sono
invariati tra le due varianti. Nessuna modifica al codice di produzione,
autenticazione, firma reale o modifica PIN/PUK in questa ripetizione.

Riepilogo e tempi aggiornati: `reports/macos-detection-validation-summary.json`,
`reports/macos-detection-fixed-benchmark.json`, `reports/macos-detection-fixed-timings.json`.

Evidenze iniziali, escluse da Git: `reports/detection-performance-repeated.json`,
`reports/detection-performance-bridge.json`, `reports/detection-pin-regression.json`
e `reports/detection-optimization-summary.json`.
