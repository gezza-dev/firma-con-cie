# Compilare CIE ID Desktop

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

## macOS Universal

Servono Xcode completo con supporto ai cataloghi `.icon` (Xcode 26 o successivo), SDK macOS, CMake/Ninja e gli strumenti della tabella. Il deployment target dell’app e del backend è macOS 12.0. Il toolchain di compilazione può richiedere un macOS più recente.

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
  --destination "$HOME/Developer/Builds/CIE-ID/macos" \
  --build-workspace "$HOME/Developer/Builds/CIE-ID/workspace" \
  --identity "$CIE_SIGNING_IDENTITY" \
  --web-extension .build/web-macos/CIEPrototypeToken.appex
```

Il bundle risultante è `CIE-ID.app`, con librerie private, avvisi e CTK. La copia di compilazione deve essere fuori dalla cartella dei sorgenti. Lo script non registra o attiva l’estensione e non esegue prove sulla carta. Se si cambiano bundle identifier o App Group occorre allineare host, estensione e archivi; gli identificativi storici sono intenzionalmente conservati.

Senza CryptoTokenKit si possono omettere `build_web_macos.py` e `--web-extension`, usando la firma ad hoc predefinita per le sole prove locali. Tale bundle non offre automaticamente l’accesso Web. Apple Development non è notarizzazione: distribuzione Developer ID e notarizzazione sono passaggi separati.

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
flutter pub get --enforce-lockfile
flutter build windows --release
```

L’output è `build/windows/x64/runner/Release/CIE-ID.exe`. Distribuire l’intera cartella Release, che contiene `cie_native`, risorse Flutter, PDFium e payload Web. Il solo `.exe` non basta. I comandi di compilazione non devono registrare driver né autenticare la carta; il helper esegue l’installazione solo su azione esplicita nell’app con UAC. [Flusso e collaudi Windows](WINDOWS_WEB_FIRST_USE.md).

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

Conservare l’intera directory `build/linux/<architettura>/release/bundle`. Il runner copia le librerie private in `cie_native`; pcsc-lite e driver compatibili devono essere disponibili sul sistema destinatario. La cache cifrata degli abbinamenti è condivisa e ha test software e prove reali Linux. Il provider di accesso Firefox PKCS#11 è incluso; il test reale di accesso è stato confermato riuscito dall’utente. La build non registra il modulo nel browser: la configurazione resta manuale. Vedere [LINUX_FIREFOX.md](LINUX_FIREFOX.md). L’assemblaggio DSS/JVM Linux resta incompleto. Per il solo bridge Linux serve OpenSSL 3 (`libssl-dev`); la build completa usa la copia privata del prefisso quando specificato.

### Scaling dei caratteri Linux

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

## DSS/JVM: macOS e Windows

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

Per Windows selezionare `--system windows` e i runtime Windows. Non usare `--refresh-dependency-lock` per una normale build: è un aggiornamento esplicito delle dipendenze. Lo script richiede una destinazione nuova e non sostituisce runtime precedenti. Gli archivi JDK/JRE e Maven si ottengono dai riferimenti/checksum del lock, fuori da Git. [Dettagli DSS](../native/ltv/README.md) · [Materiali da distribuire](LICENSING.md).

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
