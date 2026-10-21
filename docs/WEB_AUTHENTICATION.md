# Accesso ai siti con CIE — componenti sperimentali

## Stato attuale di CIE ID Desktop

La sintesi aggiornata è in [STATUS.md](STATUS.md). L'accesso reale al portale CIE
è stato verificato con Safari su macOS Apple Silicon e Chrome/Firefox su Windows
x64. L'utente ha confermato il 21 ottobre anche il collaudo riuscito con Microsoft
Edge su Windows; versione del browser e protocollo TLS non sono stati rilevati
indipendentemente. Per l'accesso si usa il PIN completo di otto cifre. L'attivazione Windows al primo
abbinamento è descritta in [WINDOWS_WEB_FIRST_USE.md](WINDOWS_WEB_FIRST_USE.md).
Le note successive conservano anche passaggi e limiti storici del porting.

Il 20 ottobre 2026 l’utente ha confermato anche l’esito positivo del test reale
di accesso ai siti con Mozilla Firefox su Linux e, successivamente, con
Firefox Snap usando il PIN completo. La conferma riguarda il
collaudo manuale; sito, versione del browser e protocollo TLS non sono stati
verificati indipendentemente. [Prova e limiti Linux](LINUX_FIREFOX.md).

Il prototipo aggiunge l’autenticazione con carta fisica e lettore (livello 3).
Non modifica CIE ID Universal pubblicata, non implementa il login tramite
smartphone e non abilita il login al sistema operativo. Le prove reali di
Cambio PIN e Sblocco Carta rimangono rinviate.

## Base condivisa

`native/src/cie_web.cpp` espone un’ABI C versionata, senza oggetti C++ tra
provider e backend. CryptoTokenKit e CSP/KSP forniscono trasporto e transazione:
il motore non riapre il lettore, non riconnette, non resetta e non ripete APDU
dopo errori di trasporto. Le risposte ISO di lunghezza corretta previste dal
protocollo IAS restano gestite dalle librerie comuni.

Il motore gestisce identificativo, certificato, SOD, DAPP/secure messaging,
un solo VERIFY PIN per sessione e firma RSA. Un errore di autenticazione o
trasporto rende inutilizzabile quella sessione. I dati vengono ricontrollati
dopo il PIN con lo stesso verificatore rigoroso dei sei DG usato dall’abbinamento.
Il certificato configurato viene legato al DG firmato del SOD anche durante
la scoperta senza PIN e confrontato con quello effettivamente letto dopo il PIN.
La firma restituita dalla carta viene verificata contro il certificato prima
di essere consegnata al sistema. Questo non estende la validazione CSCA del
codice originale: la fiducia nel certificato client è una verifica distinta
del sistema/sito, non un esito implicito del controllo SOD.

Supportati RSA 2048 e PKCS#1 v1.5 con SHA-256/384/512. Rifiutati dati RSA
arbitrari, DigestInfo non canonici, SHA-1, decifratura e RSA-PSS. Non dichiarare
supporto TLS 1.3, che richiede RSA-PSS per firme RSA di autenticazione: serve
un collaudo per ogni sito/browser e la compatibilità dipende dal protocollo
offerto dal servizio. Non vengono cambiate le impostazioni TLS dei browser.

La [verifica di fattibilità RSA-PSS del 21 ottobre 2026](RSA_PSS_FEASIBILITY.md)
non ha individuato un percorso documentato PSS/RSA senza padding per la chiave
client nel profilo CIE e nel middleware attuale. Il supporto PSS per la verifica
del SOD e per altre funzioni del chip non dimostra la possibilità di firmare PSS
con la chiave di accesso ai siti. Le capacità dichiarate restano PKCS#1 v1.5.

## Configurazione del certificato

La Home predispone il certificato nell’**abbinamento unico**, con un solo
VERIFY e verifica rigorosa dei sei DG/SOD. Il materiale pubblico verificato
viene conservato in modo versionato per completare la pubblicazione senza
un altro PIN, anche dopo il riavvio. Le vecchie CIE con solo prefisso richiedono
un aggiornamento esplicito con PIN completo. Procedura, fasi e limiti:
[PAIRING.md](PAIRING.md).

La vecchia configurazione separata resta solo in **Impostazioni → Prove avanzate
accesso ai siti**, per diagnosi e compatibilità. Le API legacy non vengono
concatenate all’abbinamento unico. Il componente di sistema deve essere attivo;
Windows richiede ancora il collaudo KSP/browser. Non si installa automaticamente
il minidriver e non si sostituiscono associazioni di certificati estranee.

