# Configurazione automatica dei browser

Dal 27 ottobre 2026 l’avvio dell’applicazione avvia un coordinatore separato
dalle operazioni di firma, verifica e gestione della carta. Inventario e
controlli lavorano su thread nativi/isolati Dart; la registrazione Linux usa
processi helper separati. L’attesa non imposta lo stato occupato dell’app.
Non vengono avviati browser, accessi, operazioni sulla CIE o richieste PIN.

## Piattaforme

| Sistema | Browser configurati | Operazione |
| --- | --- | --- |
| Windows | Edge, Chrome, Firefox | Rilevamento dalle registrazioni di Windows, verifica del componente e uso dell’archivio certificati di sistema |
| macOS | Safari, Chrome, Firefox | Rilevamento Launch Services, verifica/attivazione dell’estensione CryptoTokenKit incorporata |
| Linux | Chrome desktop, Firefox, Firefox Snap | Rilevamento nelle posizioni standard, registrazione NSS tramite gli helper verificati già distribuiti |

Il componente Windows continua a essere installato/aggiornato soltanto
dall’installer con UAC. L’app non eleva i privilegi. Le autorizzazioni macOS
e l’eventuale permesso `firefox:pcscd` di Snap rimangono personali; una
richiesta non riuscita non viene ripresentata ogni trenta secondi.

Firefox su Windows/macOS usa il modulo OS integrato, attivo per impostazione
predefinita da Firefox 90 ([documentazione Mozilla](https://blog.mozilla.org/security/2021/07/28/making-client-certificates-available-by-default-in-firefox-90/)).
Si leggono gli indici dei profili già inizializzati e le preferenze relative
al supporto OS. Un’esplicita disattivazione viene rispettata; nessuna
preferenza viene sovrascritta. Non viene installata un’altra DLL Firefox.
Policy aziendali e configurazioni non standard richiedono una verifica locale.

Su Linux vengono trattati tutti i profili Firefox inizializzati individuati
dagli helper esistenti, inclusi Snap. Chrome usa il database NSS condiviso
dell’utente. Il controllo del piano, i lock, i backup e la conservazione dei
database certificati/chiavi e degli altri moduli restano negli helper.
Moduli in conflitto non vengono sostituiti. Le distribuzioni Flatpak e
Chromium Snap restano escluse; Edge macOS/Linux non viene dichiarato pronto.

## Tentativi differiti e stato Home

Il coordinatore ricontrolla ogni trenta secondi e al ritorno nell’app;
aggiorna lo stato del componente almeno ogni minuto. Le richieste concorrenti
vengono accorpate. Se un browser è aperto o manca un profilo inizializzato,
non viene modificato: il lavoro viene ripreso quando le condizioni lo consentono.
Non vengono creati profili o chiusi processi al posto dell’utente.

Sotto una CIE abbinata, sulle tre piattaforme:

- nessun browser verificato o certificato/componente non pronto:
  **Accesso ai siti con CIE non configurato.**
- almeno un browser verificato e certificato/componente pronti:
  **Accesso ai siti con CIE configurato. Apri il sito nei seguenti browser: …**

Il browser predefinito viene prima se è configurato; gli altri sono ordinati
per nome. Basta un profilo pronto per includere Firefox, mentre gli altri
profili inizializzati continuano a essere trattati. Un errore su un browser
non nasconde gli altri pronti e non compare nella Home come messaggio d’errore.
La rimozione incompleta di una carta conserva le istruzioni di recupero.
Le indicazioni di configurazione sono controlli locali dei prerequisiti:
non certificano l’esito di un’autenticazione TLS o di un sito.

## Log e conservazione dei dati

`logs/browser-setup.jsonl` nella cartella dati persistente dell’app contiene
timestamp, identificativo browser, codice esito, messaggio e codice nativo
quando disponibile. Il log è sempre attivo, anche se la diagnostica generale
è disabilitata; gli esiti invariati vengono deduplicati. Rotazione oltre
512 KiB con una sola copia precedente. Non contiene PIN, dati della carta,
certificati, percorsi o nomi dei profili. I normali log diagnostici restano
disponibili per gli altri controlli del middleware.

Gli abbinamenti, gli archivi pubblici, le impostazioni e la gestione del PIN
restano conservati. Non sono state modificate le DLL del middleware.

## Verifiche e limiti

`test/browser_setup_test.dart` copre esiti parziali, ordine del browser
predefinito, tutti i profili, conflitti, browser aperti/non inizializzati,
riavvio del controllo, log e navigazione durante un inventario pendente.
`windows/runner/tests/browser_inventory_test.cpp` verifica le mappature e
l’inventario Windows in sola lettura, senza scritture nel registro.
Gli helper Linux mantengono i test isolati esistenti.

Il 27 ottobre 2026 l’utente ha confermato il collaudo riuscito della nuova
build Windows. Sono superati 374 test Flutter (4 integrazioni opzionali
saltate), i tre gruppi nativi Windows, 14 controlli Python e 49 controlli
dell’installer isolato. Dopo gli ultimi ritocchi ai log sono stati ripetuti
con successo 21 test mirati; impostazioni e abbinamenti Windows sono risultati
identici byte per byte prima e dopo l’avvio. Nessuna nuova prova privata sulla
CIE è stata eseguita dall’agente.

La compilazione Windows e i test condivisi non equivalgono a collaudo nativo
macOS/Linux del nuovo avvio automatico. Questi due collaudi e le prove di
accesso reali della nuova build rimangono da completare sui rispettivi sistemi.
I precedenti accessi confermati restano documentati in
[WEB_AUTHENTICATION.md](WEB_AUTHENTICATION.md).
