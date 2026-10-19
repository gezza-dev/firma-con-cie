# Marche temporali e validità alla data di riferimento

Questa pagina descrive il percorso nativo preliminare. Il nuovo validatore
condiviso DSS gestisce anche DSS/VRI, OCSP archiviati e rinnovi LTA:
[LONG_TERM_VALIDATION.md](LONG_TERM_VALIDATION.md). I limiti descritti sotto
restano quelli delle API native, non del percorso DSS aggiunto nel prototipo.

Il motore è C++ condiviso fra macOS e Windows, in
`native/backend/cie_sign_sdk/src/Native/TemporalValidation.cpp`.
Solo la scelta delle radici di sistema usa gli adattatori già esistenti.

La policy include le CA CIE e le due CA ufficiali di firma/TSA PKI Difesa,
con provenienza e SHA-256 in `trust/difesa/manifest.json`. Sono ancore private
dell'app, identiche nel worker DSS e nel C++, senza installazioni nel sistema.
La fonte esposta è `difesa_ministry` solo quando il percorso effettivamente
accettato termina in una delle due CA fissate, non in una radice del documento.

Il download delle CRL ritenta una volta gli errori di trasporto transitori e
alcuni HTTP temporanei, entro il budget condiviso di 20 secondi/12 richieste
e quattro tentativi CDP. Non ritenta errori di autenticazione TLS, HTTP permanenti
o CRL non autenticabili/scadute. Il fallimento finale resta `UNKNOWN`.
Le prove coprono sia il recupero sia il mancato recupero senza falsi stati buoni.

Le estensioni TSTInfo non critiche sono ammesse senza usarle come fonte di
fiducia o di revoca: la firma del token protegge anche questi byte. Le estensioni
duplicate sono rifiutate; quelle critiche, le versioni e gli algoritmi non
supportati restano indeterminati e non danno validità storica positiva.
L'interfaccia espone la motivazione, distinguendo la mancanza di una catena TSA
attendibile da un errore crittografico o da una marca malformata. Le prove con
estensione includono token firmati correttamente, alterazione dei byte firmati,
impronta errata e radice sconosciuta. I controlli ESS, EKU, catena e revoca non
sono sostituiti dal solo riconoscimento del formato.
Non vengono installati certificati né modificati gli archivi di fiducia.

## Risultati distinti

- `signingTime`: data dichiarata nel documento, senza valore di prova temporale.
- `timestampStatus`: presenza e verifica di impronta, firma CMS, identificazione
  ESS del certificato TSA, uso critico esclusivo `timeStamping`, catena TSA alla
  data `genTime`. `verified` descrive questi controlli; **da solo non afferma che
  la TSA non fosse revocata**, né che la firma sia storicamente valida.
- `historicalStatus`: `valid_at_timestamp`, `invalid_at_timestamp` oppure
  `indeterminate`. Non cambia l'esito dell'integrità o dei controlli attuali.
- `tsaHistoricalRevocationStatus` e `signerHistoricalRevocationStatus`: prove
  riferite all'intervallo della marca. Mancanze e risposte non verificabili
  mantengono lo stato sconosciuto.
- `documentTimestamp*`: marche PDF del documento, distinte dalle marche della
  firma e dal numero dei firmatari. Non promuovono la validità storica.

## Ambito implementato

Si verifica l'attributo CMS `id-aa-signatureTimeStampToken` nei P7M CAdES e nei
CMS delle firme PDF PAdES. L'impronta deve corrispondere agli **ottetti della
firma CMS di quel firmatario**, individuato tramite certificato e valore della
firma, non alla data dichiarata o all'hash del documento. Si rifiutano attributi
ambigui/multipli, token alterati, ESS non corrispondente, algoritmi deboli,
TSA non autorizzate e date future oltre cinque minuti di tolleranza.
Le radici contenute nel token non diventano automaticamente attendibili.

Un esito storico positivo richiede:

