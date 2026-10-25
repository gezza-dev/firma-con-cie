# UX4 — Verifica immediata e risultati condivisi

Implementato nel prototipo Flutter il 18 ottobre 2026, mantenendo grafica Material 3 e codice Dart/C++ condiviso macOS/Windows. L’app CIE ID Universal pubblicata rimane separata.

## Percorso dell’utente

- **Verifica Firma** apre un’area di caricamento con **Seleziona un documento**. Scelta e trascinamento di un solo PDF/P7M avviano subito il controllo; non servono carta, lettore o PIN.
- Durante l’attesa sono disponibili **Annulla verifica**, **Scegli un altro documento** e la navigazione verso le altre pagine. Un controllo già avviato termina entro i limiti del backend, ma il risultato viene scartato se è stato annullato o superato. I controlli dei documenti sono serializzati; non si sovrappongono alle operazioni private sulla CIE.
- Ogni firmatario presenta **Firma**, **Certificato** e **Revoca**, con esiti positivi, negativi e indeterminati distinti. Un campo mancante non viene trasformato in “non valido”; l’integrità non promuove la fiducia nel certificato. Le informazioni di revoca mancanti restano indeterminate, anche quando una parte della catena è verificata.
- La data dichiarata dal firmatario è identificata come non verificata; la data di una marca verificata è indicata separatamente. La marca non implica automaticamente validità storica della firma.
- **Dettagli del firmatario** espande periodo del certificato, catena, emittente, revoca, marca e motivi relativi alle prove storiche. **Validità storica e a lungo termine** conserva l’intera analisi DSS. Gli esiti dei due motori non vengono abbinati ai firmatari sulla sola base dell’ordine degli elenchi. Se esiste solo il risultato DSS, il nome non viene inventato e l’assenza della verifica nativa resta visibile.
- **Nessuna firma trovata**, **Documento non leggibile** e **Verifica non completata** sono esiti distinti. Un errore di rete non diventa “firma non valida”. Codici ed errori originali sono disponibili in **Dettagli tecnici**.
- Dal risultato: **Ripeti verifica** aggiorna il controllo sul file originale; **Scegli un altro documento** apre il selettore; **Concludi** torna alla selezione.
- Per un P7M analizzato e strutturalmente leggibile appare **Estrai documento**, anche se integrità o certificato hanno un esito negativo. Il salvataggio nativo propone un nome senza il suffisso P7M esterno; non sovrascrive file esistenti e non apre automaticamente il contenuto. L’estrazione non certifica la firma e, per buste annidate, estrae un solo livello.

## Copie dei documenti e coordinamento

`VerificationController` è condiviso e indipendente dal rilevamento carta. Prima del controllo crea una copia privata limitata a 256 MiB, con cartella macOS 0700, usata sia per l’analisi sia per l’eventuale estrazione. Il servizio FFI conserva inoltre il contratto preesistente: motore nativo e DSS leggono gli stessi byte.

La copia del controller rimane disponibile fino a Concludi, annullamento, nuova selezione o chiusura. Una modifica del file originale durante la verifica, o prima della conferma dell’estrazione, invalida l’esito e richiede un nuovo controllo. L’id di generazione impedisce di pubblicare risultati arrivati dopo una nuova selezione, l’annullamento o la chiusura. File temporanei ancora in uso vengono eliminati dopo il completamento del lavoro; un arresto forzato o permessi non accessibili possono richiedere pulizia manuale.

Per accertare che il P7M sia estraibile viene eseguita una sola estrazione strutturale nella cartella temporanea privata, senza apertura del contenuto né pubblicazione di file. Questo controllo non richiede firme attendibili o integre. La conferma dell’utente produce poi una nuova estrazione nativa sulla medesima copia, con pubblicazione atomica senza sovrascrittura.

Il monitor carta è sospeso durante i lavori documentali. L’interfaccia non attende il rilevamento per poter selezionare/verificare un documento; il servizio FFI attende soltanto l’eventuale lettura pubblica già in corso prima di entrare nel motore nativo condiviso. Non viene ripetuta alcuna operazione fallita e nessun ramo chiama rilevamento, abbinamento, firma o gestione PIN.

L’annullamento scarta il risultato; non uccide forzatamente il worker nativo/JVM già avviato. Finché termina, le operazioni private restano disabilitate; guida e navigazione rimangono disponibili. Credenziali proxy e regole dei verificatori restano quelle già implementate, senza nuove eccezioni di fiducia.

## Verifiche

- Suite Flutter: 100 test superati, comprese varianti di interfaccia macOS/Windows; 3 integrazioni native disattivate nel comando ordinario e attivate separatamente.
- 3 integrazioni con runtime reale macOS superate: distinzione PDF senza firme/danneggiato, integrità PDF con certificato sintetico autofirmato senza promozione di fiducia, estrazione CMS byte per byte e rifiuto di CMS detached.
- Fixture generate localmente dal test nativo documentale: 135 controlli superati, nessuna carta acceduta e nessun certificato installato nello store.
- Analisi Dart/Flutter senza problemi. Il backend C/C++, l’SDK, l’estensione CryptoTokenKit e i runtime privati DSS/JVM non vengono modificati da UX4: viene riusato il runtime UX3 già compilato per macOS Universal e Windows x64.
- Controllo visivo macOS completato: caricamento nativo, avvio automatico, riepilogo e dettagli del firmatario, data ASN.1 resa leggibile in italiano/UTC, dialogo Salva per l’estrazione e annullamento senza file pubblicati, ritorno alla selezione con Concludi. Nessuna autenticazione sulla carta.
- Il collaudo grafico e l’esecuzione del nuovo Dart sul PC Windows rimangono da eseguire. Le varianti di test Windows sul Mac non equivalgono a esecuzione sul PC.

Riproduzione locale dei test nativi facoltativi, dalla cartella del prototipo:

```sh
native/runtime/macos-ux3/tests/cie_document_tests native/runtime/macos-ux3/libcie-pkcs11.dylib reports/ux4-fixtures
CIE_PROTOTYPE_RUNTIME="$PWD/native/runtime/macos-ux3" flutter test --no-pub --dart-define=CIE_UX4_RUNTIME_TESTS=true test/verification_runtime_test.dart
```

Sono utilizzati solo documenti e certificati effimeri sintetici. Non vengono eseguite operazioni sulla CIE.

## Artefatto locale e limiti

App macOS Universal firmata Apple Development, con runtime DSS/LTA e componente CryptoTokenKit già esistente:

`/percorso/build/macos-ux4/CIE ID Flutter Prototype.app`

Il prototipo non è notarizzato né pubblicato. Nessuna release GitHub, installazione di driver, modifica alle attivazioni Web o richiesta PIN fa parte di UX4. Le prove reali di firma dei nuovi flussi, Cambio PIN e Sblocco Carta restano rinviate. Il prossimo blocco funzionale è UX5; la verifica completa sui due sistemi resta UX6.
