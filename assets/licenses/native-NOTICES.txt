# Avvisi e attribuzioni di terze parti

Fork indipendente di `italia/cie-middleware-macos`, basato sul commit
`43da456fb3002e34beccda73b9bc4b149acae534`. Non è un prodotto ufficiale,
approvato o supportato da IPZS. Verifica effettuata il 15 ottobre 2026.

Questa raccolta accompagna i sorgenti e le build di lavoro. La presenza di
un avviso non risolve una licenza mancante né autorizza una combinazione di
licenze incompatibili. Le condizioni sono descritte in
[LICENSE_AUDIT.md](LICENSE_AUDIT.md).

## Progetto originale e codice incorporato

Copyright (c) 2017, Istituto Poligrafico e Zecca dello Stato.
All rights reserved. Licenza principale:
[BSD 3-Clause](LICENSES/upstream/LICENSE.txt).
I copyright individuali e gli avvisi nei file originali restano applicabili.

| Componente | Licenza o evidenza | Testo incluso |
| --- | --- | --- |
| Logger rxi / log.c | MIT, copyright (c) 2020 rxi | [LICENSE](LICENSES/rxi-log/LICENSE) |
| Utility UUC nel middleware e nell'SDK | LGPL 2.0 o successiva nei file che lo dichiarano | [LGPL](LICENSES/gnu/COPYING.LIB); avvisi nei sorgenti |
| TestCIE, utility di test separata esclusa dal bundle dell'app | GPL 2.0 o successiva | [GPL](LICENSES/gnu/COPYING); avvisi nei sorgenti |
| Adattatori hash/RSA, reader ed eccezioni ASN.1 e tabella proprietà del fork | BSD 3-Clause | SPDX nei nuovi sorgenti; [BSD](LICENSE.txt) |
| Base64 di Philip Busch | BSD 2-Clause, copyright (c) 2006–2007 Philip Busch | [Avviso originale](LICENSES/embedded-sdk/base64-notice.txt) |
| RC2 di Kungliga Tekniska Högskolan | BSD 3-Clause, copyright (c) 2004 KTH | [Avviso originale](LICENSES/embedded-sdk/rc2.c-notice.txt) |
| Header PKCS#11 | Permesso specifico di copia, uso e derivazione | [Avviso originale](LICENSES/embedded-sdk/pkcs11-notice.txt) |
| C++ Big Integer Library di Matt McCutchen | Dominio pubblico dichiarato dall'autore; copia incorporata con adattamenti | [README upstream](LICENSES/bigint/README.txt) |

L'inventario dei file con dichiarazioni esplicite è in
`scripts/embedded-license-inventory.json`. Non assegna la licenza BSD ai file
che dichiarano altri termini e non costituisce una ricostruzione completa
della titolarità di tutti i file.

## Dipendenze della build nativa

I sorgenti sono identificati da URL, versione e SHA-256 nei lockfile
`scripts/dependencies.lock.json` e `scripts/app-dependencies.lock.json`.
I testi qui inclusi provengono dagli archivi con quei checksum.

| Dipendenza | Versione | Licenza e testi |
| --- | --- | --- |
| OpenSSL | 3.5.9 LTS | [Apache License 2.0](LICENSES/openssl/LICENSE.txt), [autori e titolari](LICENSES/openssl/AUTHORS.md) |
| Crypto++ | 8.9.0 | [File in dominio pubblico, compilazione Boost 1.0 e avvisi CRYPTOGAMS](LICENSES/cryptopp/License.txt) |
| PoDoFo | 1.1.2 LTS | [MPL 2.0 scelta per questa build](LICENSES/podofo/COPYING.MPL), [alternativa LGPL](LICENSES/podofo/COPYING.LGPL), [NOTICE upstream](LICENSES/podofo/NOTICE) |
| zlib | 1.3.2 | [zlib](LICENSES/zlib/LICENSE) |
| bzip2 | 1.0.8 | [Termini bzip2](LICENSES/bzip2/LICENSE) |
| GNU libiconv e libcharset | 1.19 | [LGPL 2.1 o successiva](LICENSES/libiconv/COPYING.LIB), [libcharset](LICENSES/libiconv/libcharset--COPYING.LIB) |
| Expat | 2.9.0 | [MIT](LICENSES/expat/expat--COPYING) |
| libpng | 1.6.59 | [PNG Reference Library License e avvisi storici](LICENSES/libpng/LICENSE) |
| FreeType | 2.14.3 | [FTL scelta per questa build](LICENSES/freetype/LICENSE.TXT), [FTL](LICENSES/freetype/docs--FTL.TXT), [GPL](LICENSES/freetype/docs--GPLv2.TXT); avvisi BDF/PCF/hash nella stessa cartella |
| fontconfig | 2.18.3 | [Termini permissivi e avvisi per i sottocomponenti](LICENSES/fontconfig/COPYING) |
| Tabelle Unicode di fontconfig | CaseFolding 17.0.0 | [Avviso della copia 2025](LICENSES/unicode/CaseFolding-17.0.0-notice.txt), [Unicode License V3 pubblicata dal titolare](LICENSES/unicode/Unicode-LICENSE-V3.txt) |
| libxml2 | 2.15.4 | [MIT e avvisi di file con copyright distinti](LICENSES/libxml2/COPYING); avvisi hash/list/dict nella stessa cartella |
| curl | 8.23.0 | [curl license](LICENSES/libcurl/COPYING) |
| SSZipArchive | 2.6.0 | [MIT](LICENSES/ssziparchive/LICENSE.txt) |
| minizip incorporato in SSZipArchive | Copia del tag SSZipArchive 2.6.0 | [zlib](LICENSES/ssziparchive/SSZipArchive--minizip--LICENSE), [copyright dei contributori](LICENSES/ssziparchive/minizip-copyrights.txt) |

