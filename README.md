# Firma con CIE

Applicazione desktop indipendente per la firma elettronica tramite Carta d’Identità Elettronica italiana (CIE). L'applicazione è compatibile con i sistemi Windows, macOS e Linux.

Firma con CIE offre un’interfaccia condivisa per usare la CIE con un lettore smart card: abbinare le carte, firmare documenti, verificare firme e accedere ai siti che supportano l’autenticazione CIE. L’interfaccia è realizzata in Flutter/Dart; middleware e SDK di firma sono C/C++, con integrazioni specifiche dei sistemi operativi.

**Questo non è un prodotto ufficiale dell’Istituto Poligrafico e Zecca dello Stato italiano e non è supportato da IPZS.** Il progetto deriva dal lavoro di [CIE ID Universal](https://github.com/gezza-dev/cie-id-macos-universal) e dal middleware originale [italia/cie-middleware-macos](https://github.com/italia/cie-middleware-macos). La nuova applicazione ha identificativi e archivi separati dall’app precedente.

## Stato del progetto

Il progetto è in sviluppo. Questo repository contiene i sorgenti; **non è ancora disponibile una release binaria pubblica di Firma con CIE**. È predisposto un [installer Windows x64 locale di test](docs/WINDOWS_INSTALLER.md), che include app e componente Web e conserva i dati personali. Le release di CIE ID Universal appartengono a un progetto distinto.

Quando saranno pubblicati, i pacchetti saranno disponibili nella pagina
[Release di Firma con CIE](https://github.com/gezza-dev/firma-con-cie/releases).
Il collegamento all’[ultima release stabile](https://github.com/gezza-dev/firma-con-cie/releases/latest)
non fissa un numero di versione; finché non esiste una release accessibile,
non offre un pacchetto da scaricare.

| Sistema | Stato verificato |
| --- | --- |
| macOS | Bundle Universal Apple Silicon/Intel compilato. Firma PDF/P7M, abbinamento, PIN parziale e accesso Safari con CIE reale verificati su Apple Silicon. L’utente ha confermato anche l’accesso riuscito con Google Chrome e Mozilla Firefox. L’esecuzione su Intel resta da collaudare. |
| Windows x64 | Interfaccia e componenti nativi compilati e verificati. Firma PDF/P7M, abbinamento persistente e PIN parziale collaudati. Accesso al portale CIE con Chrome e Firefox verificato con CIE reale e PIN completo; collaudo riuscito anche con Microsoft Edge confermato dall'utente. |
| Windows ARM64 | [Workflow GitHub Actions](docs/WINDOWS_ARM64.md) predisposto per app, middleware, componente Web e installer. Prima esecuzione completa e collaudo reale da effettuare. |
| Linux | Backend e interfaccia compilati e testati. Abbinamento persistente e firma PDF/P7M con PIN parziale verificati con CIE reale. Test reali di accesso ai siti con Mozilla Firefox, Firefox Snap e Chrome desktop con PIN completo confermati riusciti dall’utente. Pacchetto `.deb` con launcher e icone; collaudo desktop completo da completare. |

La [tabella dei browser collaudati](docs/WEB_AUTHENTICATION.md#browser-collaudati)
riepiloga gli esiti per piattaforma: Chrome e Firefox su tutti e tre i sistemi,
Edge su Windows e Safari su macOS. Edge su macOS e Linux resta da collaudare;
su Linux occorre anche completarne l’integrazione nella configurazione guidata.

Il nuovo archivio su file richiede di abbinare nuovamente le CIE con il PIN completo; non importa i precedenti abbinamenti. Le prove reali macOS/Windows riportate nella tabella riguardano il precedente archivio. Su Linux la nuova cache è stata collaudata anche con abbinamento persistente e firme PDF/P7M con PIN parziale.

Per [Chrome desktop su Linux](docs/LINUX_CHROME.md) è predisposta la registrazione
NSS esplicita del provider già usato da Firefox, con test software isolati e PIN
completo. Il login reale Chrome Linux è stato confermato riuscito dall'utente
il 23 ottobre 2026; Chromium Snap/Flatpak
non sono inclusi in questa integrazione. Nessun browser viene configurato
dall'installer o durante la compilazione.

Cambio PIN e Sblocco Carta sono implementati con test software: le prove reali su macOS e Windows restano da completare. La validazione DSS/LTA con JVM privata è predisposta per macOS, Windows e Linux; [supporto ARM64](docs/LINUX_ARM64.md).

[Stato delle verifiche e limiti](docs/STATUS.md) · [Compilazione](docs/BUILDING.md) · [Licenze](docs/LICENSING.md)

L'[adattamento della finestra all'area utile](docs/DESKTOP_WINDOW_SIZING.md)
è implementato nei tre runner senza doppio scaling. I test manuali GNOME e
Windows sono riusciti; su Windows il renderer Skia risolve il blocco della
presentazione durante il trascinamento dei bordi osservato con Impeller.
La build e il collaudo delle nuove modifiche macOS restano da completare.

## Funzionalità

- **Home e carte abbinate:** rilevamento automatico di lettore e CIE, gestione di più carte, miniatura, nome dell’intestatario e numero della carta.
- **Firma Elettronica:** procedura guidata per PAdES/PDF e CAdES/P7M; firma con CIE abbinata o non abbinata; cofirma P7M; verifica del documento prodotto prima del salvataggio.
- **Firma grafica PDF:** anteprima locale, scelta di pagina e posizione, immagine personalizzata o firma testuale. Nome e Cognome sono letti dal certificato della CIE; data e ora riportano il fuso locale. I pulsanti di conferma restano visibili mentre l’anteprima scorre.
- **Verifica Firma:** analisi di PDF e P7M anche senza CIE, risultati distinti per integrità, certificato, fiducia, revoca, marche temporali e validità storica; estrazione del contenuto incorporato nei P7M.
- **Abbinamento locale:** PIN parziale per firmare con carte abbinate; prefisso e dati verificati sono custoditi dal componente nativo in una cache cifrata per utente, condivisa fra macOS, Windows e Linux. [Formato, protezione e limiti](docs/PAIRING.md).
- **Accesso ai siti:** preparazione del certificato pubblico durante l’abbinamento; estensione CryptoTokenKit su macOS, componente smart card CSP/KSP su Windows e [provider PKCS#11 Linux per Firefox, Firefox Snap e Chrome desktop](docs/LINUX_FIREFOX.md). Nel browser si usa il PIN completo di otto cifre, anche per carte abbinate. La [procedura guidata Firefox](docs/LINUX_FIREFOX_SETUP.md) registra il modulo nel solo profilo scelto, dopo conferma; il permesso Snap richiede un'autorizzazione separata. L'installer non configura i browser.
- **Cambio PIN e Sblocco Carta:** flussi dedicati con PIN completo o PUK, conferma esplicita e nessun tentativo automatico; stato del collaudo reale indicato sopra.
- **Guida e Assistenza:** guida inclusa e consultabile offline, collegamenti esterni nel browser predefinito, FAQ e contatti ufficiali per la CIE.
- **Impostazioni:** schede Generali, Proxy e Log; preferenze persistenti, proxy HTTP/HTTPS e diagnostica facoltativa con esportazione senza credenziali o dati dei documenti.
- **Italiano e inglese:** selezione automatica dalla lingua del sistema, con inglese per lingue diverse o indeterminate; scelta manuale disponibile.
- **Tema:** chiaro, scuro o Segui il sistema. I set di icone sono inclusi per i tre sistemi; su Windows l’icona dell’eseguibile/Explorer resta statica.

Le verifiche attuali, le marche temporali e la validità storica hanno esiti separati: prove mancanti o insufficienti producono uno stato **indeterminato**. Il progetto non attesta la qualificazione giuridica della firma e non sincronizza le Trusted List europee.

## Uso dell’app compilata

I pacchetti pubblicati sono disponibili nella pagina [Release](https://github.com/gezza-dev/firma-con-cie/releases); [ultima release stabile](https://github.com/gezza-dev/firma-con-cie/releases/latest). Finché il repository è privato o non sono state pubblicate release accessibili, questi collegamenti non offrono un download pubblico e la ricerca aggiornamenti nell’app segnala indisponibilità.

Per firma, abbinamento e accesso ai siti servono una CIE, il relativo PIN e un lettore compatibile con il sistema. La sola verifica di documenti non richiede carta o lettore.

1. Avvia **Firma con CIE**, collega il lettore e appoggia la carta: il riconoscimento è automatico.
2. Nella Home usa **Abbina CIE**. L’abbinamento prepara anche il certificato per l’accesso ai siti. Su Windows il componente viene installato con l'app dal pacchetto di installazione: UAC è richiesto dall'installer, mentre l'abbinamento esegue soltanto un controllo senza privilegi amministrativi.
3. In **Firma Elettronica** scegli la CIE, il documento, il formato e l’eventuale segno grafico; inserisci il PIN solo nel campo protetto e scegli dove salvare il risultato. È possibile firmare anche senza abbinare la carta.
4. In **Verifica Firma** seleziona o trascina un PDF/P7M. I dettagli spiegano separatamente gli esiti dei diversi controlli.
5. Per un sito Web apri il browser e scegli l’accesso con lettore/CIE. Il sistema presenta il certificato e richiede il PIN completo nella propria finestra protetta. Dopo la configurazione non occorre tenere aperta l’interfaccia dell’app.

Per le build di sviluppo, prima di usare il browser verificare che il componente di sistema corretto sia attivo. [Integrazione Web](docs/WEB_AUTHENTICATION.md) · [Primo utilizzo Windows](docs/WINDOWS_WEB_FIRST_USE.md).

## Compilazione dai sorgenti

La compilazione completa comprende **interfaccia, backend e componenti di sistema**. Il solo comando `flutter build` non genera il middleware, le JVM private o il componente di autenticazione Web.

```sh
git clone https://github.com/gezza-dev/firma-con-cie.git
cd firma-con-cie
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Usare Flutter **3.47.7** / Dart **3.13.5**, fissati in [toolchain.lock.json](toolchain.lock.json). Il repository privato richiede un account autorizzato per il clone.

Le istruzioni complete, con prerequisiti e comandi per ciascun sistema, sono in **[docs/BUILDING.md](docs/BUILDING.md)**. Le versioni native sono fissate nei lockfile; non usare DLL o librerie di architettura diversa e non aggiornare le dipendenze implicitamente durante una ricompilazione.

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `lib/`, `test/` | Interfaccia, flussi condivisi, localizzazione e test Flutter |
| `native/include/`, `native/src/` | ABI C, adattatori, PC/SC, abbinamento e gestione documenti |
| `native/backend/` | Middleware e SDK importati e adattati, con provenienza e licenze originali |
| `native/platform/` | CryptoTokenKit macOS e componente smart card Windows |
| `native/ltv/`, `native/preview/` | Worker DSS, lock delle JVM e anteprima PDF |
| `macos/`, `windows/`, `linux/` | Runner e risorse delle piattaforme |
| `scripts/` | Compilazione, preparazione dei componenti e controllo dei sorgenti da caricare |
| `LICENSES/`, `NOTICE.md` | Testi di licenza e attribuzioni |
| `docs/` | Compilazione, architettura, verifiche e limiti |

Gli identificativi tecnici storici contenenti `FlutterPrototype` sono conservati per mantenere la compatibilità con abbinamenti, archivi protetti e App Group esistenti. Non sono il nome pubblico dell’app.

## Licenze e distribuzione

Pacchetti Linux per x86_64: `.deb` verificato su Ubuntu 24.04
LTS/Debian 13, `.rpm` per Fedora 44 e `.pkg.tar.zst` per Arch rolling.
[Ricette, verifiche software e limiti](docs/LINUX_DISTRIBUTION_PACKAGES.md).
È disponibile anche una ricetta [`.deb` ARM64](docs/LINUX_ARM64.md),
con compilazione e verifiche in emulazione; il collaudo su hardware ARM64 reale
resta da eseguire. Le prove reali Linux descritte sopra riguardano x86_64.

La distribuzione portabile Linux comprende un [AppImage x86_64](docs/LINUX_APPIMAGE.md),
compilato su Ubuntu 22.04, con PC/SC del sistema e modulo browser persistente
nella home. Collaudati dall'utente interfaccia, abbinamento da zero e persistente,
firme PDF/P7M con PIN parziale e accesso Firefox/Chrome con PIN completo.
È predisposto anche l’[AppImage ARM64/AArch64](docs/LINUX_APPIMAGE.md), con
base Ubuntu 22.04 e verifiche software in emulazione. Il collaudo su hardware
ARM64 con desktop, lettore, carta e browser reali resta da eseguire.
Restano da completare i collaudi su altri desktop reali e i materiali di release.
La distribuzione Linux mantiene AppImage e pacchetti nativi `.deb`, `.rpm`
e Arch, con le rispettive procedure di configurazione dei browser.

La licenza principale è **BSD-3-Clause**, con copyright e avvisi originali conservati. Il progetto include anche componenti con altre licenze: **non tutto il repository né il prodotto completo sono esclusivamente BSD**.

Consultare [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), [matrice delle licenze e condizioni di distribuzione](docs/LICENSING.md) e [avvisi del backend](native/backend/THIRD_PARTY_NOTICES.md). I futuri pacchetti binari richiedono anche materiali sorgente corrispondenti, avvisi completi e procedure di ricompilazione per i componenti che li richiedono.

Il caricamento dei sorgenti e la pubblicazione di una release binaria sono passaggi distinti. [Preparazione del repository](docs/REPOSITORY.md).

## Documentazione e assistenza

- [Guida ufficiale al software CIE](https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/)
- [Domande frequenti ufficiali](https://www.cartaidentita.interno.gov.it/Assistenza/#FAQ)
- [Segnalazioni relative a questo progetto](https://github.com/gezza-dev/firma-con-cie/issues)

Non includere PIN, PUK, documenti personali, certificati della propria CIE o credenziali nei report e nelle segnalazioni. I servizi di assistenza ufficiali riguardano la CIE e i prodotti ufficiali, non il supporto di questa applicazione indipendente.
