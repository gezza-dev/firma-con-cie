# Chrome su Linux: integrazione NSS con PIN completo

Chrome desktop su Linux può usare lo stesso provider
`libcie_linux_pkcs11.so` già impiegato da Firefox. La registrazione è distinta:
Chrome usa il database NSS condiviso dell'utente, mentre Firefox conserva
la propria configurazione dei dispositivi. Non occorre importare una chiave
privata o un PKCS#12: la chiave della CIE resta sulla carta.

Questa integrazione riguarda **Google Chrome desktop installato da `.deb`**.
La sequenza NSS di selezione del certificato client, associazione alla chiave,
richiesta del PIN e firma PKCS#1 è verificata con carta simulata. **Il 23 ottobre
2026 l'utente ha confermato l'accesso reale riuscito all'area personale con
Chrome su Linux**, seguendo la procedura con PIN completo. Chromium Snap/Flatpak non sono
coperti dalla procedura: accesso alle librerie, archivio pubblico e PC/SC
richiedono una verifica distinta. Non usare i percorsi Firefox Snap per Chrome.

## Collaudo reale del 23 ottobre 2026

Installato `cie-id-desktop 0.1.0~test20261023.2` su Ubuntu 26.10 amd64,
KDE/Wayland; pacchetto Google Chrome desktop rilevato
`156.0.8078.47-1`. Il provider è registrato come `Firma con CIE Linux` nel
database NSS condiviso, inizialmente sotto `/opt/cie-id-desktop`.
La configurazione è avvenuta con PC/SC bloccato, preservando byte per byte
gli archivi certificati/chiavi NSS e le configurazioni Firefox controllate.

Nel successivo collaudo autorizzato, l'utente ha aperto Chrome, seguito
l'accesso con carta e lettore e comunicato: «Accesso riuscito all’area personale».
Le istruzioni richiedevano tutte le otto cifre del PIN soltanto nel browser.
L'agente non ha acquisito il PIN, controllato la sessione autenticata o
modificato Firefox. Il successo è una conferma dell'utente: URL del sito e
protocollo TLS non sono stati rilevati indipendentemente. Il risultato non
attesta compatibilità con tutti i siti, lettori o confezionamenti di Chromium.

Dopo l'installazione della versione `0.1.0~test20261023.7`, Chrome ha mostrato
`No_client_certificate` prima della richiesta del PIN. La registrazione NSS
puntava ancora alla cartella precedente, ormai rimossa. A Chrome chiuso è
stato corretto soltanto il percorso della libreria CIE verso
`/opt/firma-con-cie/cie_native/libcie_linux_pkcs11.so`, senza caricare NSS o
moduli e conservando byte per byte i database certificati/chiavi, le altre
registrazioni e i file Firefox controllati. L'utente ha quindi confermato
nuovamente l'accesso ai siti con Google Chrome riuscito usando il PIN completo.
Anche questo esito deriva dalla conferma diretta dell'utente; l'agente non ha
osservato la sessione autenticata né avviato la prova sulla CIE.

## Configurazione guidata nell’app

**Configura Chrome** apre la procedura per Google
Chrome desktop. Il riquadro compare solo in cima alla Home quando Chrome
è rilevato e la configurazione richiede attenzione. Il riquadro scompare
quando la registrazione corrisponde e non compare nelle Impostazioni.
Sotto la CIE abbinata la Home elenca anche i browser configurati, separati da
virgole: **Firefox**, **Firefox Snap** e/o **Google Chrome**. Lo stato è condiviso
con i riquadri di configurazione; per Firefox Snap serve anche il permesso del
lettore. Se nessun browser è pronto, compare l'invito a usare i riquadri in cima
alla Home. Una lettura non riuscita non viene presentata come una lista vuota.
Quando Chrome è pronto per la configurazione il dialogo mostra **Continua**
e nasconde **Rileggi**; quest’ultimo resta disponibile se manca il database
iniziale o occorre recuperare da un errore.

1. Se non è ancora stato usato, aprire e chiudere Chrome una volta.
2. Aprire **Configura Chrome** e chiudere tutti i processi Chrome, anche in
   background. Non occorrono lettore, carta o PIN per questa procedura.
3. Premere **Continua**, controllare il riepilogo e confermare con **Configura**.
4. Riaprire Chrome. Il successivo accesso ai siti richiede il PIN completo
   di otto cifre nel browser; la configurazione non esegue questa prova.