1. Integrità della firma del documento e marca verificata.
2. `accuracy` esplicita supportata; l'intero intervallo deve ricadere nella
   validità delle catene del firmatario e della TSA. Le frazioni sono arrotondate
   verso l'esterno; un secondo aggiuntivo copre il troncamento di `genTime`.
3. CRL complete autentiche, incluse nel campo `crls` dei CMS, con `thisUpdate`
   e `nextUpdate` che coprano l'intero intervallo e tutti i certificati non root
   delle due catene. La firma della CRL e l'autorizzazione dell'emittente sono
   verificate. CRL delta, indirette, parziali o con estensioni critiche non
   supportate non forniscono un esito positivo. Una revoca prevale su una CRL
   buona concorrente. Non si deduce validità pregressa da una revoca successiva.
4. TSA ancora attendibile e non revocata **oggi**, tramite CRL incluse ancora
   applicabili oppure i controlli OCSP/CRL attuali. Questo requisito prudente
   evita di accettare token retrodatati con una chiave TSA compromessa; se
   manca, servirebbe una catena di rinnovi archivistici, qui non implementata.

Una risposta online attuale non viene usata come prova dello stato storico
nella catena del firmatario. Un certificato firmatario scaduto oggi può superare
il controllo alla data della marca se tutte queste condizioni sono soddisfatte.
L'esito riguarda la policy tecnica corrente, senza attestare la qualificazione
TSA, eIDAS, la data effettiva di sottoscrizione o una conformità ETSI completa.
Gli OID di policy dei token sono riportati, senza attribuire loro qualificazione.

Le marche PDF `/Type /DocTimeStamp`, `/SubFilter /ETSI.RFC3161` sono verificate
sui byte di `ByteRange` della revisione finale, collegando anche il contenuto
esadecimale della lacuna al `/Contents` del campo. Alterazioni falliscono;
marche di revisioni precedenti restano non determinabili. Non si verifica
ancora la semantica di tutte le revisioni PDF, DocMDP, DSS/VRI, OCSP archiviati,
CAdES `revocationValues`, marche di archivio/LTA o rinnovi di algoritmi.
Non si devono quindi presentare questi controlli come validazione LTV universale.
Le firme XML e le API legacy autonome TSR/TST/TSD non usano il nuovo percorso.

Gli hash accettati sono SHA-256/384/512 e SHA3-256/384/512. La policy delle firme
CRL è deliberatamente ristretta agli identificatori firma/hash riconoscibili;
RSA-PSS nelle CRL e nella firma TSA non è abilitato in questa revisione.
L'assenza di una marca o di prove supportate è un esito **non determinabile**,
non una firma automaticamente non valida. I documenti CIE di prova precedenti
non hanno marche: conservano integrità e fiducia attuali, senza validità storica.

## Test senza dati personali

`cie_security_tests` genera una CA e una TSA temporanee, firme CMS, marche RFC
3161 e CRL firmate. Le radici sono iniettate solo nella policy C++ del test e
non vengono esposte come configurazione del ponte pubblico. È verificato il
caso positivo con firmatario scaduto oggi, oltre ai casi negativi di impronta,
firma, ESS, uso TSA, radice non attendibile, data futura, revoca, CRL falsa o
inapplicabile, precisione assente e prove TSA attuali mancanti.

```bash
cie_security_tests --temporal-fixtures cartella-temporanea
python3 scripts/smoke_native.py --runtime percorso-runtime --report report.json
```

Le fixture esportate sono volutamente non attendibili per il ponte pubblico:
lo smoke conferma che non ottengono una validità storica positiva. Non serve
carta, PIN o un servizio di marcatura esterno. Per documenti esistenti,
`verify_signed_documents.py --require-history` fallisce quando almeno una firma
non ha `valid_at_timestamp`; `--require-trust` mantiene il suo significato di
controllo attuale. I due requisiti sono indipendenti.

Riferimenti: [RFC 3161](https://www.rfc-editor.org/rfc/rfc3161.html),
[API OpenSSL TS](https://docs.openssl.org/3.5/man3/TS_VERIFY_CTX/),
[documentazione DSS della Commissione europea](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/doc/dss-documentation.html).
