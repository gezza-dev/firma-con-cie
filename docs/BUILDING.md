# Compilare Firma con CIE

Per il pacchetto completo **Windows ARM64** tramite GitHub Actions, senza
installare l'ambiente di sviluppo nella VM, vedere [WINDOWS_ARM64.md](WINDOWS_ARM64.md).
La pipeline è predisposta; esecuzione completa e collaudo hardware ARM64 restano
da effettuare.

L'adattamento delle finestre macOS/Windows usa il modulo C in
`native/desktop`, da conservare insieme agli altri sorgenti. Test eseguibili
su Linux, collegamento al runner Swift e limiti della compilazione incrociata
sono in [DESKTOP_WINDOW_SIZING.md](DESKTOP_WINDOW_SIZING.md).

I comandi partono dalla radice del repository. Usare cartelle di output nuove per conservare le build precedenti. Il repository contiene sorgenti, asset e licenze, non runtime compilati né credenziali. Per lo stato effettivamente collaudato vedere [STATUS.md](STATUS.md).

## Toolchain e dipendenze

| Componente | Riferimento |
| --- | --- |
| Flutter 3.47.7 / Dart 3.13.5 | `toolchain.lock.json`, commit Flutter `abaf9c523780a608bd46686fd5e53740a07077f8` |
| Pacchetti Dart | `pubspec.lock`; usare `pub get --enforce-lockfile` |
| Python | 3.10+ consigliato; i comandi qui usano Python a 64 bit |
| C/C++ | C++17, CMake 3.23+, Ninja, make, Perl, pkg-config, autoconf/automake/libtool, Meson 1.11.0 |
| Dipendenze native | URL/versioni/SHA-256 in `native/backend/scripts/dependencies.lock.json` |
| Anteprima PDF | `native/preview/pdfium.lock.json`, avvisi in `LICENSES/preview` |
| DSS/JVM | Java 21, Maven 3.9.16; lock in `native/ltv/` |

Per ottenere Flutter da una copia separata del repository ufficiale:

```sh
git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git /percorso/flutter
git -C /percorso/flutter rev-parse HEAD
```

Confrontare il commit con il lock e aggiungere `bin` al PATH della propria sessione. Non aggiornare Flutter o le dipendenze durante una build riproducibile. Su Windows usare i corrispondenti percorsi e `flutter.bat`.

```sh
flutter --version
flutter pub get --enforce-lockfile
python3 scripts/generate_l10n.py
flutter analyze --no-pub
flutter test --no-pub
```

Questi test usano servizi simulati. Tre test del backend documentale sono opt-in: vedere la sezione Test. La UI può compilare senza runtime, ma firma, lettura CIE e verifica nativa richiedono le librerie descritte sotto.

## Dopo lo spostamento dei sorgenti

I comandi di questa guida vanno eseguiti dalla radice del checkout corrente;
gli script del repository ricavano i percorsi dalla propria posizione.
Conservare i percorsi effettivi della macchina soltanto nelle configurazioni
locali ignorate o in `LOCAL_SETUP.md`, senza inserirli negli esempi condivisi.

Dopo una rinomina, eseguire `flutter clean` e
`flutter pub get --enforce-lockfile`, quindi rigenerare le directory CMake
con percorsi assoluti obsoleti. Non riutilizzare le cache `CMakeCache.txt`
del vecchio percorso: scegliere un nuovo `--build-dir` per
`scripts/build_native.py` oppure ricreare la relativa directory generata.
Anche i file `.pc`, `.cmake`, `.la` e gli script `*-config` delle dipendenze
locali possono contenere il vecchio prefisso: verificarli e aggiornare il
solo prefisso locale, oppure ricompilare le dipendenze. Gli ambienti Python
virtuali contengono percorsi assoluti e richiedono anch’essi una verifica
dopo lo spostamento.

La rinomina della cartella dei sorgenti non cambia il percorso di
installazione `/opt/firma-con-cie`, gli identificativi tecnici, i dati
utente o la configurazione dei browser. I percorsi nei report e nei
pacchetti già prodotti documentano la build originale e restano storici.

## Processo di rilevamento della carta

