# Audit delle licenze e stato della pubblicazione

Verifica del 15 ottobre 2026 sullo snapshot del fork derivato dal commit
upstream `43da456fb3002e34beccda73b9bc4b149acae534`.

## Esito e ambito

Le implementazioni che bloccavano la pubblicazione (RSAEURO, SHA-1 di Paul
E. Jones e codice GPL dell'SDK combinato con OpenSSL) sono state sostituite
oppure eliminate dal **solo snapshot corrente**. Non sono state inventate
concessioni o eccezioni di terzi e non è stata cambiata la licenza delle
copie originali. La cronologia locale conserva le versioni precedenti:
per pubblicare questo risultato utilizzare un nuovo repository dello
snapshot, senza importare la vecchia storia Git.

La BSD 3-Clause principale e il copyright IPZS sono conservati byte per
byte. Le parti originali nuove seguono BSD 3-Clause. I file LGPL e le altre
dipendenze mantengono i propri termini: il progetto non è interamente BSD.
`scripts/license-manifest.json` registra versioni, testi e checksum;
`scripts/embedded-license-inventory.json` registra le dichiarazioni esplicite.
Questi controlli documentano le evidenze trovate, non provano la titolarità
di ogni file senza avviso né i diritti sui marchi.

## A01 — conflitto GPL/OpenSSL: risolto nello SDK prodotto

Sono rimossi SHA-224/256 PolarSSL GPL (`sha2.c/.h`), l'hashtable GPL
`include/UUCHashtable.h`, il reader GPL e le eccezioni ASN.1 GPL.
Gli hash usano OpenSSL EVP tramite `src/Native/Digest.h`; reader ed eccezioni
sono nuove implementazioni BSD basate su `std::vector` e `std::string`.
Il contenitore di proprietà usa una nuova implementazione BSD `std::map`
condivisa tra middleware e SDK (`native/PropertyTable.h`), evitando
incompatibilità fra le classi C++ interne dei due componenti.

La sola dichiarazione GPL rimasta nel codice del progetto è in
`TestCIE/main.cpp`: utility di test separata, esclusa da `CIE ID.app` e dal
pacchetto binario dell'app. Conserva GPL e avvisi. Non includere il suo
eseguibile nella release dell'app senza un'analisi distinta delle sue
librerie e dei suoi obblighi. I sorgenti distribuiti sono un insieme di
componenti con licenze diverse.

Il problema della build precedente con OpenSSL 1.1.1w è storico.
La build corrente usa OpenSSL 3.5.9 LTS sotto Apache License 2.0, con testo
integrale e elenco autori. Non si presume che Apache 2.0 sia compatibile
con GPLv2: il codice GPL resta escluso dal prodotto come descritto sopra. PoDoFo 1.1.2 è utilizzato sotto l'alternativa MPL 2.0 offerta dagli autori;
la precedente eccezione OpenSSL di PoDoFo 0.9.8 non è invocata nella nuova build. FreeType è utilizzato sotto **FTL**, non
sotto l'alternativa GPL. Il problema non è stato risolto attribuendo una
nuova licenza globale al binario o estendendo l'eccezione PoDoFo ad altri.

La FSF descrive l'incompatibilità della vecchia licenza OpenSSL con GPL:
[lista delle licenze](https://www.gnu.org/licenses/license-list.en.html#OpenSSL).
Questa sostituzione elimina il codice GPL dell'SDK che creava la combinazione.

## A02 — RSAEURO: rimosso dallo snapshot e dalla build

I dieci file RSAEURO sono eliminati; l'unico utilizzo attivo di
`RSAPublicDecrypt` è sostituito con `EVP_PKEY_verify_recover`, padding
PKCS#1 v1.5 per firme RSA. L'adattatore BSD è
`src/Native/RsaRecovery.cpp`. Dimensioni, esponente, padding e ritorni sono
verificati prima di interpretare il DigestInfo. Certificate/SignerInfo usano lo stesso adattatore EVP. L'importazione delle
chiavi RSA usa OSSL_PARAM ed EVP_PKEY_fromdata, senza RSA_METHOD o
RSA_public_decrypt in questi percorsi.

`scripts/replaced-legacy-sources.json` conserva percorsi e SHA-256 degli
originali rimossi o reimplementati; non contiene il loro codice. I vecchi
file non sono inclusi nel pacchetto di sorgenti corrispondenti. Copie locali
di recupero sotto `.build/` e la storia Git non sono materiali da pubblicare.

## A03 — implementazione SHA-1 legacy: sostituita

`sha1.c/.h` di Paul E. Jones sono eliminati. Gli utilizzatori dell'SDK usano
l'adattatore BSD OpenSSL EVP; non incorporano il vecchio algoritmo.
**SHA-1 come algoritmo rimane per la compatibilità con formati esistenti**:
questa modifica non converte documenti SHA-1 in SHA-256. Il percorso CAdES
continua a scegliere SHA-256.

I test controllano vettori noti SHA-1 (anche input vuoto e un milione di
caratteri), SHA-224/256, digest incrementali, reset e finalizzazione,
recupero RSA valido e rifiuto di firme troncate/corrotte. Generano firme CMS
con il generatore reale dell'SDK e un signer software, verificandole con
OpenSSL. Sono corretti anche il digest SHA-1 erroneamente lungo 24 byte,
l'identificativo CMS che dichiarava SHA-256 per SHA-1 e la deallocazione
dell'array hash. Sono inclusi test di firme PDF e aggiornamenti incrementali.

## A04 — sorgenti corrispondenti, LGPL e FreeType

Le utility UUC ancora LGPL, libiconv/libcharset
LGPL mantengono i testi originali. FreeType è selezionato sotto FTL, con
credito e testi completi, inclusi gli avvisi dei sottocomponenti.

`scripts/prepare-source-package.py` prepara:

- tutti i sorgenti correnti dell'app, SDK, middleware ed estensione, avvisi,
  modifiche e ricette CMake/Xcode;
- gli archivi esatti dei sorgenti delle 13 dipendenze, verificati con i
  checksum dei lockfile e disponibili nella cache della build estratta;
- manifest SHA-256 di sorgenti e bundle corrispondente, ambiente e comandi
  di ricompilazione documentati in `Docs/REBUILDING.md`.

La disponibilità dell'intera opera che utilizza le librerie in forma di
sorgenti, insieme ai sorgenti delle librerie e alle ricette, permette di
ricompilare e ricollegare con librerie LGPL modificate. Per questa modalità
si adottano i requisiti della sezione 6(a) della GNU Library GPL 2.0/LGPL
2.1; non si sostituiscono con un generico link upstream o un'offerta scritta.
Le copie di LGPL e le relative condizioni accompagnano i materiali.

La release deve distribuire **insieme** app e pacchetto corrispondente, e
consentire modifica per uso personale e reverse engineering necessario al
debugging di tali modifiche. Non applicare a queste attività divieti nella
licenza della distribuzione. Le chiavi private di firma Apple non vengono
fornite: la ricompilazione locale unsigned è documentata, e un utente può
configurare i propri identificativi e firma per CryptoTokenKit.

`check-publication.py --release` richiede il pacchetto locale e verifica
che né sorgenti né app siano cambiati dopo la sua preparazione. Qualsiasi
modifica, compresa firma/notarizzazione che modifica il bundle, richiede
nuovi materiali corrispondenti. Il test non certifica automaticamente il
rispetto futuro degli obblighi da parte del distributore.

Fonti: [GNU Library GPL 2.0](https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html),
[GNU LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).

## Dipendenze e attribuzioni

La matrice completa è in `THIRD_PARTY_NOTICES.md` e i testi in `LICENSES/`.
Sono inclusi OpenSSL Apache 2.0, Crypto++/CRYPTOGAMS, zlib, bzip2,
libiconv/libcharset, Expat, libpng, FreeType, fontconfig/Unicode, libxml2,
curl, PoDoFo, SSZipArchive/minizip e avvisi rxi, Base64, KTH e PKCS#11.
Il font Allura 1.005 mantiene OFL 1.1, copyright 2011 TypeSETit e Reserved
Font Name Allura della copia incorporata. BigInteger conserva la
[dichiarazione di dominio pubblico dell'autore](https://mattmccutchen.net/bigint/#legal)
e il README upstream per provenienza.

## Limiti della distribuzione

OpenSSL è aggiornato alla versione 3.5.9 del ramo LTS supportato fino
all'8 aprile 2030. I provider sono statici e il caricamento automatico
configurato da file esterni è disabilitato. Il provider legacy mantiene la
lettura dei PDF RC4 già supportati; non abbassa il livello di sicurezza TLS.

Le API ENGINE rimangono per compatibilità dell'SDK e sono deprecate.
L'engine CIE non viene registrato come engine predefinito globale: la firma
software e le altre operazioni OpenSSL non devono intercettare la callback
hardware. I test verificano callback RSA SHA-1/256/384/512, errori della
carta, query della lunghezza e rifiuto PSS senza accesso alla carta.
I test comprendono inoltre TLS 1.2/1.3 in memoria dopo la registrazione
dell'engine, metadati PDF cifrati RC4-40/128, AES-128 e AES-256, oltre a CMS e firme
PDF incrementali. Percorsi di moduli/configurazioni inesistenti verificano
che i provider incorporati siano sufficienti. PoDoFo è migrato a 1.1.2 LTS, con salvataggio incrementale e firma differita.
I test verificano la conservazione delle firme precedenti; la lettura dei PDF
cifrati non attesta ogni variante di firma e cifratura.
I flussi applicativi CIESigner/IAS continuano a usare l'interfaccia di firma
esistente. Il collaudo CIE/lettore e servizi remoti reali resta necessario.

104 header OpenSSL 1.x inutilizzati sono rimossi e registrati in
`scripts/removed-legacy-openssl-headers.json`. Le build usano esclusivamente
gli header e gli archivi della versione fissata nel prefisso nativo.

Il fork è sperimentale e indipendente. Nome, icone, bundle identifier,
App Group, firma, provisioning e notarizzazione richiedono configurazione
per il distributore. Le risorse storiche non attestano permessi sui marchi
IPZS/CIE. Gli archivi Intel originali e la vecchia storia Git non sono
parte dello snapshot preparato; vedere `Docs/PUBLICATION.md`.

## Aggiornamento 1.5.1

I lockfile, i testi di licenza e i relativi SHA-256 sono aggiornati alle versioni
riportate in `THIRD_PARTY_NOTICES.md`. Per PoDoFo si sceglie **MPL 2.0**;
il pacchetto contiene l'intero archivio upstream, NOTICE, entrambe le alternative
di licenza e i testi dei componenti incorporati. La libreria è ricostruita senza
i tool GPL. I moduli LGPL UUC e libiconv restano soggetti ai loro obblighi di
ricompilazione e ricollegamento, soddisfatti dai materiali sorgente completi.

Gli header Crypto++ 7.0/8.2 rimossi sono registrati separatamente; il controllo
pubblicazione ne impedisce il ripristino accidentale. OpenSSL resta 3.5.9 LTS.
I dettagli delle correzioni di sicurezza e dei test sono in `Docs/SECURITY.md`.
