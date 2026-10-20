# Pacchetto Linux .deb di test

Il pacchetto locale `cie-id-desktop` contiene l'app Flutter e il runtime
nativo, con launcher e icone. Il primo assemblaggio è per Ubuntu 26.10 amd64.
Le dipendenze minime sono calcolate con `dpkg-shlibdeps` su tutti gli ELF
distribuiti, inclusi i moduli caricati dinamicamente. Il controllo ABI core24
del provider Firefox è distinto dalla compatibilità dell'intero desktop.
Non è ancora una release binaria da redistribuire: il completamento dei
materiali sorgente/dipendenze è descritto in [LICENSING.md](LICENSING.md).
Il runtime Linux DSS/LTA e i programmi di test nativi non sono inclusi.

## Assemblaggio senza installazione

Richiede un bundle release completo già compilato, `dpkg-dev`, `binutils` e
`desktop-file-utils`. Non richiede root. Esempio dalla radice del repository:

```sh
python3 scripts/package_linux_deb.py \
  --bundle dist/linux-window-fit-software \
  --output dist/linux-window-fit-deb-test \
  --version '0.1.0~test20261020.2'
```

Usare una directory di output nuova. Lo script verifica gli hash del runtime,
il tipo/architettura dei binari e il launcher. Produce `.deb`, `SHA256SUMS`,
manifest del contenuto e log delle dipendenze. Le versioni devono contenere
`~test`. Il pacchetto non viene installato né avviato durante l'assemblaggio.

## Installazione e percorsi

Per il successivo collaudo manuale, nella directory del `.deb`:

```sh
sudo apt install ./cie-id-desktop_0.1.0~test20261020.2_amd64.deb
```

- App e librerie private: `/opt/cie-id-desktop`.
- Comando di avvio: `/usr/bin/CIE-ID`; conserva lingua e ambiente del desktop.
- Voce nel menu: **CIE ID**, con lo stesso application ID GTK/Wayland del
  file `.desktop` in `/usr/share/applications`.
- Icone statiche chiare: `/usr/share/icons/hicolor`, da 16 a 1024 pixel.
  Le varianti scure restano nei sorgenti; il launcher non cambia icona con il tema.
- Avvisi e documentazione: `/usr/share/doc/cie-id-desktop` e
  `/opt/cie-id-desktop/cie_native/licenses`.

L'installer non avvia app o browser, non configura moduli, non modifica permessi
Snap e non legge o cancella gli abbinamenti. Le cache di sistema del menu/icone
sono gestite dai normali trigger della distribuzione. Rimuovere il pacchetto con
`sudo apt remove cie-id-desktop`; i dati personali dell'utente restano presenti.
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

## Modulo Firefox e Firefox Snap

Per Firefox non confinato, il percorso installato stabile è:

```text
/opt/cie-id-desktop/cie_native/libcie_linux_pkcs11.so
```

Firefox Snap non ha automaticamente accesso al runtime installato in `/opt`.
Il modulo già registrato dal bundle di sviluppo rimane su quel percorso.
Per usare il runtime del pacchetto con Snap, chiudere Firefox e copiare
esplicitamente le sole tre librerie in un percorso stabile accessibile:

```sh
mkdir -p "$HOME/snap/firefox/common/cie-id-module-v1"
chmod 700 "$HOME/snap/firefox/common/cie-id-module-v1"
install -m 600 /opt/cie-id-desktop/cie_native/libcie_linux_pkcs11.so \
  /opt/cie-id-desktop/cie_native/libcie_web.so \
  /opt/cie-id-desktop/cie_native/libcie-pkcs11.so \
  "$HOME/snap/firefox/common/cie-id-module-v1/"
```

Caricare manualmente `libcie_linux_pkcs11.so` da questa directory in Firefox.
La copia del modulo va aggiornata esplicitamente dopo un aggiornamento del
pacchetto, sempre a browser chiuso. Non copiare altri file o la cache privata
dell'app. Il DER pubblico e l'autorizzazione `pcscd` seguono la procedura in
[LINUX_FIREFOX.md](LINUX_FIREFOX.md); il PIN richiesto resta quello completo.
