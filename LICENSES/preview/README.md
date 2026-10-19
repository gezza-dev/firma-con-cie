# Avvisi anteprima e trascinamento

Generati da scripts/prepare_preview.py da pacchetti risolti in pubspec.lock e
archivi verificati con native/preview/pdfium.lock.json. manifest.json registra
archivi, checksum delle librerie e file di avviso. La cartella dart contiene
le licenze dei pacchetti risolti, inclusi pdfrx/MIT e desktop_drop/Apache-2.0.
Flutter include anche NOTICES.Z nel bundle.

PDFium mantiene BSD-3-Clause e le licenze individuali dei componenti incorporati.
Gli archivi Windows e Linux dello stesso ramo chromium/7811 includono le licenze
upstream e dei terzi, conservate integralmente. L'XCFramework Darwin pubblicato
non include testi di licenza propri: sono inclusi gli avvisi PDFium disponibili
negli altri archivi e quelli dei pacchetti Flutter, senza attribuire una nuova
licenza ai binari. Prima di una futura distribuzione pubblica del prototipo,
verificare anche la copertura degli avvisi della specifica build Darwin.

Questa raccolta documenta la provenienza tecnica e non sostituisce una revisione
legale delle condizioni di distribuzione del prodotto completo.
