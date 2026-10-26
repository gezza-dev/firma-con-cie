# Pacchetto Linux .deb

Il pacchetto locale `firma-con-cie` contiene l'app Flutter e il runtime
nativo, con launcher e icone. Il primo assemblaggio è per Ubuntu 26.10 amd64.
Dal test `.19` è disponibile anche un bundle ricompilato su Ubuntu 24.04 LTS,
con il `.deb` verificato in Ubuntu 24.04 e Debian 13. Sono disponibili anche
ricette native Fedora e Arch: [matrice e collaudi](LINUX_DISTRIBUTION_PACKAGES.md).
Le dipendenze minime sono calcolate con `dpkg-shlibdeps` su tutti gli ELF
distribuiti, inclusi i moduli caricati dinamicamente. Il controllo ABI core24
del provider Firefox è distinto dalla compatibilità dell'intero desktop.
EGL/OpenGL/GLES, caricati dinamicamente all'avvio, sono dipendenze esplicite
oltre a quelle determinate dall'analisi degli ELF.
La versione `1.0.0` è preparata per la prima release del progetto, da
pubblicare separatamente. I materiali sorgente/dipendenze sono descritti
in [LICENSING.md](LICENSING.md).
Il pacchetto può includere il runtime DSS/LTA Linux x86_64 con JVM privata,
se presente nel bundle di ingresso. Il packager ne controlla architettura,
eseguibili e hash e calcola anche le dipendenze delle librerie Java.
Programmi di test nativi e JAR di test DSS sono esclusi.
[Build e collaudi DSS/LTA](LINUX_DSS_LTA.md).

La build ARM64 usa una JVM privata e binari AArch64; il `.deb` amd64
rimane separato. [Preparazione e collaudi ARM64](LINUX_ARM64.md).

I file `.deb` usano il nome pubblico `firma-con-cie`, per esempio
`firma-con-cie_1.0.0_arm64.deb`. L’identificativo interno del pacchetto è
`firma-con-cie`, usato da APT/dpkg per gestire gli aggiornamenti.
La prima installazione con questo identificativo è pulita: rimuovere dal
gestore pacchetti l'eventuale precedente versione dell'app prima di installare
il nuovo file. Non sono previsti alias o metadati di migrazione. La rimozione
ordinaria non cancella abbinamenti, preferenze o documenti personali.

## Assemblaggio senza installazione

Richiede un bundle release completo già compilato, `dpkg-dev`, `binutils` e
`desktop-file-utils`. Non richiede root. Esempio dalla radice del repository:

```sh
python3 scripts/package_linux_deb.py \
  --bundle build/linux/x64/release/bundle \
  --output dist/linux-deb \
  --version '1.0.0'
```

Usare una directory di output nuova. Lo script verifica gli hash del runtime,
il tipo/architettura dei binari e il launcher. Produce `.deb`, `SHA256SUMS`,
manifest del contenuto e log delle dipendenze. Le versioni seguono il formato
`MAJOR.MINOR.PATCH`, senza suffissi. Il pacchetto non viene installato né avviato durante l'assemblaggio.

## Installazione e percorsi

Per il successivo collaudo manuale, nella directory del `.deb`:

```sh
sudo apt install ./firma-con-cie_1.0.0_amd64.deb
```

- App e librerie private: `/opt/firma-con-cie`.
- Comando di avvio: `/usr/bin/Firma con CIE`; conserva lingua e ambiente del desktop.
- Voce nel menu: **Firma con CIE**, con lo stesso application ID GTK/Wayland del
  file `.desktop` in `/usr/share/applications`.
- Icone statiche chiare: `/usr/share/icons/hicolor`, da 16 a 1024 pixel.
  Le varianti scure restano nei sorgenti; il launcher non cambia icona con il tema.
- Avvisi e documentazione: `/usr/share/doc/firma-con-cie` e
  `/opt/firma-con-cie/cie_native/licenses`.

La documentazione inclusa comprende anche `STATUS.md` e
`WEB_AUTHENTICATION.md`, con lo stato dei collaudi e il comportamento degli
avvisi di accesso ai siti sulle tre piattaforme. Il controllo del pacchetto
confronta questi due documenti con i sorgenti correnti.

L'installer non avvia app o browser, non configura moduli, non modifica permessi
Snap e non legge o cancella gli abbinamenti. Le cache di sistema del menu/icone
sono gestite dai normali trigger della distribuzione. Rimuovere il pacchetto con
`sudo apt remove firma-con-cie`; i dati personali dell'utente restano presenti.
Il collaudo automatico usa un database dpkg separato senza installare sull'host;
la verifica visiva del menu e dell'icona resta un passaggio manuale.

Il 20 ottobre 2026 il pacchetto `0.1.0~test20261020.1` è stato installato anche
sull'host Ubuntu 26.10 amd64 KDE/Wayland. Installazione e hash verificati;
launcher registrato nel menu Accessori e icona risolta dal tema KDE. L'utente
ha confermato visivamente voce e icona corrette nel menu. L'agente non ha avviato
l'app né eseguito nuove prove CIE o modifiche ai collegamenti Snap o al browser.
Durante le verifiche è stato rilevato un processo dal percorso installato; non è stata
eseguita interazione con l'app o la carta durante la verifica.
Il controllo della finestra/taskbar e il collaudo GNOME restano separati.

## Adattamento della finestra GNOME/KDE

