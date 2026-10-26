# AppImage Linux x86_64 e ARM64

L’AppImage usa Ubuntu 22.04 LTS come base di compilazione, con
glibc 2.35. Si ricompilano
su questa base anche le dipendenze statiche native: i precedenti binari CIE
richiedevano glibc 2.38 e non vengono riutilizzati. Flutter Engine e PDFium
sono precompilati nelle versioni fissate dal progetto; il controllo ABI esamina
anche questi file e tutti gli ELF della JVM DSS, non soltanto il runner.
Il confezionamento compila anche il database MIME incluso e richiede gli
schemi delle impostazioni desktop: PNG/SVG e icona della finestra devono
funzionare senza dipendere dai metadati del desktop di destinazione.

Il formato è AppImage Type 2, con runtime statico fissato per versione e SHA-256
in `linux/appimage/runtime.lock.json` per x86_64 e
`linux/appimage/runtime-aarch64.lock.json` per ARM64/AArch64. Include firma/verifica, PDFium, DSS/JVM,
GTK e dipendenze private, Python 3.10 e strumenti NSS per la guida dei browser.
Non incorpora Chrome o Firefox. I browser del sistema usano il provider con
il PIN completo di otto cifre; la firma nell'app mantiene il PIN parziale per
le CIE abbinate. I dati e gli abbinamenti restano quelli dell'app nativa.

## Librerie e servizi del sistema

Restano esterni glibc e il loader, libstdc++/libgcc, le librerie grafiche e i
driver del sistema (OpenGL/EGL, Mesa e Wayland), `libpcsclite.so.1`, `pcscd` e i driver del lettore.
Non vengono distribuiti servizi, regole udev o copie di PC/SC. Il runtime C++
del sistema evita che una copia più vecchia interferisca con Mesa/LLVM dei
sistemi recenti. GTK e le librerie non garantite dai desktop di destinazione
vengono incluse; l'avvio non imposta un `LD_LIBRARY_PATH` globale. I percorsi
relativi nei singoli ELF risolvono le librerie private. Fontconfig usa una
configurazione inclusa compatibile con la libreria, mantenendo la ricerca dei
font nelle cartelle del sistema e dell’utente e una cache dedicata.

Anche i certificati HTTPS restano quelli del sistema (`ca-certificates`). Il
trasporto nativo individua a ogni richiesta il bundle Debian/Ubuntu, Fedora
o openSUSE e l'eventuale cartella `/etc/ssl/certs`, senza dipendere dalla
ricerca automatica di libcurl durante la compilazione incrociata. La stessa
selezione vale per i proxy HTTPS. Non si includono radici TLS personali e non
si disabilitano la verifica del certificato o del nome del server.

Questo controllo serve anche quando un indirizzo CRL inizia con `http://`:
il servizio CIE può reindirizzarlo a HTTPS. L'assenza di radici TLS impediva
alla prima AppImage ARM64 di consultare tali prove e produceva correttamente
un esito di revoca indeterminato. Un problema di rete, una CRL non valida o
un certificato TLS non attendibile devono continuare a dare un esito
indeterminato, senza essere trasformati in «non revocato».

La base dichiarata è Linux x86_64 oppure ARM64 con glibc almeno 2.35 e runtime C++ compatibile
con i simboli elencati nel manifest. Non è una promessa di compatibilità con
ogni distribuzione, con musl/Alpine o con qualunque stack grafico. Il normale
montaggio richiede supporto FUSE e il relativo helper del sistema; il runtime
supporta `--appimage-extract-and-run` quando il montaggio non è disponibile.
L'AppImage non è una sandbox: l’esecuzione isolata richiede un contenitore separato.

## Provider persistente per i browser

Il solo avvio o rilevamento dei profili non scrive nei browser e non installa
il provider. Dopo conferma nella Home, i profili nuovi di Firefox standard e
Chrome desktop ricevono un percorso della forma:

```
~/.local/share/firma-con-cie/pkcs11/v1/<hash-generazione>/libcie_linux_pkcs11.so
```

Se `XDG_DATA_HOME` è un percorso assoluto interno alla home, viene usato quello.
Se le cartelle dati hanno permessi condivisi o collegamenti simbolici, viene
usata invece `~/.firma-con-cie/pkcs11/v1/<hash-generazione>`: non si cambiano i
permessi delle cartelle esistenti. La cartella contiene le tre librerie CIE e un
manifest con checksum. La copia
è verificata e pubblicata atomicamente, senza privilegi amministrativi. Il
percorso rimane disponibile dopo la chiusura, lo spostamento o l'eliminazione
dell'AppImage. Il manifest rileva corruzioni; non è una protezione contro un
programma ostile che già opera con i permessi dell'utente.