- macOS: il runner conserva il solo DER pubblico nelle preferenze del prototipo
  e ne pubblica una copia in un App Group dedicato, condiviso soltanto con la
  propria estensione. Il contenitore non contiene PIN, prefissi o chiavi private;
  i file DER hanno nomi derivati dall’hash dell’identificativo e permessi 0600.
  La rimozione Web elimina entrambe le copie pubbliche. L’estensione crea il
  token dalla carta fisica e legge il DER dal contenitore, verificandolo contro
  il SOD prima di pubblicare certificato e chiave. Non si creano token software
  tramite `addTokenConfiguration`. La scoperta passa al driver senza filtro AID
  nel plist: nel collaudo reale quel filtro impediva la chiamata al driver.
  Il token non chiede neppure la preselezione automatica nelle sessioni:
  il backend IAS esegue la sequenza specifica MF/IAS/CIE. L’autenticazione e la firma della richiesta pendente vengono eseguite
  nella stessa transazione `TKSmartCard`, marcata sensibile. La callback di
  firma successiva può ritirare una sola volta il risultato verificato,
  soltanto per lo stesso DigestInfo canonico. Non viene conservato il PIN
  per riaprire una sessione e non si ripete l’autenticazione dopo un errore.
  Non enumera i lettori dal callback generico di configurazione, per evitare
  attese circolari fra i servizi macOS. Nessun access group condivide PIN o
  cache legacy; l’estensione richiede **otto cifre** nella finestra CryptoTokenKit.
  Ogni sessione ha il proprio stato di autenticazione. Dopo la prima firma,
  le richieste successive possono riusare soltanto il contesto autenticato
  della stessa `TKSmartCard`, appartenente alla stessa sessione OS. Il driver
  controlla il contesto dentro ogni transazione, calcola una nuova firma per
  ciascun DigestInfo e non conserva il PIN né lo reinvia. Le chiamate preventive
  di `beginAuthForOperation` restituiscono un’operazione senza richiesta PIN
  soltanto se il contesto è ancora valido. Rimozione, reset, contesto di un altro
  proprietario, errore di autenticazione o firma rendono la sessione terminale:
  non viene effettuato alcun nuovo VERIFY automatico. Il collaudo 0.1.8 ha confermato che terminare l’ultima transazione sensibile
  perdeva il contesto prima della richiesta successiva. La build 0.1.9 mantiene
  quindi una transazione esplicita (AID nil) fra le callback della stessa
  sessione, con le transazioni annidate bilanciate per ciascuna operazione.
  Un timer serializzato con i delegate la rilascia dopo 30 secondi di inattività;
  errore e distruzione della sessione la rilasciano subito. La scadenza è terminale
  e non avvia nuovi VERIFY. Nessun PIN viene trattenuto dal timer.
  **Login reale riuscito il 17 ottobre 2026** con Safari 27.0.1 sul portale
  ufficiale CIE: utente entrato nella propria area personale. I log confermano
  una sola autenticazione, prima firma e firma successiva, entrambe verificate,
  senza reinvio del PIN; il timer ha poi rilasciato la transazione inattiva.
  La prova riguarda questo sito/browser su Mac Apple Silicon, non tutti i siti
  o i browser e non il KSP Windows.
  Dopo una nuova
  configurazione/rimozione, rimuovere e riappoggiare la carta per aggiornare
  il token fisico. La migrazione della copia pubblica già salvata non richiede PIN.
- Windows: il DER è conservato nelle credenziali dell’utente in un namespace
  distinto dal prefisso PIN. Un contesto certificato marcato viene aggiunto
  a `CurrentUser\MY`, associato al contenitore del Microsoft Smart Card KSP.
  Poiché MY può unificare copie dello stesso certificato, se esiste già quel DER
  associato a un altro componente la configurazione viene rifiutata prima di
  scrivere, senza cambiare l’associazione preesistente. Sostituzione e
  rimozione eliminano soltanto contesti marcati dal prototipo. Non vengono
  aggiunte CA ad archivi di fiducia. Il minidriver accetta otto cifre, oppure
  quattro recuperando il prefisso esclusivamente nell’archivio protetto nativo
  dell’utente già abbinato. Nessun servizio SYSTEM impersona automaticamente
  l’utente per recuperare credenziali.

**Rimuovi configurazione Web** elimina i dati Web del solo prototipo; non
elimina il prefisso per firmare documenti. Viceversa il disabbinamento dei
documenti non elimina automaticamente la configurazione Web: con otto cifre
resta utilizzabile fino alla rimozione esplicita. La chiave privata resta sulla CIE.
Le identità Web sono dati personali locali e non vanno inviate nei rapporti.

## macOS

### Controllo dell’attivazione dalla Home

La prova reale ha mostrato che Elementi login ed estensioni non elenca il token
CryptoTokenKit su questo Mac. Per questo il recupero principale è ora
**Attiva accesso ai siti**, direttamente nella Home: dopo la conferma **Attiva**,
l’host esegue una sola elezione `pluginkit -e use` limitata all’identificativo
fisso della propria estensione incorporata. Non accetta comandi, identificativi,
percorsi o credenziali dal chiamante, non registra bundle e non cambia altri
middleware. Il risultato viene verificato rileggendo lo stato del componente;
il solo successo del comando non basta a dichiarare riuscita l’attivazione.