Non si sceglie un profilo Chrome: il modulo è registrato nel database NSS
condiviso dell’utente, selezionato secondo le stesse regole dello script.
La procedura non crea/ripara database mancanti e non richiede sudo. Snap e
Flatpak non sono coperti. L’installer non esegue la configurazione.

L’ispezione e il riepilogo leggono soltanto metadati e `pkcs11.txt`, senza
inizializzare NSS o caricare moduli. La scrittura richiede un piano ancora
valido, controllo dei processi Chrome/Chromium e lock fra le istanze della
procedura. NSS genera il solo record CIE in un database temporaneo vuoto con
PC/SC bloccato; il record viene poi unito atomicamente a `pkcs11.txt`.
I byte delle registrazioni estranee sono conservati e i moduli estranei non
sono inizializzati. `cert9.db` e `key4.db` non vengono modificati; Firefox,
certificati pubblicati, abbinamenti e permessi Snap restano invariati.
Il backup `cie-chrome-setup-backup.json` contiene soltanto la precedente
configurazione dei moduli, senza copie dei database certificati/chiavi.

Un conflitto o una modifica del piano richiedono un nuovo controllo; nessun
tentativo viene ripetuto automaticamente. Il monitor della carta nell’app
rimane sospeso durante il dialogo. Il controllo della Home è in sola lettura.
I test software usano esclusivamente HOME/database temporanei, incluso un
modulo sentinella che segnala l’eventuale caricamento di componenti estranei.

## Configurazione esplicita, separata dall'installazione

Preparare il certificato pubblico dall'app come per Firefox. Una CIE già
abbinata con dati pubblici verificati non richiede un nuovo abbinamento.
Il browser richiede sempre **tutte le otto cifre del PIN**.

Il pacchetto include il provider nel percorso stabile:

```text
/opt/firma-con-cie/cie_native/libcie_linux_pkcs11.so
```

Conservare anche `libcie_web.so` e `libcie-pkcs11.so` adiacenti. Un aggiornamento
del pacchetto mantiene il percorso; riaprire il browser dopo l'aggiornamento.

La procedura alternativa da terminale usa Python 3 e `modutil` (`libnss3-tools` su Debian/Ubuntu).
Non eseguire come root. Dalla radice dei sorgenti, per vedere il solo piano:

```sh
python3 scripts/configure_chrome_linux.py
```

Il comando predefinito non crea database, non inizializza NSS, non carica
moduli e non cambia configurazioni. Segue la selezione di Chromium M146+:
se esiste `~/.pki/nssdb`, usa quella directory; altrimenti usa
`${XDG_DATA_HOME:-$HOME/.local/share}/pki/nssdb`. Un percorso relativo in
`XDG_DATA_HOME` viene ignorato. `--database` permette di indicare esplicitamente
un database SQL desktop differente; non selezionare profili Firefox o Snap.

Per applicare la registrazione, in un collaudo autorizzato separato:

1. Se manca il database, aprire e chiudere Chrome una volta. Lo script non
   inizializza, reimposta o ripara archivi di certificati/chiavi.
2. Chiudere Chrome/Chromium, inclusi i processi in background.
3. Eseguire come utente del browser:

   ```sh
   python3 scripts/configure_chrome_linux.py --apply
   ```

La registrazione si chiama `Firma con CIE Linux`. L'operazione è idempotente:
nome e percorso già corrispondenti non vengono sostituiti. Una registrazione
omonima con percorso diverso, o lo stesso percorso con nome diverso, causa
un errore senza sostituire moduli. NSS può inizializzare i trasporti dei moduli
durante questa operazione; non viene effettuata alcuna autenticazione o firma
di prova e lo script non raccoglie PIN. Non aggiunge CA, certificati o fiducia.

Per rimuovere **soltanto** la registrazione corrispondente, a browser chiuso:

```sh
python3 scripts/configure_chrome_linux.py --remove
```

Non vengono rimossi abbinamenti, certificati, chiavi o altri moduli. Non si
modificano profili Firefox, permessi Snap, preferenze TLS o policy Chrome.
La registrazione resta un'azione dell'utente: l'installer `.deb` non la esegue.
Nei nuovi pacchetti lo script è disponibile anche in
`/usr/share/doc/cie-id-desktop/tools/configure_chrome_linux.py`.

## Procedura di prova e limiti TLS