Il rilevamento pubblico usa il programma privato `cie_card_observer` (`.exe`
su Windows), prodotto da `scripts/build_native.py` con la stessa toolchain del
backend. Va distribuito accanto al bridge; non è un servizio di sistema.
Il processo conserva lo stato di osservazione fra i sondaggi, viene interrotto
dopo cinque secondi senza risposta e viene arrestato quando il monitor è sospeso
o l’app si chiude. Dopo un timeout i sondaggi automatici osservano una pausa di
otto secondi. La perdita del primo piano e la minimizzazione della finestra
non sospendono il rilevamento; lo sospendono operazioni, dialoghi, sospensione
del sistema e chiusura. Non esiste un ripiego PC/SC nell’isolate della GUI.
Il protocollo ammette soltanto `observe` e `detect`: nessun PIN, documento,
abbinamento o operazione privata attraversa questo processo. Il supervisor
termina anche alla chiusura del canale del genitore, pur con PC/SC bloccato.

`flutter test test/card_observation_process_test.dart` compila ed esegue un
worker sintetico con il Dart SDK della toolchain. Verifica timeout, chiusura,
crash, output malformato/eccessivo e assenza di processi residui senza lettore.
CTest verifica anche il supervisor C++ reale con un bridge simulato bloccato.
Ricompilare il runtime prima di ricostruire o confezionare l’app: i controlli
di packaging rifiutano un runtime privo del nuovo eseguibile.

## macOS Universal

Servono Xcode completo con supporto ai cataloghi `.icon` (Xcode 26 o successivo), SDK macOS, CMake/Ninja e gli strumenti della tabella. Il deployment target dell’app e del backend è macOS 12.0. Il toolchain di compilazione può richiedere un macOS più recente.

Per una release compilare anche le dipendenze da una copia sorgente in un
percorso neutro, fuori dal profilo personale. Per esempio, da un checkout pulito:

```sh
CIE_RELEASE_SOURCE="$(mktemp -d /private/tmp/firma-con-cie-source-XXXXXX)"
git archive HEAD | tar -x -C "$CIE_RELEASE_SOURCE"
cd "$CIE_RELEASE_SOURCE"
```

I compilatori C/C++ mappano i percorsi sorgente, build e dipendenze a nomi
generici per macro e simboli. Questo non riscrive stringhe di configurazione
generate dalle dipendenze: perciò anche i prefissi statici devono essere
ricostruiti nella copia neutra, evitando il riuso di librerie contenenti vecchi
percorsi personali. Le versioni e gli hash dei sorgenti restano fissati.

Preparare Meson in un ambiente isolato e compilare le dipendenze nelle due architetture:

```sh
python3 -m venv .build/tools
.build/tools/bin/pip install meson==1.11.0
export PATH="$PWD/.build/tools/bin:$PATH"
python3 scripts/build_portable_dependencies.py --arch arm64
python3 scripts/build_portable_dependencies.py --arch x86_64
python3 scripts/merge_macos_dependencies.py \
  --arm64 .build/dependencies/macos-arm64/prefix \
  --x86-64 .build/dependencies/macos-x86_64/prefix \
  --output .build/dependencies/macos-universal/prefix
python3 scripts/build_native.py --system macos \
  --dependency-prefix .build/dependencies/macos-universal/prefix \
  --architectures 'arm64;x86_64' --output native/runtime/macos-base
python3 scripts/smoke_native.py --runtime native/runtime/macos-base \
  --report reports/macos-native.json
```

La fusione rifiuta header diversi o archivi di architettura inattesa. Se fallisce, riesaminare le configurazioni generate delle dipendenze prima di procedere; non aggirare il controllo copiando header arbitrari. Un prefisso ARM64 non diventa Universal con il solo flag CMake.

Per includere DSS/LTA, completare ora il runtime secondo la sezione DSS/JVM. Nei comandi seguenti `native/runtime/macos-complete` deve essere la destinazione prodotta da `build_ltv.py`; per una build senza DSS usare invece `macos-base`.

