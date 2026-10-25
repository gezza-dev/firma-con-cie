# Flatpak Linux x86_64 di test

La distribuzione Flatpak è temporaneamente accantonata a favore
dell'[AppImage](LINUX_APPIMAGE.md). Questa ricetta conserva il lavoro
sperimentale e i relativi test; il componente browser esterno è stato
verificato con profili sintetici e non collaudato nell'accesso reale ai siti.

Il pacchetto locale usa l'identificativo `it.giancarloezza.FirmaConCIE.Test`,
ramo `test`, con nome nel menu «Firma con CIE (Flatpak test)». Può affiancare
l'installazione nativa. Questa ricetta assembla un bundle Release già compilato
e verificato; non è una proposta di pubblicazione su Flathub.

## Funzionalità e confini

GUI Flutter, middleware, SDK di firma, PDFium e DSS/JVM sono x86_64.
Il runtime `org.gnome.Platform//51` fornisce GTK e le librerie comuni;
il client PC/SC proviene dal sysroot Ubuntu 24.04, con avviso di licenza
incluso. Il lettore è gestito dal servizio `pcscd` del sistema, attraverso
il permesso `--socket=pcsc`. Il Flatpak non installa servizi o driver nel sistema.

La Home riconosce `/.flatpak-info` e usa un componente esterno facoltativo
per guidare la configurazione dei browser del sistema. L’installazione del
Flatpak non modifica i browser già configurati; vedere la sezione dedicata.

Su Wayland il runner usa una barra GTK. Mantiene una sola icona incorporata,
escludendo dal layout della barra l'ulteriore icona automatica di GTK e
conservando posizione e ordine dei pulsanti del desktop. Nel Flatpak legge
la preferenza chiaro/scuro dal portale `org.freedesktop.appearance` e osserva
le variazioni durante l'esecuzione. Il tema GTK installato decide i colori:
non vengono imposti colori RGB, preferenze globali o il passaggio a X11.
Se il portale non è disponibile, resta la preferenza GTK iniziale.

Preferenze e abbinamenti sono separati dall'app nativa. Il percorso storico
del backend `.local/share/it.giancarloezza.CIEID.FlutterPrototype.pairing.v1`
è reso persistente in una `.local` privata del Flatpak tramite
`--persist=.local`. Si mappa il primo livello per funzionare anche con una
home nuova, priva delle cartelle intermedie. Non viene condiviso l'archivio
reale dell'utente. Non vengono
importati abbinamenti o PIN preesistenti.

I documenti vengono scelti tramite il portale del desktop (`GTK_USE_PORTAL=1`),
senza concedere accesso all'intera home. Apertura, salvataggio e trascinamento
vanno collaudati anche nella sessione grafica dell'utente. Sono dichiarati
accesso grafico X11/Wayland, rendering, rete per i servizi di verifica,
PC/SC e Secret Service; non sono concessi `--filesystem=home`, accesso
indiscriminato ai dispositivi o esecuzione di comandi nel sistema host.

Il salvataggio supporta anche il portale che concede accesso a un singolo file:
quando la creazione della cartella di elaborazione non è consentita, il backend
Linux usa file temporanei esclusivi nel medesimo spazio del portale e pubblica
il risultato con una rinomina atomica. Non richiede accesso all'intero Desktop.
Restano vietate le sostituzioni non confermate e viene rilevata una modifica
concorrente del documento da sostituire; un'operazione interrotta non pubblica
il file temporaneo. macOS e Windows conservano il percorso di salvataggio attuale.

## Assemblaggio

Servono Flatpak, binutils e desktop-file-utils nell'ambiente di compilazione,
il runtime GNOME 51 x86_64 e i sorgenti dell'app. Per ricompilare la GUI con
l'identità separata impostare, nella copia di compilazione:

```sh
CIE_FLATPAK_APP_ID=it.giancarloezza.FirmaConCIE.Test \
  CMAKE_BUILD_PARALLEL_LEVEL=2 flutter build linux --release --no-pub
python3 scripts/package_linux_flatpak.py \
  --bundle build/linux/x64/release/bundle \
  --pcsc-library /usr/lib/x86_64-linux-gnu/libpcsclite.so.1 \
  --pcsc-license /usr/share/doc/libpcsclite1/copyright \
  --version 0.1.0-test20261024.4 \
  --output dist/linux-flatpak-test
```

Usare una cartella di output nuova. Il profilo dei permessi è in
`linux/flatpak/it.giancarloezza.FirmaConCIE.Test.json`.
Conservare manifest con checksum del contenuto e del client PC/SC, versione
e commit del runtime verificato, snapshot dei sorgenti e rapporti di test.
I programmi nativi e i JAR di test sono esclusi dal pacchetto finale.
Gli avvisi delle librerie rimangono inclusi; valgono i requisiti di
[LICENSING.md](LICENSING.md).

L'esportatore può disattivare solo la sandbox del validatore locale delle
icone quando gira in un ambiente di compilazione già isolato. Questo non
disattiva la sandbox dell'app distribuita, che va provata con `flatpak run`.

## Prova sul computer

Se Flatpak non è installato, su Ubuntu/Debian gli strumenti di esecuzione
si installano separatamente, con autenticazione amministrativa:

```sh
sudo apt install flatpak
```

Per aggiungere il repository dei runtime e installare il file di test nel
solo account corrente, eseguire personalmente:

```sh
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user /percorso/firma-con-cie-0.1.0-test20261024.4-x86_64.flatpak
flatpak run it.giancarloezza.FirmaConCIE.Test//test
```

