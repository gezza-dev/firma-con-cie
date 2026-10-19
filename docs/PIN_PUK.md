# Cambio PIN e sblocco tramite PUK

Le pagine **Cambia PIN** e **Sblocca Carta** usano lo stesso codice Flutter,
ponte C e adattatore IAS su macOS e Windows. Non richiedono un abbinamento:
si inseriscono il PIN/PUK completo e il nuovo PIN, entrambi di otto cifre.
Il nuovo PIN deve contenere otto cifre numeriche e corrispondere alla conferma.
Non vengono applicate regole di complessità: sono accettate cifre ripetute,
sequenze consecutive e un valore uguale al PIN attuale. Resta alla carta
l’esito effettivo dell’operazione.

Il protocollo riusa InitEncKey, DH/DAPP, VerifyPIN/VerifyPUK e ChangePIN di IAS.
L'adattatore si connette esclusivamente al lettore selezionato e controlla
l'identità della CIE prima di trasmettere credenziali. Il callback dedicato
preserva l'accesso esclusivo durante il reset iniziale e non riconnette/reinvia
comandi dopo errori di trasmissione. Una sola verifica della credenziale,
seguita al massimo da un comando di modifica. Nessuna autenticazione aggiuntiva
di controllo viene eseguita automaticamente dopo il successo.

ABI v1 estesa in modo additivo: `cie_bridge_change_pin` e
`cie_bridge_unblock_pin`, con capability `canChangePin`/`canUnblockPin`.
Il risultato espone solo stato, codice e tentativi residui quando comunicati
dalla carta. PIN e PUK non vengono inseriti nei risultati o nei log, né salvati
in cache. I campi vengono svuotati prima dell'invio e all'annullamento/uscita;
i buffer del ponte/adattatore e FFI sono azzerati in ogni uscita. Le stringhe
gestite Dart e i buffer interni legacy non offrono una garanzia completa di
azzeramento di ogni copia in memoria, come per la firma del prototipo.

Se si perde la risposta durante la modifica, il risultato è
`pin_operation_indeterminate`: il nuovo PIN potrebbe essere già attivo.
Il prototipo non ripete l'operazione. Un PUK bloccato è distinto da un PIN
bloccato; i tentativi residui non vengono inventati quando non sono disponibili.
La cache degli abbinamenti dell'app precedente non viene letta né aggiornata:
dopo una modifica reale potrebbe essere necessario ripetere quegli abbinamenti.

## Prove automatiche, senza modificare una CIE

```sh
python3 scripts/test_pin.py --runtime native/runtime/macos-pin-puk --report reports/macos-pin-puk-automated.json
```

Su Windows usare Python a 64 bit e il runtime `native/runtime/windows` del kit.
Lo script controlla i checksum, le capability del runtime reale e il rifiuto
degli ingressi malformati prima di qualsiasi accesso alla carta. Esegue inoltre
40 casi di sessione IAS simulata e i confini ABI con backend sintetici:
ordine dei comandi, carta sostituita, PIN/PUK errati o bloccati, mancata risposta
alla modifica, azzeramento dei buffer e assenza di retry. Non invia un PIN/PUK
alla carta e non modifica contatori di tentativi.

`flutter test` copre con servizi sintetici anche validazione, conferma,
annullamento, campi protetti, rimozione delle credenziali, contatori ed esito
indeterminato. I test software non attestano il successo sulla CIE fisica.

## Prova manuale su ciascun sistema

1. Chiudere le altre applicazioni che usano il lettore, collegare il lettore
   e appoggiare la CIE. Aprire la nuova build separata del prototipo.
2. Attendere il rilevamento automatico della CIE e controllare la carta selezionata.
3. In **Cambia PIN**, inserire personalmente nell'app il PIN attuale e un nuovo
   PIN noto, con la relativa conferma. Conservare il nuovo PIN in modo sicuro.
4. Premere **Modifica il PIN**, leggere e confermare la richiesta. Tenere la
   carta ferma fino all'esito. Non inviare PIN o PUK in chat o nei report.