Per CryptoTokenKit servono un’identità di firma Apple disponibile nel Portachiavi e il relativo Team ID. Le chiavi private e gli eventuali profili restano fuori dal repository. Usare variabili della sessione con i propri valori:

```sh
export CIE_SIGNING_IDENTITY='Apple Development: propria identità'
export CIE_TEAM_ID='PROPRIO_TEAM_ID'
python3 scripts/build_web_macos.py \
  --runtime native/runtime/macos-complete \
  --output .build/web-macos \
  --identity "$CIE_SIGNING_IDENTITY" --team-id "$CIE_TEAM_ID"
python3 scripts/build_macos.py \
  --runtime native/runtime/macos-complete \
  --identity "$CIE_SIGNING_IDENTITY" \
  --web-extension .build/web-macos/CIEPrototypeToken.appex
```

Le destinazioni predefinite locali sono `~/Developer/Builds/firma-con-cie/firma-con-cie` per il bundle e `~/Developer/Builds/firma-con-cie/workspace-macos` per i file generati di sviluppo. Le impostazioni locali possono cambiarle senza entrare nei sorgenti pubblicati.

Per firmare con **Developer ID Application**, impostare `CIE_SIGNING_IDENTITY`
al nome completo o all'impronta del proprio certificato e aggiungere
`--developer-id` sia a `build_web_macos.py` sia a `build_macos.py`.
Questa modalità richiede il certificato corrispondente nel Portachiavi, applica
Hardened Runtime e timestamp sicuri a tutto il codice incorporato e assegna
il permesso JIT soltanto ai launcher Java privati. Non cambia gli identificativi
dell'app o l'archivio delle CIE. Per il DMG usare la stessa identità e aggiungere
`--developer-id` a `package_macos_dmg.py`: anche il contenitore riceve un
timestamp sicuro. La firma Developer ID non esegue la notarizzazione.

Senza un `--build-workspace` esplicito, la GUI Developer ID viene compilata in
una nuova cartella privata `/private/tmp/firma-con-cie-macos-*`: Flutter conserva
l'URI del registrante generato nel codice AOT e la sola mappatura C/C++ non lo
rimuoverebbe. Il bundle finale rimane nella destinazione locale scelta.
Un controllo sui file rifiuta il percorso del profilo locale prima della firma
finale; non modifica nome dell'autore, identità Developer ID o identificativi
dell'app. Il controllo completa, senza sostituirla, l'ispezione dell'intero
payload prima della pubblicazione.

### Notarizzazione per la distribuzione

Prima del rilascio aggiungere tutti gli avvisi al bundle e completare la firma.
Preparare uno ZIP con `ditto -c -k --keepParent`, poi inviarlo con
`xcrun notarytool submit --keychain-profile "$CIE_NOTARY_PROFILE" --wait`.
`CIE_NOTARY_PROFILE` è il nome del proprio profilo locale nel Portachiavi:
credenziali, nomi effettivi dei profili e ricevute locali restano fuori da Git.

Attendere lo stato **Accepted**, applicare il ticket all'app con
`xcrun stapler staple` e verificarlo con `xcrun stapler validate`.
Confezionare quindi il DMG con `package_macos_dmg.py --developer-id`, inviare
anche il DMG a `notarytool`, attendere Accepted e applicare/verificare il suo
ticket. La verifica finale comprende montaggio in sola lettura, copia dell'app,
validazione del ticket della copia e `spctl --assess --type execute`.
Per il contenitore usare `spctl --assess --type open --context context:primary-signature`.
Il checksum definitivo del DMG si calcola **dopo** l'applicazione del ticket.

Non modificare né rifirmare i pacchetti dopo la verifica finale. Una variazione
successiva richiede di ripetere le fasi interessate; una firma valida da sola
non sostituisce l'accettazione del servizio di notarizzazione.

Per scegliere una destinazione propria, copiare l’esempio e modificare **solo** il file locale:

```sh
cp local-build.example.json local-build.json
```

