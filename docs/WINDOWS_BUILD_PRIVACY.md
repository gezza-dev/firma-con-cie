# Riservatezza delle distribuzioni Windows

Le distribuzioni conservano attribuzioni e licenze, autore dei commit e
identità dei firmatari. I percorsi dei profili usati per compilare non devono
invece comparire nei file dell'app, nei manifest o negli installer.

## Compilazione da directory generiche

Preparare una copia reale dei sorgenti, SDK Flutter fissato e cache Pub fuori
dal profilo, per esempio sotto `C:\Build`. Un collegamento che risolve nel
profilo originale non sostituisce questa copia. Non cambiare le dipendenze
del lock e non modificare stringhe all'interno dei binari già compilati.

Per il backend x64, ricompilare tutte le dipendenze statiche con
`build_portable_dependencies.py`, poi il middleware con `build_native.py`,
da un checkout/prefix Linux generico o dal runner GitHub. Le mappature GCC
proteggono `__FILE__` e informazioni di debug; il prefix effettivo deve essere
generico anche perché OpenSSL conserva directory e flag di configurazione.
Riassemblare poi il runtime DSS con il nuovo trasporto CRL. La ricetta e i
lock sono quelli di [BUILDING.md](BUILDING.md).

Sul Windows corrispondente alla CPU di destinazione, una volta preparati
runtime privato e componente Web secondo la ricetta ordinaria:

```powershell
python scripts/windows_build_privacy.py `
  --flutter-sdk C:/Build/Tools/flutter `
  --pub-cache C:/Build/Tools/pub-cache --check
```

Lo script deve essere eseguito dalla copia generica del progetto. Verifica
il commit dello SDK e usa `pub get --enforce-lockfile`. Passa a MSVC
`/experimental:deterministic` insieme alle mappature `/pathmap`, e conserva
solo il nome del PDB nei metadati PE con `/PDBALTPATH`. Le opzioni sono state
verificate con il compilatore MSVC 19.44; i binari prodotti devono comunque
superare l'audit. La CPU viene ricavata dal Dart SDK realmente eseguito,
coerentemente con Flutter, e verificata nel payload finale.

Il sorgente e le cache generiche evitano anche che i registranti Dart generati
inseriscano nel codice AOT gli URI del profilo di compilazione.

## Mappe di sviluppo e manifest operativi

Il file `native_assets.json` alla radice della vecchia build è una mappa di
compilazione con percorsi assoluti. CMake non lo copia più e la policy di
distribuzione lo esclude anche da build precedenti. Viene conservato senza
modifiche il manifest operativo `data/flutter_assets/NativeAssetsManifest.json`,
che fa riferimento a `pdfium.dll` inclusa nel bundle.

Il packager controlla i file effettivamente distribuiti dopo le esclusioni.
L'opzione ripetibile `--private-path-root` permette di respingere anche i
profili di vecchie build prodotte su altre macchine. I valori dei profili non
sono registrati nel manifest pubblico. Dopo la compilazione Inno vengono
controllate anche le intestazioni dell'installer.

## Audit completo senza installare

`check_windows_distribution.py` esamina directory o installer Inno tramite
`innex` 0.7.2, senza eseguire l'installer. Controlla file binari e testuali,
stringhe UTF-16, URI, JSON, intestazioni/metadati Inno e contenuti compressi
ZIP/JAR e gzip/zlib. Errori di lettura o limiti di espansione fanno fallire
il controllo. Il rapporto elenca soltanto nomi relativi, conteggi ed esiti.

```powershell
python scripts/check_windows_distribution.py C:/Build/Output/setup.exe `
  --innex C:/Build/Tools/innex/bin/innex.exe --temporary-root C:/Build/Temp `
  --profile-root C:/Users/profilo-privato `
  --profile-root /Users/profilo-privato `
  --report C:/Build/Output/windows-privacy.json
```

Specificare i profili reali di tutte le macchine di compilazione soltanto
nel comando locale. I normali percorsi generici CI e le attribuzioni upstream
restano invariati. Per ARM64 non serve ricompilare un pacchetto già collaudato
se l'audit completo conferma che non contiene i profili personali e il codice
Windows è equivalente ai sorgenti correnti.

Le regressioni sono `test_windows_packaging_privacy.py` (gate del packager,
esclusione della mappa di sviluppo e conservazione del manifest operativo),
`test_windows_distribution_privacy.py` (archivi/encoding e rapporti) e
`test_windows_installer.py` (motore Inno reale su profili/componenti sintetici).
Nessuna prova richiede carta, PIN, autenticazioni o installazione del componente
di produzione. La verifica dei binari non equivale alla firma Authenticode.
