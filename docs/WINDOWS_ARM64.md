# Windows ARM64 con GitHub Actions

Il workflow manuale [Windows ARM64 package](../.github/workflows/windows-arm64.yml)
prepara app, middleware, componente Web e installer per **Windows 11 ARM64**.
La macchina virtuale dell'utente serve soltanto per installazione e collaudo:
non richiede Flutter, Visual Studio, Python, Java o Maven di sviluppo.

**Stato:** esecuzione completa `40914057599` riuscita sul commit `ed49908`,
con installer corretto generato e scaricato. Il 29 ottobre 2026 l'utente ha
confermato sulla VM Windows 11 ARM64 il successo dei test di abbinamento CIE,
configurazione automatica per i browser, firma, verifica firma e accesso ai siti
con CIE. L'errore di avvio 740 del controllo del componente è stato corretto.

## Collaudo confermato dall'utente (29 ottobre 2026)

Pacchetto `firma-con-cie_1.0.0_windows_arm64_setup.exe`, prodotto dalla
[build Actions 40914057599](https://github.com/gezza-dev/firma-con-cie/actions/runs/40914057599)
sul commit `ed499088f4d8dd22444aaa7e4feb0c40a0e1854b`.
SHA-256 dell'installer:
`4a318a8e536e753f2497da219e6c15fde8311e9dd6d7f2c765f9866797866599`.

| Prova su Windows 11 ARM64 | Esito confermato |
| --- | --- |
| Abbinamento della CIE | Riuscito |
| Configurazione automatica dell'accesso ai siti per i browser | Riuscita |
| Firma | Riuscita |
| Verifica firma | Riuscita |
| Accesso ai siti con CIE | Riuscito |

La conferma riguarda il pacchetto installato sulla VM dell'utente. Non sono
stati specificati i nomi/versioni dei browser o i formati di firma utilizzati;
il risultato non viene attribuito separatamente a ogni browser o formato.
La build automatica ha inoltre superato 383 test Flutter (14 saltati),
49 controlli Inno isolati e le verifiche di architettura, integrità e manifest.

## Avvio e risultati

1. Portare questi sorgenti sul ramo remoto da compilare. Il workflow deve essere
   presente anche sul ramo predefinito perché GitHub mostri il comando manuale.
2. Nel repository `gezza-dev/firma-con-cie`, aprire **Actions → Windows ARM64
   package → Run workflow**, selezionare il ramo e avviare.
3. Attendere il completamento di entrambi i job. In caso di errore leggere i log
   del passaggio e gli artifact diagnostici; non usare un payload incompleto.
4. Scaricare l'artifact `firma-con-cie-windows-arm64-<commit>` dalla stessa
   esecuzione. Contiene:

   - `firma-con-cie_1.0.0_windows_arm64_setup.exe` (versione da `pubspec.yaml`);
   - checksum `.exe.sha256` e rapporto `package-result.json`;
   - `Release/`, cartella completa dell'app e delle sue dipendenze.

Il workflow non crea release, non pubblica pacchetti, non firma Authenticode
il prodotto e non modifica il repository. Gli artifact finali e i report sono
conservati per 14 giorni; il trasferimento nativo intermedio per 7 giorni.
Per un'installazione nuova usare l'installer: avviare il solo eseguibile da
`Release` non installa il componente di sistema.

Il runner predefinito è `windows-11-arm`; disponibilità e fatturazione dipendono
dal piano e dalle impostazioni Actions del repository. Consultare la
[tabella aggiornata GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).
Non sono necessari PAT, credenziali della CIE, certificati personali o secret
per i job di compilazione. I permessi del token sono `contents: read`.

## Compilazione completa

| Fase | Host | Risultato |
| --- | --- | --- |
| Dipendenze e backend | Ubuntu 24.04 x64 con LLVM-MinGW UCRT | Tutte le librerie statiche ricompilate dai lock esistenti, DLL/observer/fetcher ARM64 |
| Accesso ai siti | Stesso job Linux | Minidriver, PKCS#11 e helper di installazione ARM64; header Microsoft CPDK verificato |
| DSS | Stesso job Linux | Worker Java condiviso, JAR verificati e JVM privata Temurin Windows ARM64 |
| App e test | Windows 11 ARM64 | Python e Dart nativi ARM64, test del backend e del provider, Flutter, test del runner |
| Distribuzione | Windows 11 ARM64 | Inno Setup, VC Redistributable ARM64 firmato Microsoft e test isolati dell'installer |

LLVM-MinGW, Inno, PDFium e JVM hanno URL/versione/SHA-256 fissati nei lock.
Maven conserva il lock SHA-512 già usato dal progetto. Gli script non riutilizzano
archivi C++ MinGW x64 nella nuova build; MSVC compila il runner Flutter e i suoi
test, comunicando con le DLL tramite le ABI C esistenti. Il runtime LLVM viene
collegato staticamente; i relativi testi di licenza sono conservati nel bundle.

Flutter resta fissato al commit di `toolchain.lock.json`. Questa versione
seleziona Windows ARM64 dall'ABI del **Dart SDK eseguito** e non offre l'opzione
`flutter build windows --target-platform`. Il workflow verifica che Python e
Dart siano ARM64 e termina se il bootstrap ripiega su x64.

Il controllo PE esamina eseguibili e DLL, inclusi PDFium, provider e JVM.
La libreria AOT Dart `data/app.so` usa invece ELF64 anche su Windows: un
controllo distinto ne verifica formato e CPU. Sono rifiutati anche un singolo
binario x64 nel pacchetto ARM64 o un manifest incoerente.
Il binario PDFium prodotto dall'hook Dart viene confrontato con l'archivio
ARM64 verificato separatamente. Il bootstrap di Inno può essere x64 ed essere
eseguito in emulazione su Windows 11 ARM64; i binari dell'app e del componente
rimangono ARM64. Il pacchetto ARM64 rifiuta Windows x64.

## Installazione e dati personali

UAC rimane nell'installer. L'installazione registra il componente senza
richiedere carta, lettore o PIN. Sono conservati AppId, identificativi tecnici,
percorsi degli archivi personali, abbinamenti e impostazioni. La configurazione
automatica dei browser rimane nell'app, in background, con la stessa policy di
rinvio e registrazione degli errori. La gestione del PIN non viene modificata.

I test Actions utilizzano dati sintetici. I test Inno hanno un AppId distinto,
un componente fittizio e una destinazione privata; non installano il componente
di produzione, non richiedono UAC e non eseguono operazioni sulla CIE.

## Collaudo sulla VM Windows ARM64

Dopo una build verde, verificare personalmente:

- installazione, aggiornamento, riparazione e disinstallazione; conservazione
  di abbinamenti e impostazioni e icona desktop selezionata per impostazione iniziale;
- apertura, ridimensionamento, hover e pulsanti della barra del titolo;
- anteprima PDF e firma grafica, inclusa la barra di conferma fissa;
- lettore/driver compatibile con Windows ARM64 e rilevamento in secondo piano;
- abbinamento e firme PAdES/CAdES, verifica firme e validazione DSS/LTA;
- accesso con **browser nativi ARM64** Chrome, Edge e Firefox. I browser x64
  in emulazione richiedono un collaudo separato; non se ne presume il supporto.

Per le prove con carta il PIN viene inserito personalmente nei campi protetti,
una sola volta per operazione. Un runner GitHub senza lettore non può attestare
il funzionamento reale del minidriver, l'inoltro USB della VM o il login al portale.

## Controlli locali senza compilare ARM64

```text
python scripts/test_windows_arm64.py
python scripts/test_product_identity.py
python scripts/test_build_paths.py
flutter analyze --no-pub
flutter test --no-pub
```

`test_windows_arm64.py` usa PE sintetici per verificare il rifiuto di architetture
miste, manifest/JVM incoerenti, header danneggiati e download alterati, oltre a
nome, destinazione e conservazione dei dati del pacchetto. Questi controlli non
sostituiscono l'esecuzione della pipeline e il successivo collaudo reale ARM64.

Verifica locale del 29 ottobre 2026 su Windows x64: actionlint 1.7.12 accetta il
workflow; analisi Flutter senza rilievi; 381 test Flutter superati e 14 saltati;
9 test dei confini ARM64, 8 dell'identità del prodotto e 9 dei percorsi di build
superati; 49 controlli con il vero motore Inno e payload sintetici superati.
L'archivio PDFium ARM64 è stato scaricato, verificato e i suoi 16 avvisi conservati.
Non è stata eseguita una compilazione dell'app ARM64 né un'installazione del
componente di produzione durante questa preparazione.

## Correzione dell'inizializzazione Windows di OpenSSL

La prima esecuzione Actions (`40869545859`, commit `84f3dd5`) si è fermata nel
collegamento di `openssl.exe`: simbolo `win32_utf8argv` non definito. Non sono
stati prodotti installer o runtime ARM64 completi.

OpenSSL 3.5.9 seleziona `apps/lib/win32_init.c` tramite un controllo sul nome
del target in `apps/lib/build.info`. Il precedente nome `cie-mingw-arm64` non
corrispondeva al prefisso `mingw`, pur ereditando `mingw-common`. Il target è
ora `mingw-arm64-cie`; rimangono le impostazioni ARM64, statiche e `no-asm`.
Il codice upstream e le funzioni crittografiche non vengono modificati.

Dopo `Configure`, `scripts/check_openssl_arm64.py` verifica che `configdata.pm`
includa il sorgente Windows e che il Makefile generi il relativo oggetto.
Una configurazione incompleta viene rifiutata prima di avviare `make`.

Verifica locale della correzione: il controllo Perl di selezione sorgenti del
tarball OpenSSL fissato dal lock omette l'inizializzatore con il vecchio nome
e lo include con quello nuovo. Superati 12 test ARM64 (inclusi tre casi del
grafo OpenSSL), 8 test dell'identità del prodotto e actionlint sul workflow.
Il collegamento effettivo ARM64 viene verificato dalla nuova esecuzione Actions;
questi test locali non ne attestano il completamento.

## Include SDK Windows di Crypto++ durante la compilazione da Linux

Nell'esecuzione `40875860520` (commit `4212ab8`), OpenSSL è stato compilato e
installato correttamente nel prefisso privato. La fase successiva si è fermata
in Crypto++ 8.9.0: `cpu.cpp` includeva `<Windows.h>` nel ramo `_M_ARM64`, mentre
gli header LLVM-MinGW sul filesystem Linux hanno nome `<windows.h>`.
L'installer non è stato generato.

La ricetta applica `scripts/prepare_cryptopp_arm64.py` esclusivamente ai sorgenti
Crypto++ estratti dall'archivio verificato, prima della build Windows ARM64.
Cambia la sola direttiva in `<windows.h>`, preservando byte, avvisi e terminatori
di riga del resto del file. Se la direttiva attesa manca o è ambigua, la build
si interrompe senza modificare il sorgente. Il checksum dello script entra
nell'identità della cache delle dipendenze, così una correzione della ricetta
non riutilizza silenziosamente un precedente archivio statico.

Versione e checksum del download upstream restano quelli del lock. Le ricette
Windows x64, macOS e Linux native non applicano questa trasformazione; funzioni
crittografiche e impostazioni `CRYPTOPP_DISABLE_ASM` rimangono invariate.
La prova locale sull'archivio Crypto++ fissato conferma una sola sostituzione;
i test ARM64 sono ora 15, con tre regressioni per include corretto, assente e
ambiguo. Il completamento della build ARM64 resta da verificare su Actions.

## Conversioni numeriche PoDoFo e libc++

L'esecuzione `40877350560` (commit `55b9797`) ha superato OpenSSL, Crypto++ e le
successive dipendenze fino a PoDoFo 1.1.2. La build si è fermata per chiamate
ambigue a `std::to_chars`: `charconv_compat.h` attivava i sostituti per vecchio
MinGW/GCC anche con la moderna libc++ di LLVM-MinGW. La macro di compatibilità
`__GNUC__` di Clang non rappresenta la versione della libreria C++ utilizzata.

`scripts/prepare_podofo_arm64.py` aggiunge `!defined(_LIBCPP_VERSION)` alle due
condizioni MinGW interessate, per `from_chars` e `to_chars`, nei soli sorgenti
estratti per Windows ARM64. Rimangono gli altri controlli upstream, inclusi
quelli per le vecchie libc++ e per i sistemi Apple. Il download resta fissato
al lock; tutte le altre parti e gli avvisi dell'header restano identici.
Se le condizioni attese cambiano, la trasformazione si interrompe senza
scrivere. Hash dello script e del probe sono inclusi nell'identità della cache.

Prima della build PoDoFo, la ricetta compila e collega
`native/tests/podofo_charconv_probe.cpp` per ARM64 contro l'header effettivamente
preparato e la libreria standard della toolchain. Il job Windows esegue questo
programma con casi float/double, precisione fissa, zero negativo, buffer
insufficiente e input non numerico. Il binario rimane negli strumenti CI,
senza entrare nell'app o nel componente installato.

Verifica locale con LLVM-MinGW 20261020: l'header originale dell'archivio
verificato riproduce l'ambiguità; quello corretto compila e si collega per
ARM64, con tipo PE controllato. Lo stesso probe compilato per x64 termina
correttamente su Windows. Superati 17 test ARM64, 8 test dell'identità del
prodotto e actionlint. Il probe ARM64 non è stato eseguito sul PC x64: tale
esecuzione e il completamento dell'app restano affidati al workflow.

## Punto d'ingresso Unicode del programma simulato dell'installer

L'esecuzione `40882037662` (commit `bb9728a`) ha superato PoDoFo, compilato il
backend e assemblato il runtime DSS. La fase Web si è fermata nel collegamento
del solo `cie_installer_fake.exe`, con `undefined symbol: WinMain`.

Il programma espone `wmain`; al suo target MinGW mancava `-municode`, già usato
dagli helper Windows di produzione. Il CMake applica ora tale opzione anche
al programma simulato, insieme al collegamento statico dei runtime. Non cambia
il comportamento MSVC né quello del componente installato.

`scripts/test_windows_installer_helper.py` verifica otto casi con log in una
cartella temporanea Unicode: i quattro comandi accettati, argomenti assenti o
non validi e un errore simulato. Il job Windows esegue il controllo sul binario
ARM64 prima dei test del provider e dei 49 casi dell'installer.

Verifica locale con LLVM-MinGW 20261020 e il vero progetto CMake: la versione
precedente riproduce `WinMain`, quella corretta compila e si collega per ARM64
(tipo PE verificato). Compilata anche la variante x64, sulla quale passano gli
otto casi dell'helper e i 49 controlli Inno con payload sintetici e dati
preservati. Superati inoltre 17 test ARM64, 8 test dell'identità del prodotto e
actionlint. Nessuna installazione di produzione, richiesta UAC o operazione
sulla CIE; l'esecuzione ARM64 resta affidata al runner GitHub.

## Compilazione del test PKCS#11 con gli header MinGW

L'esecuzione `40888376852` (commit `a410b3f`) ha superato il collegamento
dell'helper dell'installer e del modulo PKCS#11 di produzione. Il test
`pkcs11_tests.cpp` si è fermato perché il suo sostituto Windows globale
`void chmod(...)` entrava in conflitto con la vera dichiarazione MinGW
`int chmod(...)`, inclusa da `<filesystem>`.

Il sostituto è stato rimosso; la chiamata POSIX ai permessi `0700` rimane
nel solo ramo non Windows, conservando il comportamento Linux. Nessuna
operazione aggiuntiva viene eseguita su Windows. Il target della DLL simulata
ha inoltre `PREFIX ""` per mantenere lo stesso nome su MSVC e MinGW e
corrispondere a `cie_windows_pkcs11_fake.dll` richiesto dal job Windows.

Verifica locale: il sorgente precedente riproduce l'errore con LLVM-MinGW
20261020 per ARM64; il sorgente corretto compila e il tipo COFF ARM64 è
verificato. La build CMake x64 con LLVM e runtime statici supera tutti i
203 controlli PKCS#11 contro il modulo simulato, senza operazioni reali
sulla carta né configurazione dei browser. Superati anche 17 test ARM64,
8 test dell'identità del prodotto e actionlint. Collegamento ed esecuzione
del test ARM64 completo restano da verificare nella nuova esecuzione Actions.

## Formato della libreria AOT Flutter su Windows

L'esecuzione `40893166907` (commit `1396dd3`) ha completato il job nativo,
superato 381 test Flutter (14 saltati) sul runner ARM64 e compilato l'app.
Il controllo successivo si è fermato con `Invalid PE header` per `data/app.so`:
la pipeline presumeva erroneamente che anche questo file fosse PE.

Il Flutter SDK fissato in `toolchain.lock.json` usa `AotElfRelease` per
Windows; la VM Dart carica lo snapshot AOT in formato ELF anche su quel sistema.
`scripts/windows_architecture.py` verifica ora separatamente:

- EXE e DLL: formato PE e Machine `0xAA64` per ARM64 oppure `0x8664` per x64;
- `data/app.so`: ELF64 little-endian, tipo condiviso `ET_DYN`, versione/header,
  dimensioni e limiti delle tabelle, Machine 183 per ARM64 oppure 62 per x64;
- manifest nativo e JVM: coerenza con l'architettura richiesta.

Il controllo non carica o esegue alcun binario. Un ELF non può sostituire una
DLL Windows e un PE non può sostituire lo snapshot Dart. La verifica dei
checksum del payload resta attiva.

Regressioni locali: il controllo precedente riproduce l'errore sul vero
`app.so` Windows x64 già compilato; quello corretto verifica la stessa Release
senza modificarne i file (152 binari/AOT controllati). Superati 25 test dei
confini ARM64, inclusi AOT con CPU errata in entrambe le direzioni, ELF32,
endianness/versione non valide, file troncati e tabelle fuori limite; superati
anche 8 test dell'identità del prodotto e actionlint. Il pacchetto ARM64 finale
resta da generare nella nuova esecuzione Actions.

## Controllo del componente senza elevazione (29 ottobre 2026)

La diagnosi sulla VM ha confermato l'errore Windows 740 prima dell'avvio di
`CIE-Web-Setup.exe --status-package`. I 91 file del payload e le registrazioni
proprie erano presenti; il coordinatore browser registrava `component_not_ready`
con codice 6 perché il runner convertiva ogni errore di avvio in quel codice.
Il manifest PE del helper ARM64 compilato con LLVM-MinGW era assente; quello
x64 precedentemente compilato con MSVC conteneva già `asInvoker`.

Il progetto CMake comune ora incorpora esplicitamente `setup.manifest` tramite
`setup.rc` per MSVC e MinGW, su entrambe le CPU. Il livello è `asInvoker`,
`uiAccess=false`; installazione/rimozione richiedono ancora un token elevato
e restano responsabilità dell'installer. L'app non richiede UAC per i controlli.
Il runner conserva inoltre i codici di avvio effettivi e il timeout, evitando
di presentarli come prova di un componente da aggiornare.

`windows_helper_manifest.py` ispeziona senza esecuzione la risorsa PE numero 1,
tipo 24, su Linux e Windows. Build nativa ARM64 e packager di produzione
rifiutano manifest assenti, privilegi elevati o `uiAccess=true`.
`test_windows_web_helper.py` verifica il manifest del helper reale ed esegue
soltanto `--validate-package` e `--status-package`; è incluso nel job Windows.

Verifiche della correzione:

- Compilati con CMake il vero helper ARM64 LLVM-MinGW e i due helper x64
  LLVM-MinGW/MSVC: tipo PE e manifest `asInvoker` verificati.
- Su x64, entrambi gli helper restituiscono 0 alle due query da processo
  non elevato, senza PC/SC, UAC o scritture di sistema.
- Sulla VM ARM64, lo stesso manifest aggiunto esclusivamente a una copia
  privata del helper già compilato elimina l'errore 740: entrambe le query
  restituiscono 0 da processo non elevato. I 91 file del payload e il helper
  installato sono rimasti invariati. Questa prova conferma la correzione del
  manifest; non equivale al collaudo del nuovo binario o di un nuovo installer.
- Superati 30 test dei confini architettura/manifest/packaging, 44 test Flutter
  di stato/Home/configurazione browser e 8 test dell'identità del prodotto.
  Su ciascuna build x64 passano anche gli 8 casi CLI Unicode del helper
  simulato; superati i 49 controlli Inno isolati, senza installazioni reali.

Il nuovo pacchetto è stato generato dalla build Actions `40914057599` e
collaudato dall'utente come riportato nella sezione iniziale. Restano da
documentare separatamente eventuali prove di riparazione/disinstallazione,
conservazione dei dati negli aggiornamenti e i dettagli per browser/formato.

Riferimenti: [LLVM-MinGW](https://github.com/mstorsjo/llvm-mingw),
[architetture Inno Setup](https://jrsoftware.org/ishelp/topic_archidentifiers.htm),
[installer Windows](WINDOWS_INSTALLER.md).