`local-build.json` richiede la chiave `build_root`, con un percorso assoluto oppure iniziante con `~/`. Gli script lo leggono dalla cartella del progetto, indipendentemente dalla directory da cui sono avviati. Il file è ignorato da Git, escluso dalla copia di compilazione e rifiutato dal controllo degli snapshot da pubblicare. L’esempio versionato contiene solo un percorso generico; non inserirvi le proprie impostazioni. I parametri espliciti `--destination`, `--build-workspace`, `--app` e `--output` prevalgono sulla configurazione locale. Senza configurazione locale si usano i valori generici indicati sopra.

La chiave locale facoltativa `macos_output` permette di salvare app e DMG nella stessa cartella: un percorso relativo è risolto sotto `build_root`, mentre un percorso assoluto è usato direttamente. Il workspace resta separato sotto `build_root/workspace-macos`. Il nome scelto da ciascuno sviluppatore rimane nel proprio `local-build.json`; l’esempio versionato usa un nome generico. Omettendo questa chiave resta valida la disposizione predefinita precedente.

Il workspace non contiene gli archivi personali dell’app. L’estensione firmata può essere conservata fuori dai sorgenti e passata esplicitamente con `--web-extension`; i percorsi effettivi e i comandi personali possono essere annotati in `LOCAL_SETUP.md`, anch’esso escluso da Git. La copia dell’estensione deve conservare i permessi di esecuzione (per esempio con `ditto`): la sola verifica della firma digitale non rileva la perdita di tali permessi. La compilazione e il confezionamento del DMG controllano anche che i programmi necessari siano eseguibili.

Il bundle risultante è `Firma con CIE.app`, con librerie private, avvisi e CTK. La copia di compilazione deve essere fuori dalla cartella dei sorgenti. Lo script non registra o attiva l’estensione e non esegue prove sulla carta. Se si cambiano bundle identifier o App Group occorre allineare host, estensione e archivi; gli identificativi storici sono intenzionalmente conservati.

Senza CryptoTokenKit si possono omettere `build_web_macos.py` e `--web-extension`, usando la firma ad hoc predefinita per le sole prove locali. Tale bundle non offre automaticamente l’accesso Web. Apple Development non è notarizzazione: distribuzione Developer ID e notarizzazione sono passaggi separati.

### DMG firmato per le prove

Per confezionare il bundle Universal già firmato, completo di middleware,
observer e CryptoTokenKit:

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/python -m pip install ds_store==1.3.1
.build/dmg-tools/bin/python scripts/package_macos_dmg.py \
  --identity "$CIE_SIGNING_IDENTITY" \
  --report reports/macos-development-dmg.json
```

Il comando usa l’app e la cartella DMG risolte dalla configurazione locale. Con `macos_output` app e DMG sono nella stessa cartella; senza questa chiave il bundle resta sotto `build_root/firma-con-cie` e il DMG sotto `build_root`. Il nome del DMG, per esempio `firma-con-cie_1.0.0_universal.dmg`, usa la versione letta dal bundle firmato. È possibile indicare un’altra app o destinazione con `--app` e `--output`.

Il volume **Firma con CIE** contiene soltanto l’app e il collegamento
**Applicazioni**; la finestra Finder usa una disposizione a due icone con
dimensione 640×420. Per installare, trascinare l’app su Applicazioni.
La posizione iniziale è vicina all’angolo superiore sinistro e viene adattata
ai limiti dello schermo da Finder. Non dipende dalla risoluzione o dalla
posizione di Dock e barra dei menu del Mac di compilazione. La ricetta salva
`WindowBounds={{100, 100000}, {640, 420}}`: la coordinata verticale alta
lascia a Finder l’adattamento al bordo superiore del display di apertura.
La posizione effettiva resta sotto il controllo di Finder.
La ricetta verifica firma e architetture del bundle, integrità dell’immagine,
contenuto montato e copia estratta, senza modificare l’app originale o gli
abbinamenti. Rifiuta di sovrascrivere un DMG esistente. La firma del DMG usa
l’identità indicata; il pacchetto di prova Apple Development non viene
notarizzato né pubblicato automaticamente.

## Windows x64

Il backend completo usa MinGW-w64 POSIX x64; il runner Flutter e il provider smart card sono compilati con Visual Studio/MSVC x64. I due mondi comunicano tramite ABI C: non collegare direttamente oggetti C++ MinGW a oggetti MSVC.

### Backend: compilazione incrociata su Linux

In un host Linux con gli strumenti nativi della tabella:

```sh
sudo apt-get install g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix
python3 scripts/build_portable_dependencies.py --target windows-x64 --arch x86_64
python3 scripts/build_native.py --system windows \
  --toolchain .build/dependencies/windows-x64/mingw.cmake \
  --dependency-prefix .build/dependencies/windows-x64/prefix \
  --output native/runtime/windows-base
