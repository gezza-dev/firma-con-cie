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
| Linux | Chrome desktop, Firefox, Firefox Snap | Rilevamento nelle posizioni standard e dai metadati dei profili Firefox inizializzati, registrazione NSS tramite gli helper verificati già distribuiti |

Il componente Windows continua a essere installato/aggiornato soltanto
dall’installer con UAC. L’app non eleva i privilegi. Le autorizzazioni macOS
e l’eventuale permesso `firefox:pcscd` di Snap rimangono personali; una
richiesta non riuscita non viene ripresentata ogni trenta secondi.

Firefox su Windows/macOS usa il modulo OS integrato, attivo per impostazione
predefinita da Firefox 90 ([documentazione Mozilla](https://blog.mozilla.org/security/2021/07/28/making-client-certificates-available-by-default-in-firefox-90/)).
Su Windows si leggono gli indici dei profili già inizializzati e le preferenze
relative al supporto OS; un'esplicita disattivazione mantiene il browser escluso
dall'elenco dei pronti. Su macOS si usano Launch Services e la versione pubblica
del bundle Firefox: versioni precedenti alla 90, o non verificabili, restano
escluse. Il profilo privato non viene letto e non è richiesto l'accesso ai dati
di altre app o l'accesso completo al disco. Nessuna preferenza viene modificata
e non viene installata un'altra libreria Firefox. Eventuali disattivazioni
private del modulo OS o policy aziendali su macOS restano operative nel browser
e non sono certificabili da questo inventario dei prerequisiti. Il collaudo
di accesso e le configurazioni non standard restano verifiche distinte.

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

La verifica Linux ha rilevato una possibile sovrapposizione tra la lettura
iniziale degli abbinamenti e quella dello stato del componente. La correzione
locale ritenta soltanto la query dei metadati quando riceve `busy`, fino a
cinque letture con attese asincrone di 200 ms. Uno stato ancora occupato non
viene conservato per un minuto come assenza del componente. Non vengono
ritentate operazioni sulla carta, firme o invii del PIN.

Il controllo automatico parte dopo il caricamento del middleware e la lettura
iniziale degli abbinamenti. Gli eventi di attivazione della finestra durante
questo caricamento non avviano controlli concorrenti. Questo evita il falso
errore iniziale «Attendere il completamento dell’operazione», riprodotto con
un evento di focus anticipato e coperto da test software con dati sintetici.

L'inventario Linux riconosce Chrome e Firefox nelle posizioni standard del
sistema, oltre a `/snap/bin/firefox`. Riconosce anche Firefox estratto in una
cartella personale, per esempio Download: legge `LastPlatformDir` da
`compatibility.ini` dei profili nativi inizializzati indicizzati da `profiles.ini`
(cartelle Mozilla tradizionale e XDG). Verifica che l'installazione indicata
esista ancora, abbia l'identità Firefox in `application.ini` e un eseguibile ELF
con permesso di esecuzione. Non esegue il browser, non scandisce Download o
l'intera Home e non modifica questi metadati. Profili obsoleti, non inizializzati,
Snap o Flatpak non fanno dichiarare presente Firefox standard. Il coordinatore
continua a includere un browser tra i pronti solo dopo la verifica della sua
configurazione NSS; la sola presenza dell'eseguibile non basta.

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
`test/linux_browser_inventory_test.dart` copre Firefox estratto nelle cartelle
personali, coesistenza con Snap, percorsi XDG, installazioni rimosse, identità
ed eseguibili non validi, metadati mancanti e conservazione dei file. Verifica
anche che entrambi i Firefox già configurati compaiano senza nuove scritture NSS.
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

Il 27 ottobre 2026 il commit `1628af0` è stato compilato anche per macOS
Universal, con firma Apple Development e DMG verificato dopo montaggio e copia.
Sono superati analisi Flutter, 374 test Flutter (4 integrazioni opzionali
saltate), 27 gruppi nativi, 21 controlli del componente macOS, 14 casi DSS/LTA,
19 casi storici e 37 controlli di trasporto. Avvio, navigazione e chiusura
dell'app sono riusciti; la Home ha mostrato Safari e Chrome pronti. Le
impostazioni, gli abbinamenti, i certificati pubblici e i file dei browser
controllati sono rimasti invariati. Nessuna autenticazione o richiesta PIN
è stata avviata durante queste verifiche.

L'utente ha confermato riuscito l'accesso CIE tramite Firefox su macOS. Il
successivo controllo diagnostico ha individuato la causa di
`profile_inspection_failed`: la protezione macOS dei dati di altre app negava
la lettura di `profiles.ini` (`PathAccessException`, errore POSIX 1, Operation
not permitted). L'inventario corretto non legge più il profilo Firefox macOS;
usa soltanto metadati pubblici del browser e stato del componente di sistema.
I test verificano che il lettore dei profili non venga chiamato su macOS, che
versioni sconosciute/non supportate non siano dichiarate pronte e che Windows
conservi i controlli delle preferenze. Le protezioni di macOS restano invariate.

Il nuovo helper nativo si verifica senza aprire browser o profili:

```sh
mkdir -p .build/macos-browser-inventory
xcrun swiftc macos/Runner/BrowserInventory.swift test/macos_browser_inventory/main.swift \
  -o .build/macos-browser-inventory/tests
.build/macos-browser-inventory/tests
```

L'opzione facoltativa `--inspect-installed` aggiunge il solo inventario di
browser/versioni installati. Il collaudo nativo Linux del nuovo avvio automatico
e gli accessi reali rimangono distinti dai test condivisi.

La correzione macOS è stata ricompilata Universal e verificata nell'app firmata:
la Home e il log dedicato mostrano Safari, Firefox e Chrome pronti, senza nuovi
`profile_inspection_failed`. Sono passati 377 test Flutter (4 integrazioni
opzionali saltate), 19 controlli nativi dell'inventario e i controlli del
componente CryptoTokenKit. Profilo/preferenze Firefox e dati locali delle CIE
sono risultati identici nei confronti prima e dopo l'avvio. Il DMG Apple
Development è stato verificato dopo montaggio e copia; non è notarizzato.
I precedenti accessi confermati restano documentati in
[WEB_AUTHENTICATION.md](WEB_AUTHENTICATION.md).