La Home controlla la configurazione CryptoTokenKit insieme all’elezione della
sola estensione CIE ID tramite `pluginkit -m`: è una lettura, non esegue
registrazioni né cambia lo stato di altre estensioni. L’assenza della carta o
di una chiave osservabile non viene interpretata come disattivazione. Il
controllo dell’elezione avviene fuori dal thread dell’interfaccia, con un limite
di due secondi; un esito sconosciuto non viene presentato come consenso negato.

Se il componente incluso richiede attenzione, una CIE già abbinata mostra
il pulsante di attivazione anche quando la pubblicazione del certificato non è
ancora terminata. L’operazione avviene fuori dal thread dell’interfaccia, con
un timeout e senza ripetizioni automatiche. Annullamento ed errore conservano
l’abbinamento. Il canale di apertura delle Impostazioni di Sistema rimane
separato, come ripiego, senza essere considerato un’attivazione riuscita.

Al ritorno nell’app, lo stato viene aggiornato anche senza lettore. Quando il
componente passa da non disponibile a disponibile, l’eventuale pubblicazione
pendente viene completata una volta con i dati pubblici verificati già salvati,
senza autenticare la carta. Un errore non causa un ciclo di tentativi: restano
disponibili abbinamento e completamento manuale. Le CIE in rimozione non vengono
riconfigurate. Il controllo non attesta un login riuscito nel browser.

Test software mirati: `flutter test test/macos_web_activation_test.dart`.
Il classificatore nativo può essere verificato senza cambiare impostazioni:

```sh
xcrun swiftc macos/Runner/WebComponentActivation.swift test/macos_activation/main.swift -o /tmp/cie-activation-tests
/tmp/cie-activation-tests
```

Estensione nuova `CIEPrototypeToken.appex`, identificatore
`it.giancarloezza.CIEID.FlutterPrototype.WebToken`, distinta dall’app pubblicata.
Usa `TKSmartCard` del sistema, con sessione sensibile, senza PC/SC parallelo
e senza accedere al Portachiavi delle cifre PIN. L’host include un canale nativo
limitato a configurazione pubblica, rimozione e prova locale.

Build di sviluppo (runtime completo preparato con `build_native.py`/`build_ltv.py`):

```sh
python3 scripts/build_web_macos.py --runtime /percorso/runtime-macos \
  --output /percorso/nuova-cartella-estensione --identity IDENTITA_APPLE_DEVELOPMENT \
  --team-id TEAM_APPLE_DI_10_CARATTERI
python3 scripts/build_macos.py --runtime /percorso/runtime-macos \
  --identity IDENTITA_APPLE_DEVELOPMENT \
  --web-extension /percorso/nuova-cartella-estensione/CIEPrototypeToken.appex \
  --destination /percorso/nuova-app --build-workspace /percorso/workspace-locale
```