```

Trasferire la cartella completa, manifest e avvisi compresi, sul PC Windows. I test cross-compilati devono essere eseguiti su Windows: la compilazione su Linux non equivale a un collaudo del runtime.

### Interfaccia e componente smart card sul PC

Servono Visual Studio 2022 con sviluppo desktop C++, Windows SDK, Flutter e Python x64. Il provider richiede il **CPDK Microsoft ufficiale con cardmod.h v7**; gli header Microsoft non sono inclusi nel repository. `prepare_cpdk.py` è una ricetta di estrazione su Linux con 7z/msitools, non un installer Windows; in alternativa preparare il CPDK ufficiale sul PC secondo i suoi termini.

Collocare il runtime completo in `native/runtime/windows`. Se si desidera DSS/LTA, completare prima la cartella secondo la sezione DSS/JVM. Da un terminale con gli strumenti Visual Studio disponibili:

```powershell
py -3 scripts/smoke_native.py --runtime native/runtime/windows --report reports/windows-native.json
cmake -S native/platform/windows/web -B .build/web-windows -A x64 "-DCIE_CARDMOD_INCLUDE=C:/percorso/CPDK/Include"
cmake --build .build/web-windows --config Release
ctest --test-dir .build/web-windows -C Release --output-on-failure
py -3 scripts/package_web_windows.py --runtime native/runtime/windows --provider .build/web-windows/Release/cie_prototype_minidriver.dll --output native/runtime/windows-web-component
$ciePayloadHeader = (Resolve-Path native/runtime/windows-web-component/setup_payload.h).Path
cmake -S native/platform/windows/web -B .build/web-windows -A x64 "-DCIE_CARDMOD_INCLUDE=C:/percorso/CPDK/Include" "-DCIE_WEB_SETUP_MANIFEST=$ciePayloadHeader"
cmake --build .build/web-windows --config Release --target cie_web_setup
Copy-Item .build/web-windows/Release/CIE-Web-Setup.exe native/runtime/windows-web-component/
py -3 scripts/test_windows_web_helper.py --helper native/runtime/windows-web-component/CIE-Web-Setup.exe
flutter pub get --enforce-lockfile
flutter build windows --release
```

L’output è `build/windows/x64/runner/Release/Firma con CIE.exe`. Distribuire l’intera cartella Release, che contiene `cie_native`, risorse Flutter, PDFium e payload Web. Il solo `.exe` non basta. I comandi di compilazione non devono registrare driver né autenticare la carta. L’installazione del componente e l’autorizzazione UAC spettano al pacchetto di installazione; l’app ne controlla lo stato in sola lettura e, se occorre intervenire, mostra le istruzioni per eseguire il pacchetto. [Installer e collaudi Windows](WINDOWS_INSTALLER.md) · [Flusso iniziale e storia dei collaudi](WINDOWS_WEB_FIRST_USE.md).

Questa ricetta non firma Authenticode il prodotto. L’esecuzione in processi protetti e una distribuzione Windows richiedono verifiche e firma distinte.

## Linux

La ricetta di sviluppo di riferimento usa Ubuntu 24.04. Su Ubuntu 26.10 x86_64 sono stati collaudati abbinamento persistente e firme PDF/P7M con PIN parziale; l’utente ha confermato anche un test reale di accesso ai siti con Mozilla Firefox. Il collaudo completo di tutte le funzioni resta da completare: vedere [STATUS.md](STATUS.md).

```sh
sudo apt-get update
sudo apt-get install build-essential cmake ninja-build pkg-config \
  libpcsclite-dev pcscd libccid libgtk-3-dev liblzma-dev libssl-dev \
  python3-venv perl autoconf automake libtool gettext
