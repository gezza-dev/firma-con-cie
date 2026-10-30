# Avvisi anteprima e trascinamento

Generati da scripts/prepare_preview.py da pacchetti risolti in pubspec.lock e
archivi verificati con native/preview/pdfium.lock.json. manifest.json registra
archivi, checksum delle librerie e file di avviso. La cartella dart contiene
le licenze dei pacchetti risolti, inclusi pdfrx/MIT e desktop_drop/Apache-2.0.
Flutter include anche NOTICES.Z nel bundle.

PDFium mantiene BSD-3-Clause e le licenze individuali dei componenti incorporati.
Gli archivi Windows e Linux dello stesso ramo chromium/7811 includono le licenze
upstream e dei terzi, conservate integralmente. L'XCFramework Darwin pubblicato
non include testi di licenza propri. Per Darwin sono conservati anche i testi
originali dei due archivi Mac ARM64/x64 usati dal suo costruttore, sotto
`darwin-universal/`. URL, checksum e commit del costruttore sono fissati in
`native/preview/darwin-notices.lock.json`; `prepare_preview.py` li verifica e
registra gli hash dei testi nel manifest. Il confronto delle sezioni Mach-O
con il framework Universal della build fissata conferma la corrispondenza
dei due binari, a parte metadati di caricamento e firma. Non vengono usati
gli avvisi Windows/Linux come sostituti degli avvisi specifici Mac.

Questa raccolta documenta la provenienza tecnica e non sostituisce una revisione
legale delle condizioni di distribuzione del prodotto completo.
