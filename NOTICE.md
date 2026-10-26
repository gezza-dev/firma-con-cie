# Avvisi di Firma con CIE

Repository: https://github.com/gezza-dev/firma-con-cie.
Per l'ambito attuale delle licenze e i materiali necessari a una futura
distribuzione binaria vedere `docs/LICENSING.md` e `LICENSES/README.md`.
Gli audit inclusi in `native/backend` descrivono anche lo snapshot storico
di provenienza; non attestano che una release di Firma con CIE sia già pubblicata.

## Icona dell'applicazione

Le icone in `assets/branding`, nel catalogo macOS, nelle risorse Windows e
in `linux/resources` usano il nuovo disegno documento e pennino selezionato
per Firma con CIE, generato con OpenAI image_gen. Le basi chiara e scura
riprendono gli sfondi della GUI. Il precedente logo derivato da CIE ID
Universal/IPZS non è usato per l’icona dell’applicazione.
Termini in `assets/branding/LICENSE.txt`; provenienza, prompt e ricetta di
esportazione in `assets/branding/README.md`. La miniatura illustrativa della
CIE mantiene invece la propria attribuzione originale, riportata più avanti.

Il backend incorpora anche i certificati pubblici Root CA/SubCA CIE pubblicati
dal Ministero dell'Interno e le CA di firma/TSA della PKI Difesa pubblicate
dal Ministero della Difesa. Queste ultime sono documentate con provenienza e
checksum in `native/backend/cie_sign_sdk/trust/difesa/`.
Per le CA CIE, provenienza, checksum e policy sono in
`native/backend/cie_sign_sdk/trust`; il runtime e il bundle includono una copia.
Non vengono installati nell'archivio di fiducia del sistema e non viene loro
attribuita la licenza del nuovo codice.

Prototipo indipendente collegato al fork `gezza-dev/cie-id-macos-universal`.
Non è un prodotto ufficiale dell'Istituto Poligrafico e Zecca dello Stato Italiano
e non è supportato da IPZS.

Il nuovo codice del prototipo dichiara BSD-3-Clause. I termini dei componenti
riutilizzati restano quelli dei rispettivi titolari: il collegamento FFI non
modifica la licenza del middleware, dell'SDK o delle librerie incorporate.

Il backend originale è identificato in `toolchain.lock.json`; i sorgenti di base
sono disponibili nel [tag v1.5.2](https://github.com/gezza-dev/cie-id-macos-universal/tree/v1.5.2).
La copia in `native/backend` contiene modifiche per il porting, descritte in
`native/backend/PORTING.md`. Commit e checksum dell'importazione iniziale sono
registrati in `native/backend-upstream.json`. Le licenze individuali, inclusa
LGPL per le utility che la dichiarano, restano applicabili.

Il runtime portabile copia gli avvisi del backend e quelli del prototipo.
Le dipendenze sono ricompilate dagli archivi identificati nel lockfile.
Le DLL Windows private libgcc/libstdc++ sono accompagnate dai termini GCC con
Runtime Library Exception 3.1; winpthreads/MinGW-w64 mantengono i propri avvisi.
I testi forniti dalla distribuzione della toolchain sono in `LICENSES/mingw`.
I loro copyright e le eccezioni non vengono sostituiti dalla licenza del prototipo.
Il pacchetto di test include una copia delle sorgenti del progetto e le ricette
per ricompilare backend e dipendenze; non è una release per utenti finali.

Flutter, Dart, il motore grafico e i pacchetti mantengono i propri avvisi.
Gli avvisi diretti di Flutter, `ffi` e `file_selector` sono in `LICENSES`;
`path_provider` gestisce la cartella delle preferenze e `url_launcher` i link
nel browser predefinito: mantengono i loro termini BSD-3-Clause, conservati
anche in `LICENSES/preview/dart` e negli avvisi Flutter.
Flutter genera inoltre `NOTICES.Z` con gli avvisi dei pacchetti inclusi.
L’anteprima locale usa pdfrx/PDFium; il trascinamento usa desktop_drop. Versioni,
checksum e avvisi sono in `native/preview/pdfium.lock.json` e `LICENSES/preview`.
La raccolta include le licenze native dei terzi e quelle dei pacchetti Dart;
vedere `LICENSES/preview/README.md` per la copertura degli avvisi Darwin.
Il bundle copia i testi diretti in `Contents/Resources/CIEPrototype`.

Nessun eseguibile del prototipo è stato pubblicato come release. La firma
Apple Development serve alle prove locali e non equivale a notarizzazione.

## Validatore DSS/LTA locale

EU DSS 6.5.1 (Commissione europea), LGPL-2.1-or-later, è usato come worker
locale tramite JAR originali separati. Dipendenze e JVM Eclipse Temurin 21
sono fissate in native/ltv e accompagnate da sorgenti JAR e avvisi nei runtime.
OpenJDK/Temurin è GPL-2.0 con Classpath Exception; licenze in jre/*/legal.
Non sono installate CA di test. Il prototipo non afferma qualificazione eIDAS.
Vedere native/ltv/README.md per provenienza e condizioni di distribuzione.

## Adapter per autenticazione Web

Il nuovo motore di autenticazione riusa IAS e il backend CIE con le rispettive
licenze già riportate. Gli adapter CryptoTokenKit e cardmod sono sorgenti del
prototipo; non includono codice del vecchio CSP Windows. Il CPDK Microsoft
10.1.19041.953 è una dipendenza di compilazione: header e installer restano
fuori dal progetto e dai pacchetti di prova. Provenienza, checksum e procedura
sono in scripts/prepare_cpdk.py e docs/WEB_AUTHENTICATION.md. La build locale
Windows non implica una certificazione Microsoft o una firma Authenticode.

## Illustrazione della CIE

La miniatura in `assets/images/cie-card.png` e le varianti 2x/3x provengono
dall’asset `CIE ID/Assets.xcassets/cie.imageset` del middleware originale.
È riutilizzata senza modifiche con l’attribuzione IPZS e la licenza BSD-3-Clause
originale, inclusa in `assets/licenses/native-LICENSE.txt`; provenienza in
`assets/licenses/cie-card-NOTICE.txt`. Non contiene dati della carta dell’utente.