python3 -m venv .build/tools
.build/tools/bin/pip install meson==1.11.0
export PATH="$PWD/.build/tools/bin:$PATH"
python3 scripts/build_portable_dependencies.py
python3 scripts/build_native.py --system linux \
  --dependency-prefix "$PWD/.build/dependencies/linux-$(uname -m)/prefix"
python3 scripts/smoke_native.py --runtime native/runtime/linux --report reports/linux-native.json
flutter pub get --enforce-lockfile
flutter build linux --release
```

Conservare l’intera directory `build/linux/<architettura>/release/bundle`. Il runner copia le librerie private in `cie_native`; pcsc-lite e driver compatibili devono essere disponibili sul sistema destinatario. La cache cifrata degli abbinamenti è condivisa e ha test software e prove reali Linux. Il provider di accesso Firefox PKCS#11 è incluso; il test reale di accesso è stato confermato riuscito dall’utente. La build non registra il modulo nel browser: la configurazione è un’azione esplicita dell’utente, disponibile anche tramite il nuovo wizard. Vedere [LINUX_FIREFOX.md](LINUX_FIREFOX.md). Il runtime opzionale DSS/LTA Linux x86_64 è assemblato secondo [LINUX_DSS_LTA.md](LINUX_DSS_LTA.md), con JVM privata e test senza CIE. Per il solo bridge Linux serve OpenSSL 3 (`libssl-dev`); la build completa usa la copia privata del prefisso quando specificato.

### Compatibilità Firefox Snap

Il runtime Linux incorpora anche helper Python e guardia PC/SC per la
[configurazione guidata di Firefox](LINUX_FIREFOX_SETUP.md). CTest esercita
profili e cartelle Snap temporanei. L'app usa l'helper in sola lettura per
decidere se mostrare il riquadro nella Home; registrazione e permesso richiedono
conferme separate nella procedura aperta dall'utente.
Il nuovo `.deb` dipende anche da Python 3 e `libnss3-tools`.

Per Chrome desktop lo stesso provider usa NSS; **Configura Chrome** nell’app
propone riepilogo e conferma prima della registrazione. L’helper usa un
NSS temporaneo con PC/SC bloccato e conserva i database certificati/chiavi.
La registrazione rimane esplicita e separata da build/installer. I test `linux_chrome_nss` e
`linux_chrome_setup_policy` non aprono il browser e non accedono alla CIE.
[Procedura, test SQL isolati e limiti](LINUX_CHROME.md).

La ricetta Linux disabilita il rilevamento curl di `memset_explicit` per usare
il suo fallback non eliminabile `explicit_bzero`. Dopo la compilazione nativa,
`check_linux_firefox_abi.py` verifica il provider e le due librerie CIE richieste
rispetto a core24 (glibc 2.39, GLIBCXX 3.4.33, CXXABI 1.3.15). Il controllo
non modifica i binari: una dipendenza troppo recente richiede una toolchain
Ubuntu 24.04/core24 compatibile. Non includere una glibc privata nel bundle.

La copia del certificato pubblico per Snap viene preparata dall’app al
completamento della configurazione Web; PIN e chiavi della cache non vengono
pubblicati. Build e test non registrano il modulo, non avviano Firefox e non
collegano l’interfaccia `pcscd`. I comandi del collaudo NSS nel confinamento
Snap, con carta simulata o PC/SC bloccato, sono in [LINUX_FIREFOX.md](LINUX_FIREFOX.md).

Nel collaudo manuale separato del 20 ottobre 2026, dopo la preparazione del
certificato pubblico e l’abilitazione autorizzata di `firefox:pcscd`, l’utente
ha confermato l’accesso riuscito con Firefox Snap e PIN completo.

### Pacchetto .deb

Per assemblare un `.deb` locale da un bundle release completo e collaudare
installazione, aggiornamento e rimozione senza installarlo sull'host:

```sh
python3 scripts/package_linux_deb.py \
  --bundle build/linux/x64/release/bundle \
  --output dist/linux-deb \
  --version '1.0.0'
