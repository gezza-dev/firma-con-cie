# Icone Firma con CIE — documento e firma

Il nuovo simbolo dell’app è un documento blu con pennino e tratto di firma
verde chiaro: la **proposta B** scelta dal responsabile del progetto.
Il disegno è stato generato con lo strumento integrato OpenAI **image_gen**;
non utilizza il logo dell’app ufficiale CIE ID/IPZS.

La stessa immagine del documento e del pennino è composta su due basi:

- **Chiara:** `#F7F8FC`, come lo sfondo dell’interfaccia chiara.
- **Scura:** `#121318`, come lo sfondo dell’interfaccia scura.

Il canvas è di 1024 × 1024 px, il raggio degli angoli è di 224 px e il
livello del simbolo è scalato all’88%. La base è opaca; gli angoli esterni
sono trasparenti. La composizione non aggiunge una seconda cornice o un
riquadro grigio. Le proporzioni e i colori sono fissati in `themes.json`.
I sorgenti SVG incorporano il PNG del simbolo: la composizione è modificabile,
mentre il disegno interno resta raster.

## File sorgenti e formati

- `source/selected-proposal-B.png`: proposta selezionata, conservata come
  riferimento visivo; non è la risorsa usata dai runner.
- `source/document-signature.png`: documento, pennino e firma su trasparenza.
- `source/firma-con-cie-light.svg` e `source/firma-con-cie-dark.svg`: composizioni complete.
- `master/firma-con-cie-light.png` e `master/firma-con-cie-dark.png`: master a 1024 px.
- **macOS:** `macos/AppIcon.icon`, catalogo nativo con simbolo e basi separati,
  copiato anche in `macos/Runner/AppIcon.icon`. Le varianti chiara e scura
  sono associate alle apparenze del sistema. ICNS e iconset da 16 a 1024 px
  sono in `macos/light` e `macos/dark`. Il catalogo PNG del runner è aggiornato
  per la compatibilità; vetro e traslucenza dei livelli sono disabilitati.
- **Windows:** `windows/light/firma-con-cie.ico` e `windows/dark/firma-con-cie.ico`, ciascuno
  con immagini da 16, 20, 24, 32, 40, 48, 64, 128 e 256 px. La risorsa
  `windows/runner/resources/app_icon.ico` dell’eseguibile usa il tema chiaro.
- **Linux:** PNG da 16, 24, 32, 48, 64, 128, 256, 512 e 1024 px nelle cartelle
  `linux/light/hicolor` e `linux/dark/hicolor`. `linux/hicolor` e la GResource
  `linux/resources/cie-id.png` usano il tema chiaro. Il launcher `.desktop`
  mantiene il suo application ID, anche su Wayland. La build e il pacchetto
  `.deb` includono icone e launcher; [procedura Linux](../../docs/LINUX_PACKAGE.md).

I percorsi generici `firma-con-cie.png`, `firma-con-cie.icns` e `firma-con-cie.ico`
usano il nome attuale dell'app e il disegno nella variante chiara.

## Selezione del tema

Il catalogo macOS include la selezione nativa dell’aspetto. Il tema delle
icone dipende dalle impostazioni del sistema, separatamente dal tema delle
finestre e dalle Preferenze dell’app. L’impostazione globale **Stile icone e
widget → Scuro → Automatico** consente alle icone di seguire l’aspetto di
macOS; questa applicazione non la modifica.

Le icone incorporate nell’EXE Windows e nei launcher Linux standard sono
statiche. Entrambi i set sono forniti, ma un file ICO o PNG aggiuntivo non
attiva da solo il cambio automatico in Explorer, nel menu Start o nel launcher.
Le eventuali personalizzazioni grafiche del sistema possono modificare
l’aspetto finale delle icone.

## Rigenerazione

Con Python e Pillow 10 o successivo, da Windows, Linux o macOS:

```sh
python scripts/generate_app_icons.py
```

Lo script usa i master PNG già presenti, aggiorna i formati nativi e le
risorse dei runner, registra SHA-256 in `manifest.json` e crea l’archivio
`dist/branding/firma-con-cie-icons.zip`. Non richiede credenziali né nuove
operazioni di generazione con l’AI.

Per ricreare anche i master PNG dalle composizioni SVG su macOS:

```sh
python3 scripts/generate_app_icons.py --render-source
```

## Provenienza e termini

I prompt di generazione ed estrazione del simbolo sono in
`imagegen-prompt.txt`; gli hash degli originali e la geometria sono in
`provenance.json`. Disegno e formati esportati sono messi a disposizione
con i termini BSD-3-Clause, nella misura applicabile, riportati in
`LICENSE.txt`. L’avviso distribuito con l’app è in
`assets/licenses/cie-app-icon-NOTICE.txt`, con il relativo testo integrale
`cie-app-icon-LICENSE.txt`.

Il precedente logo ufficiale non è incluso in questi set. La miniatura della
carta mostrata all’interno dell’app è una risorsa distinta e conserva
l’[attribuzione originale](../licenses/cie-card-NOTICE.txt).
