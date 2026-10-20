# Stato del progetto e verifiche

Situazione al 20 ottobre 2026. [VALIDATION.md](VALIDATION.md) conserva il diario storico: le attività da svolgere nelle voci precedenti descrivono lo stato di quel momento.

| Ambito | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Interfaccia condivisa | Compilata Universal; eseguita su Apple Silicon | Compilata/eseguita x64 | Collaudo desktop da completare |
| Middleware e SDK | Compilati ARM64/x86_64; test nativi su ARM64 | Backend MinGW x64 e componenti MSVC; test su Windows | Compilazione/test nativi senza carta |
| Firma PAdES/CAdES | CIE reale verificata | CIE reale verificata | PDF e P7M con CIE reale e PIN parziale verificati |
| Abbinamento e PIN parziale | Persistenza e firme reali verificate | Persistenza e firme reali verificate | Abbinamento, persistenza e firme con PIN parziale verificati |
| Accesso ai siti | CryptoTokenKit e accesso Safari al portale CIE verificati | CSP/KSP e accesso Chrome al portale CIE verificati | Provider Firefox PKCS#11; test reale con Mozilla Firefox riuscito, confermato dall’utente |
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
