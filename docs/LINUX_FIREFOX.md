# Accesso ai siti con Firefox su Linux

Il runtime include `libcie_linux_pkcs11.so`, un provider PKCS#11 2.20 di sola
lettura per l’autenticazione con CIE e PIN completo. Utilizza il motore condiviso
`libcie_web.so` e il trasporto pcsc-lite. Il browser riceve certificato, chiave
pubblica e un riferimento alla chiave privata sulla carta; la chiave privata
non viene esportata.

Il 20 ottobre 2026 l’utente ha confermato **l’esito positivo del test reale di
accesso ai siti con Mozilla Firefox su Linux**, dopo le istruzioni di
configurazione e prova con PIN completo. È una conferma del collaudo manuale,
distinta dai test automatici con carta simulata. Versione e confezionamento
del browser, sito effettivamente usato e protocollo TLS non sono stati
comunicati né verificati indipendentemente. Il risultato non estende il
supporto a tutti i siti, lettori, browser o alle build Snap/Flatpak.
La sola presenza della libreria nel bundle continua a non dimostrare che
Firefox l’abbia caricata o che un sito la accetti.

## Preparazione e configurazione separata

L’abbinamento unico conserva il certificato pubblico verificato; il completamento
Web ne scrive una copia nel namespace `web` della cache privata `file-cache-v3`.
Il provider legge soltanto questo namespace pubblico, senza recuperare il
prefisso PIN degli abbinamenti. Se manca il certificato salvato, il motore può
provare a leggerlo e verificarlo dalla carta senza PIN; una CIE che richiede
l’autenticazione per questa lettura deve essere predisposta prima nell’app.
Il certificato salvato viene nuovamente legato alla carta/SOD dal motore condiviso.

L’applicazione non legge né modifica i profili Firefox, non registra il modulo e
non avvia il browser. Lo stato «certificato predisposto» conserva esplicitamente
la configurazione Firefox come non verificata. Su Linux la prova avanzata
nell’app mostra informazioni e non esegue autenticazioni.

Per la configurazione manuale, Firefox può caricare la libreria
tramite **Impostazioni → Privacy e sicurezza → Certificati → Dispositivi di
sicurezza → Carica**. Il file è `cie_native/libcie_linux_pkcs11.so` nel bundle
completo. Mantenere un percorso stabile per tutta la cartella: le librerie
adiacenti sono necessarie anche quando l’app non è aperta. Il solo file `.so`
non è un pacchetto autonomo. La rimozione della registrazione Firefox resta
un’azione distinta dalla rimozione del certificato locale nell’app.

Questo documento non esegue la configurazione. Le build Snap/Flatpak e gli altri
browser richiedono verifiche separate di accessibilità della libreria e PC/SC.
Non viene dichiarato supporto per Chrome/Chromium in questa integrazione.

## PIN e durata dell’autenticazione

Firefox richiede **tutte le otto cifre**. Quattro cifre, caratteri non numerici,
login amministrativo e login contestuale vengono rifiutati senza inviare PIN
alla carta. Il provider copia il PIN soltanto per una singola `C_Login`, lo
passa una volta al motore e cancella la propria copia. Non conserva il PIN e
non lo ricostruisce dalla cache.

La scoperta pubblica rilascia la connessione prima della finestra PIN. Il login
apre una nuova connessione esclusiva e una transazione PC/SC, legate
all’identificativo e al certificato già selezionati. Lettore occupato o identità
cambiata interrompono l’operazione; non si riconnette e non ripete il VERIFY.
Le sessioni PKCS#11 dello stesso token condividono il contesto autenticato, come
richiede PKCS#11; firme successive calcolano nuove firme senza reinviare il PIN.

Logout, chiusura dell’ultima sessione, finalizzazione, rimozione/reset ed errori
rilasciano la connessione. Dopo 30 secondi senza firma il timer rilascia la
transazione e azzera lo stato autenticato; un nuovo login richiede una nuova
`C_Login` del browser con PIN completo. Il timer non autentica e non conserva
credenziali. Un errore di PIN/firma rende terminale il contesto corrente: occorre
chiudere le sessioni del token (per esempio chiudendo Firefox) e ripartire con
una nuova operazione esplicita. Non vengono eseguiti Cambio PIN o Sblocco Carta.

