# Licenze, provenienza e distribuzione

Questo documento riguarda lo snapshot sorgente di Firma con CIE. Non attribuisce una nuova licenza ai componenti di terzi e non sostituisce i testi integrali conservati nel repository. La visibilità privata di GitHub e la licenza sono aspetti distinti: il cambio di visibilità non modifica i termini dei componenti.

## Codice e risorse del progetto

| Materiale | Termini e provenienza |
| --- | --- |
| Nuovo codice condiviso Dart, ponte C e adattatori del progetto | BSD-3-Clause, indicata negli SPDX e in [LICENSE](../LICENSE) |
| Middleware e SDK importati | BSD-3-Clause principale IPZS e licenze individuali dei file; [avvisi](../native/backend/THIRD_PARTY_NOTICES.md) |
| Utility UUC che dichiarano LGPL | GNU Library GPL 2.0 o successiva secondo le intestazioni originali; [testo incluso](../native/backend/LICENSES/gnu/COPYING.LIB) |
| Icona documento e firma | Disegno originale generato con image_gen; termini BSD-3-Clause nella misura applicabile, [provenienza e formati](../assets/branding/README.md) |
| Miniatura della carta | BSD e attribuzioni originali conservate; [avviso](../assets/licenses/cie-card-NOTICE.txt) |
| Certificati CA pubblici | Non sono codice BSD del progetto: provenienza, checksum e policy in [trust](../native/backend/cie_sign_sdk/trust/README.md) e [PKI Difesa](../native/backend/cie_sign_sdk/trust/difesa/README.md) |

Il testo principale BSD e il copyright IPZS sono conservati senza sostituirli. I nomi CIE/IPZS e le risorse derivate non indicano approvazione del progetto e la licenza del codice non costituisce una concessione generale sui marchi.

L’importazione del backend è registrata in [native/backend-upstream.json](../native/backend-upstream.json), con repository, commit e hash iniziali. Le modifiche di porting sono in [PORTING.md](../native/backend/PORTING.md). Questo è un nuovo repository dello snapshot corrente; la vecchia cronologia del progetto upstream non viene importata.

## Dipendenze native

Versioni e URL/SHA-256 sono fissati nel [lock nativo](../native/backend/scripts/dependencies.lock.json). Le scelte già adottate dal backend sono mantenute:

| Componente | Versione fissata | Licenza utilizzata / testi |
| --- | --- | --- |
| OpenSSL | 3.5.9 | Apache-2.0; [licenza e attribuzioni](../native/backend/LICENSES/openssl/LICENSE.txt) |
| Crypto++ | 8.9.0 | Dichiarazioni di dominio pubblico, compilazione Boost-1.0 e avvisi CRYPTOGAMS; [testo](../native/backend/LICENSES/cryptopp/License.txt) |
| PoDoFo | 1.1.2 | Alternativa MPL-2.0; [testo](../native/backend/LICENSES/podofo/COPYING.MPL) e [NOTICE](../native/backend/LICENSES/podofo/NOTICE) |
| zlib / bzip2 | 1.3.2 / 1.0.8 | zlib / termini bzip2; [zlib](../native/backend/LICENSES/zlib/LICENSE), [bzip2](../native/backend/LICENSES/bzip2/LICENSE) |
| libiconv / libcharset | 1.19 | LGPL-2.1-or-later; [testo](../native/backend/LICENSES/libiconv/COPYING.LIB) |
| Expat / libpng | 2.9.0 / 1.6.59 | MIT / PNG Reference Library License; [Expat](../native/backend/LICENSES/expat/expat--COPYING), [libpng](../native/backend/LICENSES/libpng/LICENSE) |
| FreeType | 2.14.3 | FTL selezionata, conservando testi e attribuzioni originali; [licenza](../native/backend/LICENSES/freetype/LICENSE.TXT) |
| fontconfig / libxml2 / curl | 2.18.3 / 2.15.4 / 8.23.0 | Termini permissivi e avvisi dei sottocomponenti; [matrice completa](../native/backend/THIRD_PARTY_NOTICES.md) |

Le precedenti implementazioni RSAEURO, SHA-1 legacy e sorgenti GPL dello SDK sostituiti non vengono ripristinati. Gli algoritmi legacy eventualmente necessari a leggere documenti esistenti sono distinti dalle vecchie implementazioni rimosse. L’[audit ereditato del backend](../native/backend/LICENSE_AUDIT.md) è un documento storico del fork di provenienza: i suoi percorsi di build e pacchetti si riferiscono a quel progetto, non a questa nuova release.