python3 scripts/test_linux_deb.py \
  'dist/linux-deb/firma-con-cie_1.0.0_amd64.deb' \
  --report reports/linux-deb-validation.json
```

Servono `dpkg-dev`, `binutils` e `desktop-file-utils`; il verificatore usa anche
GTK, `gresource`, `ldd` e la simulazione APT. Il database dpkg di prova è
separato, senza script di manutenzione o avvio dell'app. Il percorso privato
installato è `/opt/firma-con-cie`, con launcher e icone in `/usr/share`.
[Installazione, limiti e modulo Firefox Snap](LINUX_PACKAGE.md).

### Pacchetti Fedora e Arch e compatibilità Debian

Il contenuto comune dei pacchetti è preparato da `linux_package_common.py`.
`package_linux_distribution.py --format rpm` usa `rpmbuild` in Fedora;
`--format arch` usa `makepkg` come utente ordinario in Arch. Il `.deb` continua
a usare lo stesso comando sopra e `dpkg-shlibdeps`. Il controllo delle
dipendenze include esplicitamente EGL/OpenGL/GLES, caricati dinamicamente
all'avvio. I pacchetti usano la versione di release e non configurano browser.
[Versioni verificate, ricette, isolamento e limiti](LINUX_DISTRIBUTION_PACKAGES.md).

### Pacchetto Debian ARM64

Il target `arm64` richiede GUI, runtime nativo, PDFium e JVM AArch64;
worker e dipendenze Java possono essere riutilizzati dopo confronto degli hash.
`build_ltv.py --architecture arm64` verifica l'architettura del runtime base;
il confezionamento e i test `.deb` selezionano la JVM ARM64 separatamente.
La compilazione e il collaudo possono usare un ambiente emulato privato.
[Procedura ARM64, provenienza e limiti](LINUX_ARM64.md).

### AppImage x86_64 e ARM64

La base di compilazione è Ubuntu 22.04 con due job, glibc 2.35 e runtime C++
del sistema compatibile con `GLIBCXX_3.4.30`. Il pacchetto include Flutter,
GTK, PDFium, DSS/JVM, Python e strumenti NSS; PC/SC e lo stack grafico restano
quelli del sistema. La guida browser copia il provider in un percorso utente
persistente solo dopo conferma. Gli script dei pacchetti nativi conservano
i propri percorsi e comportamento. [Build e collaudi AppImage](LINUX_APPIMAGE.md).

### Scaling dei caratteri Linux

La dimensione della finestra è separata dallo scaling dei caratteri.
`linux/runner/window_sizing.cc` usa `GdkMonitor` (GTK >= 3.22) e area utile
in pixel logici, senza moltiplicare per `gdk_monitor_get_scale_factor`.
1280×720 è una preferenza, con riserva per decorazioni e margine; uno spazio
inferiore causa una richiesta di massimizzazione al compositor. La finestra
resta ridimensionabile e osserva monitor/area utile/configurazione. Le dimensioni
minime sono limitate a quelle disponibili. Non vengono cambiate preferenze
del desktop, il comportamento dei caratteri o i runner macOS/Windows.
[API GTK dell'area utile](https://docs.gtk.org/gdk3/method.Monitor.get_workarea.html).

Il runner espone su `cie.id/linux_text_scaling` la risoluzione logica effettiva
dei caratteri GDK, divisa per 96. Usa `gdk_screen_get_resolution`, che include
già la compensazione `GDK_DPI_SCALE`, e osserva `notify::resolution` per le
variazioni durante l’esecuzione. Non modifica impostazioni del desktop.

Il builder dell’app applica questo valore solo su Linux e solo quando Flutter
fornisce `TextScaler.noScaling`. Un text scaler già attivo nel motore ha la
precedenza e viene conservato integralmente, anche se riduce i caratteri.
Non si moltiplicano le scale GTK e Flutter e non si usa `devicePixelRatio` per
calcolare la scala del testo. Risoluzioni non disponibili o non valide usano
il comportamento standard di Flutter. La scala raggiunge anche i dialoghi.

I test del runner richiedono i file Flutter generati dalla build Linux, ma
non avviano l’app né richiedono un display, un lettore o una carta:

```sh
cmake -S linux/runner/tests -B .build/linux-runner-tests -G Ninja
cmake --build .build/linux-runner-tests --parallel 2
ctest --test-dir .build/linux-runner-tests --output-on-failure
flutter test --no-pub test/linux_text_scaling_test.dart
```

Per leggere soltanto il valore del desktop corrente, senza finestre o accessi
alla carta: `.build/linux-runner-tests/text_scaling_tests --desktop-read-only`.

Con `xvfb-run` e `dbus-run-session` disponibili, CTest include anche
`linux_window_chrome`: usa un display virtuale e un portale sintetico per
controllare l'icona unica, il layout dei pulsanti, i cambi di preferenza
chiaro/scuro e la chiusura durante una richiesta asincrona. Non apre l'app
né accede alla carta. La barra GTK conserva il tema del desktop, l'icona unica
e il layout dei pulsanti, senza forzare colori o una scala aggiuntiva.

## DSS/JVM: macOS, Windows e Linux x86_64

`scripts/build_ltv.py` compila il worker Java e assembla JAR originali separati, JVM private, trust e helper CRL. Usare Java 21 e il Maven fissato in `native/ltv/toolchain.lock.json`, con percorsi effettivi alla JDK e all’eseguibile Maven. Su Windows usare Python e percorsi Windows.

```sh
python3 scripts/build_ltv.py \
  --java-home /percorso/jdk-21 \
  --maven /percorso/apache-maven/bin/mvn \
  --base-runtime native/runtime/macos-base \
  --output native/runtime/macos-complete --system macos