Il file `.flatpak` non contiene il runtime GNOME: al primo avvio/installazione
può servire scaricarlo, insieme alle estensioni grafiche e linguistiche.
Non basta il file dell'app per garantire un'installazione offline.

I test software usano un'installazione Flatpak privata, home e D-Bus temporanei,
profili sintetici, nessun socket PC/SC reale e un display Xvfb. Le prove GUI
bloccano esplicitamente PC/SC. Nessuna prova reale sulla CIE viene eseguita
per preparare questo pacchetto; collaudi con carta e PIN sono passaggi separati.

Il test `output_staging` di CTest verifica pubblicazione e sostituzione su un
filesystem ordinario. `scripts/test_linux_flatpak_portal.py` esegue gli stessi
controlli nel vero portale documenti, con un documento sintetico e PC/SC bloccato.
Il test rimuove il solo permesso temporaneo creato per quel documento e non
apre l'app GUI, l'archivio degli abbinamenti o documenti personali. Il programma
di test resta esterno al pacchetto distribuito.

## Componente esterno per Firefox, Firefox Snap e Chrome

Dalla build `0.1.0-test20261024.4`, la Home può guidare la configurazione dei
browser del sistema tramite il pacchetto separato `firma-con-cie-browser-helper`.
Il componente è disponibile per x86_64 in formato `.deb`, `.rpm` e Arch.
Non è l'app nativa completa: contiene il provider PKCS#11, gli script già
collaudati e un servizio D-Bus della sessione utente. Il suo percorso è
`/opt/firma-con-cie-browser-helper`; il percorso nativo `/opt/firma-con-cie`
resta distinto. Il pacchetto non contiene la JVM o una seconda interfaccia.

L'installazione richiede un passaggio esplicito con il gestore dei pacchetti
del sistema, ad esempio `sudo apt install ./firma-con-cie-browser-helper_*.deb`.
Non avvia il componente, non registra moduli nei browser e non concede permessi
Snap. Occorrono Python 3.9+, PyGObject/GIO, gli strumenti NSS e PC/SC; i pacchetti
dichiarano le dipendenze specifiche della distribuzione. Questi pacchetti sono
per il collaudo; non sono stati installati durante la preparazione.

La Home segnala il componente assente. Dopo la sua installazione, «Rileggi»
rende disponibili gli stessi dialoghi per Firefox/Firefox Snap e Chrome,
mostrati solo quando servono. I profili non inizializzati e quelli già pronti
restano esclusi dalla selezione. Il browser deve essere chiuso prima della
conferma. Per Firefox Snap l'autorizzazione a `pcscd` è un'azione separata,
richiede conferma del sistema e non viene concessa dal pacchetto.

Il browser usa **sempre il PIN completo di otto cifre**. L'abbinamento nella
sandbox continua a permettere il PIN parziale per la firma nell'app; il
componente esterno non importa abbinamenti, prefissi del PIN o chiavi private.
Dalla Home riceve soltanto identificativo e certificato pubblico delle CIE già
abbinate e pronte, senza interpellare la carta. La pubblicazione di questi dati
avviene dopo la conferma della configurazione. Il certificato viene validato come
X.509 RSA 2048 prima della registrazione; nessuna operazione del componente
richiede il PIN o effettua tentativi di autenticazione.

Le registrazioni native già valide vengono riutilizzate: non sono riscritte
per puntare alla nuova cartella. Se manca soltanto il certificato pubblico,
la guida ne propone la preparazione lasciando invariato il modulo registrato.
Le nuove registrazioni usano il componente esterno; Firefox Snap riceve le
librerie nella propria cartella consentita, con generazione verificata e avvisi
di licenza. Non disinstallare il componente se un profilo ne usa ancora il
modulo; per rimuoverlo occorre prima riconfigurare esplicitamente quel profilo.

Il solo nuovo permesso Flatpak è la comunicazione con
`it.giancarloezza.FirmaConCIE.BrowserHelper1`. Non concede accesso ai file dei
profili o esecuzione generica sul sistema host. Il servizio accetta solo le
operazioni previste e richieste dallo stesso utente, limita dimensione e coda
dei messaggi e lega ogni conferma a un piano monouso di cinque minuti, alla
connessione chiamante e ai certificati pubblici. Verifica nuovamente i file
prima di scrivere e conserva i moduli estranei. È un servizio locale del
medesimo utente, non una barriera contro programmi ostili che già operano con
i suoi permessi. Non scrive certificati in `cert9.db`, chiavi in `key4.db` né
record privati di abbinamento: prepara esclusivamente il namespace pubblico
`web` dell'host o la cartella pubblica di Firefox Snap. Un errore dopo la
registrazione può lasciare il modulo registrato e la preparazione pubblica da
completare; il successivo controllo propone nuovamente il passaggio necessario.

Per costruire il componente, dopo la build nativa:

```sh
python3 scripts/package_linux_browser_helper.py \
  --runtime native/runtime/linux \
  --publisher .build/native-linux/cie_browser_public_certificate \
  --format deb --version 0.1.0~test20261024.1 \
  --output dist/linux-flatpak-browser-helper/deb
```

Usare `--format rpm` nell'ambiente Fedora e `--format arch` nell'ambiente Arch.
Il programma rifiuta utility compilate con l'override della cache di test.
Manifest e checksum accompagnano ogni pacchetto. I test software usano soltanto
HOME, profili, bus e certificati sintetici; il collaudo di accesso reale dal
Flatpak richiede un passaggio successivo con l'utente.