Host ed estensione sono firmati con lo stesso team e dichiarano il gruppo
`TEAM.it.giancarloezza.CIEID.FlutterPrototype.web-public`. Il prefisso del team
permette questo App Group macOS senza provisioning profile separato, secondo
[la documentazione Apple](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
Il gruppo è dedicato ai certificati pubblici del prototipo.

La compilazione non conferma la registrazione. Dopo aver aperto il nuovo host,
controllare `pluginkit -m -p com.apple.ctk-tokens` e la disponibilità della
configurazione al solo host. Se necessaria, la registrazione del bundle di
prova è `pluginkit -a "/percorso/app/Contents/PlugIns/CIEPrototypeToken.appex"`.
Con più build del prototipo registrate, rimuovere le sole registrazioni dei
vecchi bundle di prova e forzare nuovamente la registrazione dell’host attuale
con `lsregister -f` prima di aprirlo. Non disabilitare estensioni ufficiali automaticamente. L’eventuale consenso
Smart Card si concede nella finestra macOS. Non cambiare SIP o altri controlli.
La rimozione di questa registrazione di prova usa `pluginkit -r` sullo stesso
percorso; i dati Web si rimuovono prima dall’app.

## Linux / Firefox

Il runtime Linux include ora un provider PKCS#11 separato, con PIN completo e
motore condiviso. Il collaudo software comprende PKCS#11, NSS in memoria e
archivio pubblico isolato. Il test reale di accesso ai siti con Mozilla Firefox
è stato confermato riuscito dall’utente il 20 ottobre 2026, con i limiti di
osservazione riportati nella documentazione Linux.
La build e l’app non registrano il modulo e non modificano i profili del browser.
Firefox Snap ha una build ABI verificata per core24 e una copia privata del
solo certificato pubblico, separata dalla cache Web/PIN dell’host. L’accesso
al lettore richiede l’autorizzazione Snap manuale; l’app non modifica i permessi.
I test software sono riusciti anche con NSS dello Snap e carta simulata.
Il 20 ottobre 2026 l’utente ha confermato anche il login reale Snap con PIN
completo, dopo la preparazione del DER e l’abilitazione autorizzata di `pcscd`.
[Architettura, durata delle sessioni, limiti e prove](LINUX_FIREFOX.md).

## Windows x64

Minidriver nuovo, API cardmod v7, filesystem virtuale di sola lettura,
contenitore RSA di firma, memoria restituita tramite allocator CSP, ordine
dei byte RSA convertito soltanto al confine cardmod. Le callback di mutazione
PIN/PUK, generazione/importazione chiavi e decifratura sono disabilitate.
La disautenticazione fisica richiede il reset del chiamante; il minidriver non
la dichiara riuscita limitandosi a dimenticare lo stato locale.

Il CPDK **10.1.19041.953** fornisce l’header ufficiale `cardmod.h` v7; il ramo
portabile del vecchio `CardMod.h` del backend e l’header v4 di vecchie toolchain
MinGW non sono adatti. `prepare_cpdk.py` scarica/estrae il kit Microsoft su Linux
con hash fissati, senza eseguire installer. Header e SDK restano in `.build`.
Sono presenti assert sugli offset della tabella callback e sui tipi x64.

```sh
cmake -S native/platform/windows/web -B build-web \
  -DCIE_CARDMOD_INCLUDE=/percorso/cpdk/Include
cmake --build build-web --config Release
```

Il pacchetto privato contiene `cie_prototype_minidriver.dll`, helper di
registrazione, `backend/` privato e `Manage-WebToken.ps1`. L’azione predefinita
**Plan** legge soltanto stato, firma Authenticode e registrazioni corrispondenti.
**Install** richiede PowerShell amministratore, controlla i checksum, prepara
una cartella protetta in Program Files e registra **solo l’ATR esatto della CIE
presente**, con un nome proprio. Si ferma su registrazioni preesistenti senza
sostituirle. Eventuali conflitti richiedono una valutazione separata e un piano
di ripristino. Non è un installer per tutti i modelli CIE.

**Remove** rimuove la sola registrazione del prototipo. Rimuovere prima i dati
Web nella GUI dell’utente. Le build di sviluppo non hanno firma Authenticode
Microsoft: i processi Windows protetti possono rifiutarle. Il pacchetto non
modifica le policy di firma, LSA, driver o antivirus per aggirare questo limite.
La firma e il percorso di certificazione/distribuzione Windows restano aperti.

## Prove

1. Suite software native, Flutter e minidriver isolato prima di ogni attivazione.
   Il minidriver isolato usa una DLL finta nella propria cartella `tests`, senza
   registrazione o accesso alla CIE. `cie_web_store_tests.exe` è una prova esplicita
   su certificato sintetico e namespace credenziali di test: aggiunge/rimuove
   soltanto dati di prova in MY, verifica la preservazione del contesto non
   marcato e non modifica gli archivi CA.
2. Attivazione separata del componente, poi configurazione del certificato nella GUI.
3. Rimuovere/riappoggiare la carta; **Prova componente di sistema** chiede
   conferma, firma una richiesta locale via Security.framework/CryptoTokenKit o
   NCrypt/Smart Card KSP e ne verifica il risultato. Il PIN si inserisce solo
   nella finestra del sistema; niente documenti né rete.
4. Prova manuale di un sito con Entra con CIE e lettore, annotando solo sistema,
   browser, esito e codici tecnici. Non inviare cookie, certificati personali,
   dati dell’account o documenti. Una prova locale riuscita non è un login Web.

La chiusura automatica di test di firma documentale o l’esito positivo di un
test software non autorizzano un tentativo PIN/PUK reale. Linux, Intel macOS
eseguito e browser reali mantengono evidenze distinte.

Firefox può usare i certificati client del sistema tramite
`security.osclientcerts.autoload`; le policy e l’assunzione di supporto RSA-PSS
vanno controllate prima del collaudo, senza alterare globalmente la sicurezza.
Non viene caricato il modulo PKCS#11 legacy con cache disabilitata.

Riferimenti: [Apple CryptoTokenKit](https://developer.apple.com/documentation/cryptotokenkit),
[configurazione token](https://developer.apple.com/documentation/cryptotokenkit/tktokendriver/configuration),
[Microsoft minidriver](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/smart-card-minidriver-overview),
[registrazione](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/minidriver-registration),
[CPDK](https://www.microsoft.com/en-us/download/details.aspx?id=30688),
[policy Firefox](https://mozilla.github.io/policy-templates/).
