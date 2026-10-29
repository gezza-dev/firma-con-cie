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

Riferimenti: [LLVM-MinGW](https://github.com/mstorsjo/llvm-mingw),
[architetture Inno Setup](https://jrsoftware.org/ishelp/topic_archidentifiers.htm),
[installer Windows](WINDOWS_INSTALLER.md).
