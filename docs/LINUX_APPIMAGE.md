# AppImage x86_64 di test

La distribuzione Flatpak è temporaneamente accantonata. Il prototipo AppImage
usa Ubuntu 22.04 LTS come base di compilazione, con glibc 2.35. Si ricompilano
su questa base anche le dipendenze statiche native: i precedenti binari CIE
richiedevano glibc 2.38 e non vengono riutilizzati. Flutter Engine e PDFium
sono precompilati nelle versioni fissate dal progetto; il controllo ABI esamina
anche questi file e tutti gli ELF della JVM DSS, non soltanto il runner.

Il formato è AppImage Type 2, con runtime statico fissato per versione e SHA-256
in `linux/appimage/runtime.lock.json`. Include firma/verifica, PDFium, DSS/JVM,
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

La base dichiarata è Linux x86_64 con glibc almeno 2.35 e runtime C++ compatibile
con i simboli elencati nel manifest. Non è una promessa di compatibilità con
ogni distribuzione, con musl/Alpine o con qualunque stack grafico. Il normale
montaggio richiede supporto FUSE e il relativo helper del sistema; il runtime
supporta `--appimage-extract-and-run` quando il montaggio non è disponibile.
L'AppImage non è una sandbox: una prova isolata richiede un contenitore separato.

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

## Preparazione

`linux/appimage/Dockerfile` descrive l'ambiente Ubuntu 22.04 fissato. È possibile
usare Docker/Podman oppure un contenitore rootless equivalente a partire dallo
stesso manifest OCI. Nei test locali vengono esposti soltanto sorgenti,
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
  --version 0.1.0-test20261025.1 --output dist/linux-appimage-test
```

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
modificano browser reali. Sono stati superati i controlli runtime e ABI,
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
Snap dall'AppImage, cambio PIN e sblocco carta. La build corrente è una
versione di test x86_64: non copre ARM64 né costituisce una release binaria
pubblica completa. Prima della pubblicazione occorrono i materiali di
distribuzione descritti in [LICENSING.md](LICENSING.md), inclusi i sorgenti
corrispondenti delle dipendenze richiesti per il bundle effettivo.