Una connessione esclusiva protegge la sequenza IAS da altre applicazioni. Il
provider la rilascia con reset della carta per cancellare l’autenticazione fisica.
Il monitor dell’app deve trattare un lettore occupato come temporaneamente non
disponibile. La conferma del login reale non verifica separatamente tutti i
casi di contesa del lettore, rimozione della carta, errore o scadenza.

## Meccanismi e limiti

Sono esposti RSA 2048, `CKM_RSA_PKCS`, `CKM_SHA256_RSA_PKCS`,
`CKM_SHA384_RSA_PKCS` e `CKM_SHA512_RSA_PKCS`. La modalità raw accetta soltanto
DigestInfo DER canonici SHA-256/384/512; non è un servizio di RSA arbitrario.
Le modalità con hash supportano anche `C_SignUpdate`/`C_SignFinal`.
Richieste di dimensione e buffer piccoli non firmano e mantengono l’operazione.
Il motore condiviso verifica la firma contro il certificato prima di restituirla.

SHA-1, RSA-PSS, decifratura, modifica PIN/PUK, creazione/importazione/esportazione
di chiavi e scritture di oggetti non sono supportati. Nessuna CA viene aggiunta
agli archivi di fiducia. RSA-PSS non viene pubblicizzato: non è dichiarata
compatibilità generale con autenticazione client TLS 1.3. Sito e protocollo
vanno verificati senza ridurre le impostazioni di sicurezza del browser.

## Test software riproducibili

Dopo la build nativa Linux descritta in [BUILDING.md](BUILDING.md):

```sh
ctest --test-dir .build/native-linux --output-on-failure
flutter analyze --no-pub
flutter test --no-pub
```

`linux_firefox_pkcs11` carica esclusivamente `libcie_linux_pkcs11_fake.so`: il
provider e il trasporto di produzione vengono compilati con sostituti PC/SC e
motore Web sintetici, senza collegare pcsc-lite o il vero motore. Le firme sono
RSA reali con una chiave creata soltanto in memoria per il test. Il namespace
cache è temporaneo e la build di produzione ignora l’override di test.

`linux_firefox_nss` usa NSS con `NSS_NoDB_Init`: carica solo il modulo simulato
in memoria, seleziona il certificato, richiede un PIN sintetico una volta,
firma e verifica il risultato con OpenSSL. Non apre Firefox e non crea/modifica
un profilo. Il test è aggiunto da CMake quando `libnss3` è disponibile; richiede
anche il comando `openssl`.

`linux_web_public_store` prova il namespace del certificato pubblico con dati
sintetici e una cartella temporanea. Il controllo di disponibilità legge solo
la versione del modulo, senza chiamare `C_Initialize` o enumerare lettori.

Per controllare i metadati di un runtime assemblato:

```sh
python3 native/platform/linux/web/tests/test_packaged_metadata.py \
  /percorso/runtime-linux \
  .build/native-linux/platform/linux/web/libcie_linux_no_card_guard.so
```

Questo controllo precarica obbligatoriamente un blocco delle chiamate PC/SC:
verifica che gli hook di test siano assenti dal provider di produzione, che la
registrazione Firefox resti non verificata e che la vecchia prova Windows non
venga eseguita. Il risultato deve riportare zero chiamate PC/SC.

Riferimenti: [moduli PKCS#11 di Firefox](https://firefox-admin-docs.mozilla.org/reference/policies/securitydevices/),
[implementazione PKCS#11 per NSS](https://nss-crypto.org/reference/security/nss/legacy/pkcs11_implement/index.html),
[PKCS#11 2.40, semantica delle sessioni e firme](https://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/os/pkcs11-base-v2.40-os.html).
Le dichiarazioni PKCS#11 riusate nel repository sono identificate come derivate
da RSA Security Inc. PKCS #11 Cryptographic Token Interface (Cryptoki).