5. Comunicare soltanto l'esito. Per provare la nuova credenziale si può firmare
   il documento di prova con il nuovo PIN, una volta, su iniziativa dell'utente.
   L'eventuale ripristino del PIN precedente è un'altra modifica esplicita.
6. Per **Sblocca Carta**, usare soltanto un PUK completo e noto e impostare
   personalmente il nuovo PIN. Non bloccare intenzionalmente la CIE con PIN
   errati e non usare credenziali errate per verificare i messaggi: quei casi
   sono coperti dalle simulazioni. Un test PUK reale modifica comunque il PIN.
7. In caso di esito indeterminato, interrompere le prove e annotare il solo
   messaggio: non ripetere automaticamente e non alternare tentativi con vecchio
   e nuovo PIN. Errori di lettura/esclusività prima dell'autenticazione richiedono
   prima di tutto la verifica del lettore e delle altre app aperte.

Mac e Windows usano la medesima carta fisica: se il PIN è stato cambiato sul
primo sistema, sul secondo il PIN attuale è quello nuovo. I test della firma,
della verifica e del rilevamento restano separati dalle modifiche PIN/PUK.

## Invalidazione dell’abbinamento e Portachiavi

Prima di confermare, pagina e dialogo avvisano che l’abbinamento locale verrà
disabilitato, anche quando il tentativo non riesce. Occorre poi ripetere
**Abbina CIE** dalla Home con il PIN completo. Lo stesso vale per lo sblocco con PUK.

Il ponte nativo registra prima un marcatore persistente senza credenziali,
separato dal Portachiavi/Gestore credenziali e limitato all’utente e a questa app.
Tenta poi di cancellare separatamente prefisso PIN e dati pubblici dell’abbinamento.
Un errore di cancellazione non impedisce la singola operazione sulla carta.
L’eventuale prefisso rimasto non è leggibile per firmare con PIN parziale; la
carta non ricompare negli elenchi dopo il riavvio, nemmeno attraverso i metadati Web.
Solo un nuovo abbinamento autenticato e salvato rimuove l’invalidazione.
Le configurazioni Web pubbliche e gli archivi delle altre applicazioni non vengono cancellati.
Se non si può registrare l’invalidazione persistente, si interrompe prima di
trasmettere credenziali (`pairing_invalidation_unavailable`, `outcome=not_started`).

Su macOS la cancellazione recupera solo il riferimento persistente dell’esatta
voce locale del servizio dell’app, poi usa `kSecMatchItemList` come richiesto
da `SecItemDelete` su macOS. Non legge il prefisso, non modifica ACL, non allarga
l’accesso e non apre richieste di autenticazione per la pulizia. Il risultato
primario della carta è separato da `cleanupWarning`, `cleanupCode` e dal codice
numerico OS `cleanupNativeCode`: una pulizia incompleta non viene presentata come
un cambio PIN fallito. La diagnostica può registrare il codice OS senza dati della CIE.
Il vecchio messaggio scartava OSStatus, quindi la causa OS esatta del precedente
errore non è ricostruibile. La nuova cancellazione è collaudata con credenziali
sintetiche in un servizio separato; nessun abbinamento reale è modificato dai test.

`native/tests/test_pin_invalidation.py` simula Portachiavi bloccato, errore nella
sola cancellazione, successo, PIN/PUK errati, esito incerto e mancata scrittura
dell’invalidazione; verifica persistenza in un secondo processo, blocco della
firma parziale obsoleta e una sola chiamata all’adattatore. Non usa PC/SC reale.

La pagina mostra un solo avviso sull’invalidazione dell’abbinamento, prima del
pulsante di conferma. Sono stati rimossi il paragrafo sulla complessità del PIN,
il paragrafo finale sugli altri abbinamenti e la spiegazione tecnica sull’errore
di pulizia non bloccante; l’eventuale pulizia incompleta resta segnalata nel risultato.