Gli header storici Crypto++ 7.0/8.2 sono rimossi: la build utilizza soltanto
Crypto++ 8.9.0. I percorsi e i checksum dei 338 header rimossi sono in
`scripts/removed-legacy-cryptopp-headers.json`. Il testo storico di licenza
7.0 è conservato per attribuzione della precedente importazione.

### Componenti incorporati in PoDoFo 1.1.2

This product includes software developed by the PoDoFo Project
(https://github.com/podofo/podofo).

Per la libreria PoDoFo è selezionata MPL 2.0; i sorgenti esatti sono inclusi
nel pacchetto corrispondente. Gli strumenti GPL di PoDoFo non sono compilati.
AFDKO è disabilitato; i relativi avvisi sono conservati per i sorgenti upstream.

| Componente | Licenza e testi |
| --- | --- |
| Chromium Numerics / PDFium | [BSD](LICENSES/podofo/3rdparty--chromium--numerics--LICENSE), [PDFium BSD e Apache](LICENSES/podofo/3rdparty--chromium--pdfium--LICENSE) |
| Adobe AFDKO | [Apache 2.0](LICENSES/podofo/3rdparty--adobe--afdko--LICENSE) |
| fmt | [MIT e avviso originale](LICENSES/podofo/fmt-notice.txt) |
| fast_float | [MIT scelta, con alternative e copyright upstream](LICENSES/podofo/fast-float-notice.txt) |
| Howard Hinnant date | [MIT](LICENSES/podofo/date-notice.txt) |
| utf8proc | [MIT](LICENSES/podofo/utf8proc-notice.txt), [Unicode](LICENSES/unicode/Unicode-LICENSE-V3.txt) |
| utf8cpp | [Boost 1.0 e copyright Nemanja Trifunovic](LICENSES/podofo/utf8cpp-notice.txt) |
| tcb-span | [Boost 1.0](LICENSES/podofo/Boost-LICENSE-1.0.txt), [copyright Tristan Brindle](LICENSES/podofo/span-notice.txt) |
| SASLprep | [MIT, copyright Francesco Pretto](LICENSES/podofo/SASLprep-notice.txt); testo MIT in [fmt](LICENSES/podofo/fmt-notice.txt) |
| LiberaLean, derivato Liberation | [SIL OFL 1.1, titolari e nomi riservati](LICENSES/podofo/src--podofo--private--LiberaLean--LICENSE.txt) |
| Font Foxit/PDFium | [provenienza e copyright](LICENSES/podofo/src--podofo--private--FoxitFonts--COPYING.txt), [licenza PDFium](LICENSES/podofo/3rdparty--chromium--pdfium--LICENSE) |

## Attribuzioni OpenSSL e FreeType

OpenSSL 3.5.9 usa Apache License 2.0. Il testo integrale e l'elenco di autori
per i copyright sono inclusi; l'archivio ufficiale non contiene un file
NOTICE alla radice. Non sono state riscritte le sue intestazioni.
Gli header vendored OpenSSL 1.x inutilizzati sono rimossi dallo snapshot;
non sono input della build né componenti dell'app nuova.

> Portions of this software are copyright © 1996–2026 The FreeType Project
> (www.freetype.org). All rights reserved.

Per questa build si sceglie FreeType License (FTL). Il testo dell'alternativa
GPL resta incluso per completezza della distribuzione upstream, senza
applicarlo alla build del fork. Vedere `LICENSES/freetype/LICENSE.TXT`.

## Font e risorse

Il font incorporato è Allura-Regular, versione 1.005:

Copyright (c) 2011 TypeSETit, LLC (typesetit@att.net),
with Reserved Font Name "Allura".

Autore: Robert E. Leuschke. Il font dichiara nei propri metadati la
[SIL Open Font License 1.1](LICENSES/allura/OFL-1.1.txt).
L'[avviso della copia effettiva](LICENSES/allura/COPYRIGHT.txt) è conservato;
il font non è stato modificato dal fork. Non vendere il font da solo; per
modifiche al font rispettare le condizioni sul Reserved Font Name.

Le risorse grafiche e i nomi CIE/IPZS conservati dall'upstream sono
attribuzioni storiche. Non devono essere presentati come approvazione del
fork. L'audit non attesta una concessione generale dei diritti sui marchi.

## Redistribuzione

Conservare questi avvisi e tutti i testi in `LICENSES/` insieme ai sorgenti.
La build Xcode include entrambi nelle risorse di app ed estensione prima
della firma. Le copie finali in `dist/` mantengono i medesimi avvisi.

Per componenti GPL/LGPL, i testi di licenza non sostituiscono gli obblighi
di fornire i sorgenti corrispondenti, le modifiche e, quando richiesto, ciò
che permette la ricompilazione o il ricollegamento. Per i dettagli e i punti
di distribuzione consultare `LICENSE_AUDIT.md` e `Docs/PUBLICATION.md`.
