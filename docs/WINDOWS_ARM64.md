# Windows ARM64 con GitHub Actions

Il workflow manuale [Windows ARM64 package](../.github/workflows/windows-arm64.yml)
prepara app, middleware, componente Web e installer per **Windows 11 ARM64**.
La macchina virtuale dell'utente serve soltanto per installazione e collaudo:
non richiede Flutter, Visual Studio, Python, Java o Maven di sviluppo.

**Stato:** infrastruttura predisposta; la prima esecuzione completa su GitHub
e il collaudo con lettore/CIE su Windows ARM64 devono ancora essere eseguiti.
La riuscita dei test x64 precedenti non attesta quella dei binari ARM64.

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

Il controllo PE esamina eseguibili, DLL, libreria AOT `data/app.so`, PDFium,
provider e JVM; rifiuta anche un singolo binario x64 o un manifest incoerente.
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

Riferimenti: [LLVM-MinGW](https://github.com/mstorsjo/llvm-mingw),
[architetture Inno Setup](https://jrsoftware.org/ishelp/topic_archidentifiers.htm),
[installer Windows](WINDOWS_INSTALLER.md).
