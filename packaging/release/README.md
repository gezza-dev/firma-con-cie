# Sorgenti delle dipendenze della release

`dependency-sources.lock.json` fissa l'archivio sorgente completo
Temurin/OpenJDK 21.0.12.1+1 e i cinquanta source JAR corrispondenti alle dipendenze
Java distribuite. Gli archivi nativi sono quelli già fissati da
`native/backend/scripts/dependencies.lock.json`.

`windows-runtime-sources.lock.json` registra le pubblicazioni Ubuntu, i file
sorgente originali e i loro hash per le versioni GCC/MinGW del runtime x64.
Sono inclusi GCC 13, gcc-mingw-w64, mingw-w64 e binutils con le patch di
confezionamento delle versioni registrate. I file sono verificati anche contro
la sezione `Checksums-Sha256` dei rispettivi descriptor `.dsc`.

I source JAR sono verificati contro i file pubblicati da Maven Central e sono
poi fissati con SHA-256. L'archivio completo OpenJDK è quello del distributore
Temurin della stessa release dei JRE; non è il solo `src.zip` Java.

Gli archivi originali restano fuori da Git. `scripts/prepare_release_sources.py`
controlla gli hash prima di creare il pacchetto, conserva nomi pubblici relativi
e verifica nuovamente i byte contenuti nello ZIP. Non sovrascrive un archivio
esistente e non include percorsi locali o directory di compilazione.

Per prepararlo occorrono:

| Opzione | Materiale locale |
| --- | --- |
| `--native-cache` | Cartella dei dodici archivi nativi originali |
| `--jdk-archive` | Archivio sorgente OpenJDK fissato |
| `--java-sources` | Cartella dei cinquanta source JAR |
| `--toolchain-cache` | Sorgenti Ubuntu e descriptor fissati per GCC/MinGW |
| `--output` | Nuovo file ZIP da allegare alla release |

Il pacchetto delle dipendenze va usato insieme ai sorgenti del progetto della
stessa release. Ogni componente mantiene i propri termini; i compilatori e gli
SDK Apple/Microsoft da ottenere separatamente non vengono redistribuiti.

## Supplemento Linux

`linux-system-sources.lock.json` fissa i pacchetti sorgente Ubuntu delle librerie e degli strumenti inclusi nelle due AppImage, distinti dai componenti forniti dal sistema ospite. Ogni voce conserva la versione sorgente esatta, la pubblicazione Launchpad e i file originali con SHA-256, verificati contro il descriptor `.dsc`. Le due versioni di systemd presenti nei pacchetti x86_64 e AArch64 restano entrambe registrate.

L’inventario completo binario/sorgente è allegato alla release come `linux-bundled-system-sources.json`; `linux-build-materials.zip` conserva separatamente patch agli strumenti Flutter, revisioni e istruzioni di ricostruzione senza impostazioni locali. Il supplemento dei sorgenti Ubuntu si usa insieme agli altri due archivi del progetto e delle dipendenze comuni.

Per creare il supplemento da una cache con cartelle `<nome-sorgente>_<versione>` (l’eventuale `:` dell’epoca è sostituito da `_epoch_`):

```sh
python3 scripts/prepare_linux_release_sources.py \
  --cache /percorso/cache-sorgenti-ubuntu \
  --inventory /percorso/linux-bundled-system-sources.json \
  --output /percorso/firma-con-cie_1.0.0_linux-dependency-sources.zip
```

Lo script verifica inventario, versioni, dimensioni e hash prima di scrivere il nuovo archivio; verifica poi anche il contenuto dello ZIP.
