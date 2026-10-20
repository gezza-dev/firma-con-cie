# Stato del progetto e verifiche

Situazione al 20 ottobre 2026. [VALIDATION.md](VALIDATION.md) conserva il diario storico: le attività da svolgere nelle voci precedenti descrivono lo stato di quel momento.

| Ambito | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Interfaccia condivisa | Compilata Universal; eseguita su Apple Silicon | Compilata/eseguita x64 | Collaudo desktop da completare |
| Middleware e SDK | Compilati ARM64/x86_64; test nativi su ARM64 | Backend MinGW x64 e componenti MSVC; test su Windows | Compilazione/test nativi senza carta |
| Firma PAdES/CAdES | CIE reale verificata | CIE reale verificata | Prova reale da eseguire |
| Abbinamento e PIN parziale | Persistenza e firme reali verificate | Persistenza e firme reali verificate | Cache su file testata senza carta |
| Accesso ai siti | CryptoTokenKit e accesso Safari al portale CIE verificati | CSP/KSP e accesso Chrome al portale CIE verificati | Componente di sistema non disponibile |
| Cambio PIN e Sblocco Carta | Test software; collaudo reale da completare | Test software; collaudo reale da completare | Collaudo reale non eseguito |
| DSS/LTA con JVM privata | Predisposto e testato | Predisposto e testato | Assemblaggio non previsto dallo script attuale |

L’esecuzione su un sistema non prova automaticamente la compatibilità con tutti i lettori, le CIE, i browser o i servizi. Il formato LTA non implica da solo una validazione storica positiva: servono prove e una catena di fiducia sufficienti.

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