python3 scripts/test_ltv.py --runtime native/runtime/macos-complete --report reports/ltv.json
python3 scripts/test_history.py --runtime native/runtime/macos-complete --report reports/history.json
```

Per Windows selezionare `--system windows` e i runtime Windows. Per Linux x86_64 usare `--system linux`, il JDK Linux e i runtime fissati nel lock; vedere [LINUX_DSS_LTA.md](LINUX_DSS_LTA.md). Non usare `--refresh-dependency-lock` per una normale build: è un aggiornamento esplicito delle dipendenze. Lo script richiede una destinazione nuova e non sostituisce runtime precedenti. Gli archivi JDK/JRE e Maven si ottengono dai riferimenti/checksum del lock, fuori da Git. [Dettagli DSS](../native/ltv/README.md) · [Materiali da distribuire](LICENSING.md).

## Test senza carta e prove esplicite

I test Flutter e CTest predefiniti usano identità sintetiche. Per il solo ponte, senza compilare tutte le dipendenze:

```sh
cmake -S native -B .build/bridge-tests -DCIE_BUILD_BACKEND=OFF -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/bridge-tests --config Debug
ctest --test-dir .build/bridge-tests -C Debug --output-on-failure
```

Su Linux occorrono comunque gli header PC/SC. `build_native.py` esegue CTest solo per build native; lo smoke sul sistema destinatario esegue anche SDK, documenti, firme sintetiche e casi temporali.

I tre test Flutter documentali opt-in richiedono il runtime e fixture sintetiche in `reports/ux4-fixtures`. Il generatore `cie_document_tests` accetta il percorso del middleware e, come secondo argomento, la cartella in cui conservare le fixture. Aggiungere un file di testo `not-a-pdf.pdf` per il caso negativo. Impostare `CIE_PROTOTYPE_RUNTIME` al runtime da verificare e poi eseguire:

```sh
flutter test --no-pub --dart-define=CIE_UX4_RUNTIME_TESTS=true test/verification_runtime_test.dart
```

Il rilevamento reale è un’operazione separata con `smoke_native.py --detect`; le firme reali richiedono `test_card_signing.py` o un’azione nell’app. Non aggiungere questi passaggi ai test automatici. Non usare PIN volutamente errati. Cambio PIN e PUK non sono test di compilazione.

Le workflow GitHub sono inizialmente ad avvio manuale e non includono credenziali di firma o hardware. I risultati locali non attestano che una workflow sia già riuscita su GitHub.
