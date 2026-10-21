# Verifica di fattibilità RSA-PSS per l'accesso ai siti

Verifica del 21 ottobre 2026 su specifiche pubbliche, middleware incluso nel
repository e adattatori Windows/macOS/Linux. Nessuna operazione sulla CIE reale,
nessuna autenticazione, installazione o modifica alle preferenze dei browser.

## Esito

Il percorso attuale della chiave di autenticazione CIE offre RSA 2048 con padding
PKCS#1 v1.5. Non è stata individuata un'interfaccia documentata che consenta alla
stessa chiave di produrre firme RSA-PSS o di eseguire RSA senza padding. Pertanto
PSS non viene implementato né dichiarato ai browser. L'esito riguarda il profilo
CIE pubblicato e il middleware esaminato: non è una dimostrazione sperimentale
che ogni variante presente o futura del chip sia fisicamente incapace di PSS.

Per procedere servirebbero la documentazione del produttore/emittente relativa
alla chiave client e una prova crittografica sulla carta. Il solo fatto che il
chip o una sua applicazione supportino PSS per altri scopi non basta.

## Riscontri

Le [specifiche CIE 3.0 attualmente pubblicate dal Ministero](https://www.cartaidentita.interno.gov.it/pa-e-imprese/specifiche-del-microprocessore-e-del-file-system/)
rimandano al [documento versione 1.0 del 19 novembre 2015](https://www.cartaidentita.interno.gov.it/downloads/2021/03/cie_3.0_-_specifiche_chip.pdf).
I punti rilevanti sono:

- pagina 27, allegato A: `Cert_CIE.Kpriv` (`BF9001`), la chiave del certificato
  client, ha algoritmo `02h`, accesso tramite INTERNAL AUTHENTICATE dopo secure
  messaging e PIN; PSO COMPUTE DIGITAL SIGNATURE e DECIPHER sono vietati;
- pagina 28: l'ambiente `SE.Sign` seleziona algoritmo `2` e chiave locale `81h`;
- pagina 7, §5.5: il riferimento a PSS riguarda la Terminal Authentication
  dell'applicazione MRTD, distinta dall'applicazione IAS per l'accesso ai siti.

Il [middleware ufficiale Windows, `IAS::Sign`](https://github.com/italia/cie-middleware/blob/master/CSP/CSP/IAS.cpp)
e la copia inclusa in `native/backend/cie-pkcs11/CSP/IAS.cpp` selezionano
`MSE SET AT` (`00 22 41 A4`, algoritmo `02`, chiave `81`), quindi
`INTERNAL AUTHENTICATE` (`00 88 00 00`). È il percorso PKCS#1 v1.5 usato dagli
accessi già collaudati. Non espongono selezione PSS, parametri MGF/salt o una
modalità RSA senza padding. Anche il secondo `IAS.cpp` dello SDK documentale
mantiene questo schema. Le definizioni `CKM_RSA_PKCS_PSS` negli header PKCS#11
non equivalgono a un meccanismo implementato: le funzioni del middleware non lo
espongono.

`IAS::VerificaSODPSS` e `CRSA::RSA_PSS` verificano firme del SOD con una chiave
pubblica: non firmano con la chiave privata del titolare. Il supporto PSS di
OpenSSL o delle API Windows non estende le operazioni autorizzate dalla carta.

Nel nostro motore `cie_web_sign` accetta soltanto DigestInfo DER SHA-256/384/512,
chiama `IAS::Sign` e verifica la firma restituita. Gli adattatori seguono questo
contratto:

| Adattatore | Operazione esposta |
| --- | --- |
| Windows minidriver, tramite CSP/KSP Microsoft | `CARD_PADDING_PKCS1`, hash SHA-2 oppure DigestInfo canonico già codificato di Firefox |
| macOS CryptoTokenKit | PKCS#1 v1.5; rimozione del blocco BT1 fornito da Security.framework perché il padding è applicato dalla carta |
| Linux PKCS#11 | `CKM_RSA_PKCS` e varianti SHA-256/384/512 |

## Perché il padding nel software non risolve

[RFC 8017, §9.1 e §9.2](https://www.rfc-editor.org/rfc/rfc8017.html#section-9.1)
definisce codifiche differenti per PSS e PKCS#1 v1.5. Preparare un blocco PSS
nel computer richiederebbe poi l'operazione RSA privata senza ulteriore padding.
Passarlo a `IAS::Sign` manterrebbe invece il percorso PKCS#1 v1.5 della carta:
non produrrebbe una firma PSS valida. Una firma v1.5 non può essere convertita
successivamente in PSS senza una nuova operazione privata adatta.

[RFC 8446, §4.4.3](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.3)
richiede PSS per CertificateVerify con RSA in TLS 1.3. Non viene quindi dichiarato
supporto all'autenticazione client RSA in TLS 1.3. Gli accessi già riusciti non
stabiliscono quale protocollo sia stato negoziato nei singoli flussi.

## Verifiche di compatibilità

Sono stati eseguiti i test locali senza carta:

- 124 controlli isolati del minidriver, inclusi SHA-2 esplicito e DigestInfo
  Firefox, query delle capacità, rifiuto di PSS con parametri SHA-256/384/512
  validi anche per la sola richiesta della dimensione, e firma PKCS#1 riuscita
  dopo il rifiuto senza nuove autenticazioni;
- 56 controlli della policy setup, 79 della policy web e 308 del vincolo fra
  autenticazione e richiesta di firma;
- 19 verifiche RSA e 20 controlli ABI sul runtime nativo già distribuito,
  con trasporto simulato per le prove ABI.

I nuovi controlli di regressione sono in
`native/platform/windows/web/minidriver_tests.cpp`. Il codice di produzione,
l'app e il componente installato restano quelli collaudati con Chrome e Firefox.
Il 21 ottobre l'utente ha confermato anche il collaudo riuscito con Microsoft
Edge su Windows. La versione di Edge e il protocollo TLS non sono stati rilevati
indipendentemente; il collaudo non attesta il supporto PSS.
È stato ricompilato soltanto l'eseguibile dei test. I log della verifica sono
in `../reports/rsa-pss-feasibility-20261021/` rispetto alla radice del repository.

Per una futura estensione occorrerà verificare prima la firma PSS reale contro
il certificato della carta (hash, MGF1 e salt concordati), poi esporre la capacità
solo per le carte compatibili e collaudare nuovamente PKCS#1 e i browser.
