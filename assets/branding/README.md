# Icone CIE ID

Icone derivate da quella di CIE ID Universal, nelle due varianti richieste:

- **Chiara:** base e sottile bordo del cerchio `#F7F8FC`, lo stesso sfondo
  della GUI chiara (`scaffoldBackgroundColor` in `lib/app_theme.dart`).
- **Scura:** base e bordo `#121318`, lo stesso sfondo della GUI scura
  (`ColorScheme.fromSeed`, seme `#4C65AD`, `scheme.surface`).

Il logo circolare occupa il 73% della base ed è centrato. Il blu e il bianco
del disegno rimangono quelli dell'asset precedente; la bordatura viene
composta con SVG, senza generare nuovamente il logo. La base è opaca; solo
gli angoli esterni sono trasparenti. Master raster a 1024 px in
`master/CIE-ID-light.png` e `master/CIE-ID-dark.png`, con sorgenti SVG in
`source`. I colori e le proporzioni sono definiti in `themes.json`.
I percorsi generici `CIE-ID.png`, `CIE-ID.icns` e `CIE-ID.ico` usano la
variante chiara per compatibilità.
Il riferimento originale rimane nel progetto precedente, senza modifiche.

- **macOS:** `macos/AppIcon.icon` è il formato nativo a livelli usato da Xcode
  26 o successivo: due aspetti nativi, predefinito chiaro e scuro, con sfondi
  opachi estesi a tutto il canvas e logo scalato al 73%. Le varianti della
  base e del cerchio sono associate alle apparenze del sistema nel documento
  `.icon`. Effetto vetro sul logo, ombre e traslucenza sono disattivati.
  La build genera le icone compatibili per i macOS precedenti. ICNS e iconset
  di entrambe le varianti sono in `macos/light` e `macos/dark`.
- **Windows:** `windows/light/CIE-ID.ico` e `windows/dark/CIE-ID.ico`, con
  immagini 16, 20, 24, 32, 40, 48, 64, 128 e 256 px nello stesso file.
  La risorsa `windows/runner/resources/app_icon.ico` usa la variante chiara.
- **Linux:** PNG da 16 a 1024 px in `linux/light/hicolor` e `linux/dark/hicolor`;
  la struttura generica `linux/hicolor` usa il tema chiaro. È incluso il
  file `.desktop`. L'icona della finestra GTK è incorporata come GResource;
  non dipende dalla directory da cui viene avviata l'app. La build copia
  icone e launcher in `share/icons` e `share/applications` del bundle.
  Nei pacchetti Linux il programma va installato nel PATH con nome `CIE-ID`;
  per un launcher di un bundle portabile, `Exec` deve indicare il suo percorso
  assoluto. Questi file non installano automaticamente nulla nel sistema.
  Il pacchetto locale di test generato da `scripts/package_linux_deb.py`
  installa il launcher in `/usr/share/applications` e i nove PNG chiari in
  `/usr/share/icons/hicolor`. Il comando `/usr/bin/CIE-ID` avvia il bundle
  privato in `/opt/cie-id-desktop`; application ID e nome del file `.desktop`
  coincidono anche su Wayland. [Procedura Linux](../../docs/LINUX_PACKAGE.md).

L'associazione automatica dei due aspetti è configurata per macOS. Gli ICO
dell'eseguibile Windows e il launcher Linux standard restano risorse statiche:
il solo set di file non attiva un cambio automatico delle icone di Explorer,
del menu Start o del launcher Linux al variare del tema. Entrambi i set sono
disponibili per le successive integrazioni specifiche di piattaforma.

Su macOS, l'impostazione delle icone è distinta dal tema delle finestre e
da quello selezionato nelle Preferenze di CIE ID. In **Impostazioni di Sistema
→ Aspetto → Stile icone e widget**, **Default** mantiene l'icona chiara anche
con finestre scure. Per seguire l'aspetto di macOS scegliere **Scuro →
Automatico**; **Scuro → Sempre** mantiene invece le icone scure. Questa è
una preferenza globale per tutte le app e i widget, che CIE ID non modifica.
[Riferimento Apple](https://support.apple.com/guide/mac-help/change-appearance-settings-mchlp1225/mac).

Per rigenerare i formati dal master raster già presente (anche su Windows/Linux):

```sh
python3 -m venv /tmp/cie-icon-tools
/tmp/cie-icon-tools/bin/python -m pip install 'Pillow>=10'
/tmp/cie-icon-tools/bin/python scripts/generate_app_icons.py
```

Lo script ridimensiona e converte il master, aggiorna le risorse dei runner,
scrive i checksum in `manifest.json` e crea `dist/branding/CIE-ID-icons.zip`.
Non rigenera il disegno con l'AI e non richiede credenziali.

Per ricreare anche il PNG master dal sorgente SVG su macOS:

```sh
/tmp/cie-icon-tools/bin/python scripts/generate_app_icons.py --render-source
```

La composizione modificabile usa un rettangolo 1024 × 1024 con raggio
224 e il cerchio a x/y 138,24, dimensioni 747,52 × 747,52. Il file `.icon`
usa lo stesso rapporto dimensionale ma lascia la maschera finale al sistema,
come richiesto da Apple, evitando il riempimento di compatibilità grigio
delle vecchie icone irregolari. La versione PNG non incorpora riflessi.

## Aspetto applicato dal sistema

Le due basi usano esplicitamente i colori della GUI; non viene richiesto uno
sfondo di compatibilità grigio automatico. macOS può comunque applicare
un sottile riflesso sul perimetro dell'icona e altri effetti di presentazione.
Gli stili monocromatici, colorati o trasparenti scelti dall'utente nel sistema,
così come temi o launcher di terzi, possono modificare l'aspetto finale:
l'app non può garantire che ogni pixel visualizzato mantenga il colore sorgente
con tali stili.
Riferimenti: [Apple, adozione di Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass),
[Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Provenienza e modifica grafica

Il master deriva da `CIE ID/Assets.xcassets/AppIcon.appiconset/icon_512@2x.png`
del progetto CIE ID Universal, basato sul middleware originale IPZS.
Provenienza e hash del riferimento sono in `provenance.json`.
Il disegno originale mantiene copyright e condizioni della licenza originale
BSD-3-Clause, riprodotta in `LICENSE-upstream.txt`. La modifica non implica
approvazione o supporto da parte di IPZS.

Il cerchio con bordo nero è stato modificato in precedenza con lo strumento
integrato **image_gen**; il relativo prompt è in `imagegen-prompt.txt`.
La composizione definitiva della base e delle proporzioni è deterministica,
tramite SVG e il documento nativo `.icon`; non è stata rigenerata con l'AI.
Il riferimento originale resta disponibile per il confronto.