La versione `0.1.0~test20261020.2` sostituisce la finestra Linux fissa con
1280×720 come dimensione preferita, ridimensionabile. Il runner usa l'area
utile del monitor in coordinate logiche GTK, riservando spazio alla barra del
titolo e un margine. Non applica nuovamente lo scaling del monitor né cambia
la scala dei caratteri. Se lo spazio è insufficiente richiede la massimizzazione
al gestore finestre, senza usare lo schermo intero: GNOME/KDE gestiscono così
i pannelli anche quando Wayland non espone un'area utile completa.
La finestra si adatta ai cambi di monitor, area utile e risoluzione; una
finestra già ridotta manualmente viene conservata se entra nella nuova area.

Test software: sette casi nativi del runner (dimensioni e scala del testo),
200 test Flutter superati e tre test di runtime facoltativi saltati, analisi
senza problemi. Sei nuovi scenari verificano tutte le pagine da 640×400,
caratteri fino al 200% e display al 200%, con dialogo scorrevole e pulsante
raggiungibile. La lettura separata del monitor GNOME/Wayland locale rileva
1280×800 logici, area utile 1213×771 e fattore display 2: nessuna finestra
è stata aperta per questa lettura. Il collaudo visivo della versione aggiornata
resta manuale; la preparazione del pacchetto non aggiorna l'app installata.

Nella successiva prova manuale del 20 ottobre 2026 l'utente ha confermato
l'installazione e l'esito positivo dell'adattamento automatico nel contesto
GNOME. Versione installata `0.1.0~test20261020.2` e integrità del pacchetto
verificate tramite dpkg. L'esito della finestra è una conferma dell'utente;
l'agente non ha avviato l'app o altre prove sulla CIE. La verifica visiva su
KDE della finestra aggiornata e i cambi di monitor restano prove distinte.

## Cambio della cartella dell’app

I pacchetti usano `/opt/firma-con-cie` e l'identificativo `firma-con-cie`.
Gli aggiornamenti successivi della stessa identità sono gestiti da apt/dpkg;
una precedente distribuzione con identità diversa va prima disinstallata.
Non si creano collegamenti di compatibilità. Abbinamenti, impostazioni e
immagini dell’utente conservano i percorsi precedenti nella home.
L’installer non cancella o riconfigura alcun profilo browser: i moduli che
puntavano alla vecchia cartella richiedono una nuova configurazione dell’utente.

La barra GTK su GNOME/Wayland mostra a sinistra l’icona incorporata nell’app,
alla dimensione logica di 24 px; GTK gestisce lo scaling. Su X11 con decorazione
gestita dal window manager viene fornita l’icona della finestra: posizione e
visibilità dipendono dal tema del desktop. Non si cambiano le preferenze del
window manager né le dimensioni massime della finestra.

## Modulo Firefox e Firefox Snap

**Configura Firefox** offre una procedura
per Firefox desktop e Firefox Snap. Il riquadro compare solo in cima alla
Home quando occorre intervenire sulla configurazione o sul permesso
Snap; i profili non inizializzati sono esclusi dall'elenco e dall'avviso.
La procedura prevede scelta del profilo, riepilogo
e conferma finale. Per Snap vengono copiate soltanto tre librerie in una
generazione privata; il permesso del lettore richiede una seconda conferma.
La procedura non richiede carta/PIN e non esegue login. Il `.deb` include
helper e guardia PC/SC, con dipendenze Python 3 e `libnss3-tools`.
L'installazione del pacchetto non esegue la procedura né configura browser.
[Istruzioni e limiti del nuovo wizard](LINUX_FIREFOX_SETUP.md).

Google Chrome desktop usa lo stesso provider con una registrazione NSS
distinta. **Configura Chrome** offre la procedura
nell’app con riepilogo e conferma esplicita, senza richiedere carta/PIN.
Il riquadro compare solo nella Home quando la configurazione richiede attenzione.
Nessuna delle due procedure è presente nella pagina Impostazioni.
Il pacchetto include l’helper Chrome e la stessa guardia PC/SC di Firefox;
l’installer non modifica browser. Resta disponibile l’alternativa da terminale in
`/usr/share/doc/firma-con-cie/tools/configure_chrome_linux.py`: senza opzioni
mostra soltanto il piano. L'installer non la esegue. Dopo l'installazione del
pacchetto `0.1.0~test20261023.2` e la registrazione esplicita, l'utente ha
confermato il 23 ottobre 2026 il login reale Chrome Linux riuscito con PIN
completo. Firefox non è stato modificato. [Istruzioni e limiti](LINUX_CHROME.md).

Per Firefox non confinato, il percorso installato stabile è:

```text
/opt/firma-con-cie/cie_native/libcie_linux_pkcs11.so
```

Firefox Snap non ha automaticamente accesso al runtime installato in `/opt`.
Il modulo già registrato dal bundle di sviluppo rimane su quel percorso.
Come alternativa manuale al wizard, per usare il runtime del pacchetto con Snap, chiudere Firefox e copiare
esplicitamente le sole tre librerie in un percorso stabile accessibile:

```sh
mkdir -p "$HOME/snap/firefox/common/firma-con-cie-module-v1"
chmod 700 "$HOME/snap/firefox/common/firma-con-cie-module-v1"
install -m 600 /opt/firma-con-cie/cie_native/libcie_linux_pkcs11.so \
  /opt/firma-con-cie/cie_native/libcie_web.so \
  /opt/firma-con-cie/cie_native/libcie-pkcs11.so \
  "$HOME/snap/firefox/common/firma-con-cie-module-v1/"
```

Caricare manualmente `libcie_linux_pkcs11.so` da questa directory in Firefox.
La copia del modulo va aggiornata esplicitamente dopo un aggiornamento del
pacchetto, sempre a browser chiuso. Non copiare altri file o la cache privata
dell'app. Il DER pubblico e l'autorizzazione `pcscd` seguono la procedura in
[LINUX_FIREFOX.md](LINUX_FIREFOX.md); il PIN richiesto resta quello completo.