Dopo la configurazione, aprire il sito con «Entra con CIE», selezionare la
modalità con carta e lettore, scegliere l'identità e inserire il PIN completo
soltanto nella finestra del browser. Non ripetere automaticamente un PIN
rifiutato. Nessun comando di compilazione o test software avvia questa prova.

Il provider supporta RSA 2048 e PKCS#1 v1.5 con SHA-256/384/512, senza RSA-PSS.
La compatibilità con TLS 1.3 non è dichiarata: un sito che richiede RSA-PSS
per l'autenticazione client non è reso compatibile dalla sola registrazione.
Non abbassare la sicurezza TLS del browser per aggirare il limite.
[Valutazione RSA-PSS](RSA_PSS_FEASIBILITY.md).

## Perché Firefox su Windows/macOS non richiede il modulo manuale

Firefox 90+ trova normalmente i certificati client tramite il sistema su
Windows e macOS. I componenti di questa app sono già integrati con Smart Card
KSP/minidriver e CryptoTokenKit. Su Linux la registrazione PKCS#11 rimane
necessaria. Per evitare il caricamento dalla finestra dei dispositivi si può
usare la policy Firefox `SecurityDevices.Add`, mantenendo le altre policy.
È una configurazione esplicita del browser, non un effetto automatico di PC/SC.
Firefox Snap richiede inoltre percorsi accessibili nel confinamento e il suo
permesso PC/SC. La nuova [configurazione guidata Firefox](LINUX_FIREFOX_SETUP.md)
consente la registrazione per profilo e l'autorizzazione Snap con conferme
separate; non applica policy globali e non modifica la registrazione Chrome.

## Test software

```sh
ctest --test-dir .build/native-linux --output-on-failure
python3 native/platform/linux/web/tests/test_chrome_setup.py -v
```

`linux_chrome_nss` chiama le API usate da `ClientCertStoreNSS` e
`SSLPlatformKeyNSS`: `CERT_FindUserCertsByUsage`, `PK11_FindKeyByAnyCert`,
`PK11_DoesMechanism` e `PK11_SignWithMechanism`, con il parametro `SECItem`
vuoto previsto da Chrome. Il solo modulo simulato può essere caricato; la
chiave RSA e il certificato vengono creati in memoria. Il test verifica una
sola richiesta del PIN sintetico completo, una firma e il rifiuto di RSA-PSS
fra i meccanismi disponibili. NSS può chiedere il PIN già durante la selezione
del certificato; la successiva firma non deve reinviarlo.

I test opzionali del ciclo SQL NSS usano `CIE_NSS_TEST_TOOLS` (directory con
`certutil`/`modutil`) e `CIE_NSS_TEST_FAKE` (provider simulato compilato).
Creano esclusivamente database temporanei: aggiunta, idempotenza, rimozione,
conflitti, percorso con spazi e conservazione byte per byte di `cert9.db` e
`key4.db`, oltre alla registrazione di un modulo estraneo. Non aprono Chrome,
non accedono ai database dell'utente e non usano una CIE reale. I controlli
NSS non equivalgono a un test completo del browser e del sito.

Fonti primarie:

- [Database NSS Linux di Chromium](https://chromium.googlesource.com/chromium/src/+/main/docs/linux/cert_management.md)
- [Selezione del percorso NSS](https://chromium.googlesource.com/chromium/src/+/main/crypto/nss_util.cc)
- [Selezione dei certificati client](https://chromium.googlesource.com/chromium/src/+/main/net/ssl/client_cert_store_nss.cc)
- [Firma NSS di Chromium](https://chromium.googlesource.com/chromium/src/+/main/net/ssl/ssl_platform_key_nss.cc)
- [Certificati client del sistema in Firefox](https://blog.mozilla.org/security/2021/07/28/making-client-certificates-available-by-default-in-firefox-90/)
- [Policy Firefox SecurityDevices](https://firefox-admin-docs.mozilla.org/reference/policies/securitydevices/)

### Dopo il cambio della cartella di installazione

Le registrazioni NSS create prima del passaggio a `/opt/firma-con-cie`
non vengono modificate dall’installer. Se puntano alla vecchia cartella,
rimuoverle esplicitamente con il percorso originale e registrare il nuovo
modulo seguendo la procedura precedente. Non cancellare i database NSS per
aggiornare soltanto il percorso del modulo. Nessun collegamento al vecchio
percorso viene installato.