Gli obblighi MPL riguardano i file coperti e le relative modifiche, non una ridenominazione globale del progetto: [FAQ ufficiali Mozilla](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). OpenSSL 3 usa Apache-2.0: [fonte ufficiale](https://openssl-library.org/source/license/index.html). Non si applicano eccezioni OpenSSL inventate a file di altri autori.

## Flutter, anteprima e componenti di sistema

Le 89 dipendenze risolte, comprese quelle SDK/dev, sono identificate in `pubspec.lock`. I pacchetti Flutter del SDK condividono la licenza Flutter; gli altri testi sono conservati in `LICENSES/preview/dart`. Flutter genera anche gli avvisi del bundle. Tra i componenti diretti: ffi, file_selector, path_provider e url_launcher BSD-3-Clause; pdfrx/PDFium con i rispettivi termini; desktop_drop Apache-2.0.

`LICENSES/preview/manifest.json` registra la provenienza degli avvisi disponibili degli archivi PDFium fissati. L’archivio Darwin non fornisce propri avvisi: prima di redistribuirne il binario occorre completare la copertura specifica di quella build, come indicato in [LICENSES/preview/README.md](../LICENSES/preview/README.md). La presenza degli avvisi Windows/Linux non è una dichiarazione automatica di completezza per Darwin.

Le DLL private MinGW libgcc/libstdc++ mantengono GPL e GCC Runtime Library Exception, con attribuzioni MinGW/winpthreads in [LICENSES/mingw](../LICENSES/mingw). Il CPDK Microsoft è una dipendenza di compilazione da ottenere separatamente; installer e header non sono redistribuiti in questo repository. Gli SDK di Apple e Microsoft rimangono soggetti ai propri termini.

Il [pacchetto Windows locale](WINDOWS_INSTALLER.md) include il redistributable
Microsoft Visual C++ x64 originale e firmato, fornito con Visual Studio Build
Tools. Non comprende compilatori o header Microsoft. Inno Setup 7.1.0 è usato
per compilare il pacchetto; sorgente `.iss` e versione del tool sono registrati
in `packaging/windows`. Le licenze dell'app, delle librerie e della JVM restano
incluse nel bundle e mantengono i propri obblighi di distribuzione.

## DSS, dipendenze Java e JVM

EU DSS 6.5.1 è usato come worker Java con JAR separati. I 50 JAR sono fissati in [dependencies.lock.json](../native/ltv/dependencies.lock.json); [LICENSES/ltv](../LICENSES/ltv/README.md) conserva la licenza ufficiale DSS LGPL-2.1 e gli avvisi estratti dagli altri JAR verificati. Le dipendenze mantengono le proprie licenze, non acquisiscono tutte LGPL o BSD.

Il runtime Eclipse Temurin/OpenJDK 21 è GPL-2.0 con Classpath Exception. Versione, archivi e hash sono nel [lock JVM](../native/ltv/toolchain.lock.json); i testi `legal` accompagnano ciascuna JVM assemblata. Una distribuzione binaria deve fornire anche il corrispondente sorgente OpenJDK nella forma richiesta dalla sua licenza. I soli URL upstream, il JRE e un elenco di checksum non sostituiscono tale materiale. [Provenienza e dettagli](../native/ltv/README.md).

## Cosa è pronto e cosa richiede una release binaria

Questo repository è predisposto per caricare **sorgenti, asset, lockfile e avvisi**. Non contiene librerie compilate, JAR/JRE, chiavi di firma o documenti personali. Il pacchetto sorgente di questo repository non è ancora il pacchetto completo di sorgenti corrispondenti di una futura app distribuita.

Per ciascuna futura release binaria:

1. Conservare commit, configurazione, manifest/hash e comandi che hanno prodotto esattamente il bundle distribuito.
2. Affiancare i sorgenti corrispondenti del progetto e delle dipendenze, incluse eventuali modifiche, script e quanto serve alla ricompilazione/ricollegamento dei componenti LGPL. Per le librerie statiche non basta citare la licenza o un link generico. Riferimenti: [LGPL-2.1 sezione 6](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html), testi individuali inclusi.
3. Includere sorgenti/modifiche e informazioni di reperimento per i file MPL, testi e attribuzioni completi delle dipendenze, avvisi PDFium specifici e sorgenti richiesti per OpenJDK.
4. Mantenere i JAR sostituibili, i relativi source JAR e gli avvisi. Consentire le attività previste dalle licenze per modifica e debugging; non introdurre divieti incompatibili.
5. Completare il collaudo, la firma e la distribuzione della piattaforma. La notarizzazione non certifica la conformità delle licenze. Le chiavi private del distributore restano private; la compilazione locale con le proprie identità è documentata.

La raccolta documenta i termini e le evidenze disponibili. Non è una dichiarazione che ogni futuro pacchetto binario sia già completo o che una scansione automatica certifichi la titolarità di tutti i materiali.
