# Abbinamento locale e PIN parziale

Il flusso segue CIE ID Universal: la Home riconosce la CIE, **Abbina CIE** richiede il PIN completo una sola volta e **Rimuovi CIE** cancella i dati locali della carta selezionata. La cache appartiene al singolo utente e a questa applicazione; non legge o modifica la cache di CIE ID Universal.

## Archivio condiviso su file

Il runtime usa `file-cache-v3` su macOS, Windows e Linux. Non usa Portachiavi, Gestione credenziali, GNOME Keyring o KWallet per conservare gli abbinamenti. Il percorso dipende dalla cartella dati dell’utente e da un identificativo tecnico stabile, mai dal nome o dal percorso dell’eseguibile:

- macOS: `~/Library/Application Support/it.giancarloezza.CIEID.FlutterPrototype.pairing.v1/cache-v3/`;
- Windows: `%LOCALAPPDATA%/it.giancarloezza.CIEID.FlutterPrototype.pairing.v1/cache-v3/`;
- Linux: `~/.local/share/it.giancarloezza.CIEID.FlutterPrototype.pairing.v1/cache-v3/`.

Ogni file `.card` contiene un record binario versionato con le prime quattro cifre del PIN, se abbinate, e i dati pubblici verificati della carta (certificato, Nome e Cognome). Il numero stampato della CIE viene ricavato dal certificato. Il PIN completo, le ultime quattro cifre e il PUK non vengono salvati. I file `.web` conservano la copia del certificato pubblico necessaria al provider Windows, nello stesso formato cifrato.

Il record è cifrato con AES-256-CBC, IV casuale e HMAC-SHA256 in modalità encrypt-then-MAC. Due sottochiavi distinte vengono derivate con HMAC-SHA256 e contesti separati dalla chiave principale casuale locale di 64 byte. Il MAC autentica intestazione, IV, cifrato, tipo di record, identificativo della CIE e spazio dei nomi dell’app. Il controllo del MAC precede sempre decifratura e analisi del padding. I test includono un vettore di riferimento indipendente per confrontare i backend crittografici: CommonCrypto su macOS, CNG su Windows e OpenSSL 3 su Linux. L’esecuzione dei test su ciascun sistema è documentata separatamente in STATUS.md.

La chiave principale è nel file separato `.key`: non è fissa, non è nel codice e non deriva dal PIN. Una chiave mancante o danneggiata con record esistenti non viene rigenerata automaticamente. Non esiste un fallback in chiaro o al vecchio gestore credenziali.

### Protezione e limiti

Su macOS/Linux la directory è `0700` e i file sono `0600`, di proprietà dell’utente corrente. Su Windows directory e file hanno una DACL protetta riservata al SID dell’utente corrente. Sono rifiutati collegamenti simbolici/reparse point, file non regolari, hard link e permessi non conformi quando si leggono chiave o dati. Scritture su file temporanei privati, flush e sostituzione atomica evitano record troncati; un lock fra processi serializza le modifiche.

Questa scelta ha un limite concreto: **la chiave è un file locale**, non è isolata in un gestore credenziali del sistema. Un programma che può leggere i file del medesimo utente (o un amministratore) può recuperare anche la chiave. La cifratura non offre quindi la stessa separazione fra applicazioni del Portachiavi. La cache resta protetta dai permessi dell’account e dall’eventuale cifratura del disco. Non è un formato di backup da condividere insieme alla chiave.

Il formato della cache non è compatibile byte per byte con il file `.cache` di Universal. Non viene riutilizzata la chiave statica della sua implementazione dimostrativa.

## Passaggio dai vecchi abbinamenti

La scelta per questa migrazione è un **nuovo abbinamento con il PIN completo**. Nessun prefisso PIN o altro dato viene importato automaticamente dal Portachiavi, da Gestione credenziali o dall’app originale. I vecchi elementi non vengono cancellati automaticamente; il nuovo runtime non li consulta. Una configurazione Web precedente non ricompare da sola nella Home come carta abbinata. I certificati pubblici già pubblicati nel sistema restano separati fino alla successiva configurazione/rimozione esplicita.

Dopo il nuovo abbinamento verificare persistenza al riavvio, firma PDF e P7M con PIN parziale e rimozione dalla Home. Le precedenti prove reali del vecchio archivio non attestano automaticamente il nuovo formato.

## Procedura e rimozione

L’ABI `cie_bridge_enroll` esegue una sola autenticazione, verifica IAS/DAPP e SOD, salva i dati pubblici verificati e il prefisso nativo, poi prepara il certificato per l’accesso ai siti. La pubblicazione usa il certificato già verificato e non ripete il PIN. Non ci sono tentativi automatici dopo un errore. Gli errori di salvataggio restano distinti dall’esito dell’autenticazione.

La firma con PIN parziale ricompone le otto cifre solo nel ponte nativo, controlla l’identità della carta e azzera i buffer al termine. Il login Web continua a richiedere le otto cifre nella finestra del sistema: né CryptoTokenKit né il minidriver usano il prefisso per accedere ai siti.

**Rimuovi CIE** coordina la sola configurazione Web di questa applicazione e cancella il file `.card` esatto, senza decifrarlo. Si può quindi rimuovere anche un record cifrato danneggiato o la cui chiave manca, purché la directory sia accessibile e il file sia regolare. La rimozione è ripetibile, non chiede PIN, non autentica la carta e non modifica altre carte o certificati. Su Windows vengono rimossi soltanto certificati MY con il marcatore di proprietà di questa applicazione. CryptoTokenKit e lo store certificati Windows restano necessari per il browser: sono distinti dall’archivio degli abbinamenti.

Un errore parziale mostra **Riprova rimozione** nella sessione corrente, senza proporre di riconfigurare la carta. Le immagini personalizzate vengono eliminate solo dopo il successo nativo. Cambio PIN e Sblocco Carta continuano a invalidare durevolmente l’abbinamento prima dell’operazione; il fallimento della pulizia non causa un nuovo tentativo sulla carta. Le prove reali di queste due funzioni restano separate.

## Test

```sh
ctest --test-dir .build/native-macos --output-on-failure
python3 scripts/test_pairing_runtime.py --runtime native/runtime/macos-file-cache --report reports/pairing-file-cache.json --file-store-test
```

I test della cache usano esclusivamente directory temporanee e dati sintetici. Il binario è compilato con `CIE_PAIRING_TEST_SERVICE`; solo questa build accetta `CIE_PAIRING_TEST_CACHE`. Le prove coprono riavvio, eseguibili rinominati, conservazione di un’altra carta, IV casuale, alterazione di tutti i byte del cifrato/tag, chiave errata o mancante, permessi, symlink, lock e cancellazione senza decifrare. Non contattano una CIE e non modificano archivi di credenziali reali.

Su Windows il provider smart card deve essere ricompilato e incluso nel nuovo payload: un vecchio minidriver continuerebbe a cercare la copia pubblica nel vecchio archivio. I test del certificato Windows restano espliciti e usano soltanto un certificato sintetico nel suo spazio di test. Per stato e collaudi hardware vedere [STATUS.md](STATUS.md).