Una versione aggiornata del provider genera una nuova cartella e richiede una
nuova conferma; la precedente rimane disponibile per gli altri profili. Non
vengono eliminate automaticamente generazioni potenzialmente ancora utilizzate.
Le registrazioni native già valide sotto `/opt/firma-con-cie` vengono riutilizzate
senza riscriverle. Gli script dei pacchetti nativi conservano il comportamento
precedente. Firefox Snap usa il percorso e la procedura Snap già collaudati;
l'eventuale permesso `pcscd` resta un'azione separata, autorizzata dall'utente
con gli strumenti del sistema. Il caricamento sui browser Flatpak non è incluso.

Il browser deve essere chiuso prima della conferma. La guida riusa scoperta
profili, controlli, lock, preparazione NSS su un database vuoto e conservazione
dei moduli estranei già implementati. Non apre i database personali di chiavi
o certificati per generarvi il modulo, non richiede il PIN e non autentica la
CIE. Python e NSS inclusi permettono la guida anche se `modutil` non è installato
sul sistema. PC/SC rimane sempre esterno anche per il provider persistente.

### Firefox Snap e alternanza con i pacchetti nativi

Il confezionamento AppImage conserva identiche, byte per byte, le tre librerie
del provider provenienti dal bundle nativo: `libcie_linux_pkcs11.so`,
`libcie_web.so` e `libcie-pkcs11.so`. Prima della rilocazione controlla ABI,
dipendenze ammesse e percorsi relativi necessari per trovare le librerie vicine.
Gli altri ELF dell'AppImage continuano a ricevere i percorsi privati richiesti.

Questo evita di cambiare l'impronta della copia Snap soltanto per il formato
di distribuzione. Quando i due pacchetti contengono lo stesso provider, una
configurazione effettuata dal `.deb` è riconosciuta anche dall'AppImage e
viceversa, senza riscrivere `pkcs11.txt`. Non cambia il controllo esatto degli
hash: un provider aggiornato richiede una nuova generazione e una copia
alterata resta rifiutata. Il PIN per il browser resta completo.

Le vecchie AppImage riscrivevano i percorsi di due di queste librerie. Se il
profilo usa ancora una loro copia, può essere necessaria una configurazione
esplicita una sola volta con il provider ora condiviso; non vengono modificati
automaticamente profili o permessi Snap. La correzione entra nei nuovi archivi
quando l'AppImage viene rigenerata: non cambia i pacchetti già prodotti.

Verifiche software del 26 ottobre: entrambi gli ordini di configurazione su
profili Snap temporanei, quattro passaggi ripetuti per ordine senza nuove
registrazioni NSS, rifiuto delle copie alterate e rilevamento degli aggiornamenti
effettivi. Controllati anche Firefox standard e Chrome su
profili sintetici. Le librerie x86_64 sono caricate sotto guardia senza
inizializzare PKCS#11; per ARM64 sono verificati conservazione dei byte e ABI,
senza eseguire il runtime. Browser reali, permessi Snap e CIE restano esclusi.

## Preparazione

`linux/appimage/Dockerfile` descrive l'ambiente Ubuntu 22.04 fissato. È possibile
usare Docker/Podman oppure un contenitore rootless equivalente a partire dallo
stesso indice OCI fissato, selezionando `linux/amd64` oppure `linux/arm64`.
Ogni AppImage contiene binari di una sola architettura. Nei test locali vengono esposti soltanto sorgenti,
toolchain e file sintetici; nessun socket PC/SC, dispositivo USB o profilo reale.

Nell'ambiente 22.04, con il Flutter Linux fissato dal progetto e due job:

```sh
python3 scripts/build_portable_dependencies.py --arch x86_64 --jobs 2
python3 scripts/build_native.py --system linux --jobs 2 \
  --dependency-prefix .build/dependencies/linux-x86_64/prefix \
  --build-dir .build/native-appimage --output native/runtime/linux
# Aggiungere il runtime DSS/JVM secondo LINUX_DSS_LTA.md prima della GUI.
flutter pub get --enforce-lockfile
CMAKE_BUILD_PARALLEL_LEVEL=2 flutter build linux --release --no-pub
python3 scripts/package_linux_appimage.py \
  --bundle build/linux/x64/release/bundle \
  --runtime /percorso/runtime-x86_64 \
  --version 1.0.0 --output dist/linux-appimage
```

Per ARM64 usare un ambiente Ubuntu 22.04 ARM64 nativo o emulato. La build
Debian ARM64 precedente, basata su Ubuntu 24.04, non costituisce la base di
questo AppImage: si ricompilano le librerie native contro la glibc 2.35.
Con due job, usare `--arch aarch64` per le dipendenze,
`--architectures aarch64` per `build_native.py`, il prefisso
`.build/dependencies/linux-aarch64/prefix` e una JVM privata `linux-arm64`.
Flutter produce `build/linux/arm64/release/bundle`. Il confezionamento nel
sistema ARM64 usa:

```sh
python3 scripts/package_linux_appimage.py \
  --bundle build/linux/arm64/release/bundle \
  --runtime /percorso/runtime-aarch64 \
  --version 1.0.0 --output dist/linux-appimage-arm64
```

Il risultato si chiama `firma-con-cie-1.0.0-aarch64.AppImage`; x86_64 mantiene
`firma-con-cie-1.0.0-x86_64.AppImage`. Il packager riconosce la CPU dell’ambiente,
verifica runtime AppImage e ogni ELF, seleziona i percorsi di sistema corretti
e rifiuta un payload misto. La compatibilità di ABI è controllata anche sul
modulo persistente dei browser; nei browser si mantiene il PIN completo.
Chrome deve essere disponibile come browser nativo della stessa architettura:
la guida non installa un browser e non ne garantisce la disponibilità su ARM64.

Il file del runtime deve corrispondere al checksum fissato. Il confezionamento
rifiuta ELF con requisiti glibc superiori a 2.35, librerie PC/SC/glibc incluse e
file con architettura diversa. Sono esclusi programmi di test e dati utente.
Sono inclusi documentazione, licenze del progetto e avvisi dei pacchetti Ubuntu
usati per le librerie private; il manifest registra versioni, ABI e SHA-256.
Le condizioni di una distribuzione pubblica restano quelle di LICENSING.md.

## Verifiche e collaudo reale

I test software devono verificare il file AppImage, l'estrazione, l'avvio GUI
su un display virtuale, le dipendenze su Ubuntu 22.04/24.04, Debian, Fedora e
Arch, il runtime DSS e la guida NSS con profili sintetici. Il test del provider
rimuove la copia sorgente dopo la configurazione e controlla che il percorso
registrato rimanga valido. Le prove bloccano PC/SC e usano HOME temporanee.

Durante la preparazione i test non installano pacchetti sul computer né
modificano browser reali. Per x86_64 sono stati superati i controlli runtime e ABI,
DSS/LTA, modulo persistente e avvio GUI su Xvfb nelle cinque basi indicate,
oltre ai test Flutter, CTest nativi e runner GTK. I test in contenitore non
equivalgono al collaudo di tutti i desktop Wayland, GNOME/KDE, driver GPU,
lettori e servizi PC/SC.

### Collaudi reali confermati dall'utente (25 ottobre 2026)

Sul computer Linux x86_64 sono riusciti l'avvio ordinario dell'AppImage e il
collaudo dell'interfaccia. L'utente ha confermato firma PAdES/PDF e CAdES/P7M
del documento sintetico con PIN parziale; un controllo offline ha verificato
l'integrità crittografica delle firme e, per il P7M, l'identità del contenuto
rispetto al PDF originale. Questi controlli non attestano catena di fiducia,
revoche o validità a lungo termine.

Confermate anche configurazione guidata e autenticazione reale con Firefox
desktop e Google Chrome usando il PIN completo soltanto nel browser. Chrome
ha mantenuto l'accesso dopo la chiusura dell'AppImage; il controllo successivo
ha verificato il provider persistente e la conservazione della configurazione
Firefox e dei moduli Chrome estranei.

Successivamente, su richiesta dell'utente, sono stati rimossi il pacchetto
nativo, le registrazioni CIE nei tre browser e gli abbinamenti locali.
È riuscito un nuovo abbinamento dall'AppImage con PIN completo inserito
dall'utente soltanto nell'app. Dopo la chiusura e riapertura, la CIE è rimasta
abbinata senza reinserire il PIN. Il record cifrato è risultato leggibile e
invariato; la verifica di persistenza ha bloccato PC/SC e non ha eseguito firme
o accessi ai siti. L'agente non ha acquisito PIN o controllato sessioni
autenticate. I rapporti restano locali, esclusi dai sorgenti pubblicati.

Restano separati i collaudi reali su altre distribuzioni e desktop, Firefox
Snap dall'AppImage, cambio PIN e sblocco carta. La versione `1.0.0` è preparata per la prima release del progetto e copre
x86_64 e ARM64 con artefatti distinti. I collaudi reali riportati sopra
riguardano x86_64; ARM64 richiede ancora hardware reale. La pubblicazione è un passaggio successivo, insieme ai materiali di
distribuzione descritti in [LICENSING.md](LICENSING.md), inclusi i sorgenti
corrispondenti delle dipendenze richiesti per il bundle effettivo.
