# Modifiche al backend importato — 16 ottobre 2026

La copia iniziale deriva dal fork macOS v1.5.2, commit
`355c9b742268af80466404d80287ad9ce3f8c9b4`. La mappa dei checksum originali è
in `../backend-upstream.json`. I copyright e le licenze dei file incorporati
rimangono applicabili; questo documento identifica le modifiche del prototipo.

- CMake C/C++ comune, senza i target GUI AppKit/CryptoTokenKit; collegamenti di
  sistema distinti per PCSC.framework, Winscard e pcsc-lite.
- `platform/cie_platform.h` usa i tipi PC/SC del sistema e sostituisce le macro
  storiche che mascheravano i tipi. Dimensioni/offset dell'ABI del ponte sono
  controllati compilando l'adattatore con gli stessi header.
- Tipi `size_t` coerenti nelle utility ASN.1/array; handle PKCS#11 numerici con
  gestione del wrap; nessun puntatore troncato su Windows LLP64.
- Nomi degli include corretti per filesystem case sensitive; eliminazione del
  macro `min` che interferiva con la libreria standard GCC.
- `std::recursive_mutex` al posto dei mutex legacy non operativi su POSIX;
  connessione PC/SC del contesto differita fino alla prima operazione sulla carta.
- File UTF-8, apertura Unicode su Windows e controlli sui campi di testo dell'SDK.
  La lettura del file di proprietà senza symlink usa un'apertura sul file effettivo,
  non confronti separati sul pathname.
- Cache legacy degli abbinamenti disabilitata nella build del prototipo; PIN completo
  passato direttamente a IAS. Nessun percorso condiviso con l'app originale.
- Logger silenziosi; rimosso il collegamento IPC con l'app originale.
  Il cleanup azzera la copia del PIN nel contesto SDK; il signer non conserva
  un'ulteriore copia inutilizzata del PIN.
- Test SDK portati anche a Windows; test aggiuntivo contro collisioni/troncamento
  degli handle e controllo dei parametri di testo troppo lunghi.
- Un solo header SDK per middleware e libreria: il vecchio duplicato in
  `cie-pkcs11/Sign/disigonsdk.h` ora include quello condiviso. I client dell'SDK
  devono essere ricompilati insieme: `SIGNER_INFO` contiene il nuovo risultato
  di fiducia. L'ABI legacy `verifyInfo_t` resta invariata e il ponte usa la nuova
  funzione C additiva e size-checked `getCertificateValidation`.
- Validazione della catena in `Native/CertificateTrust.cpp`, con Root CA CIE
  esplicita, SubCA non attendibili fino alla verifica e adattatori alle policy
  native macOS/Windows. Rimossa la vecchia deduzione errata che l'assenza di un
  emittente nel vecchio store equivalesse a una catena verificata.
- Revoca attuale del firmatario e degli emittenti non root, con OCSP/CRL firmati,
  limiti di rete/dimensione e stato sconosciuto in caso di errori. Nessuna fiducia
  automatica nelle radici del documento o nelle risposte AIA; nessuna modifica
  agli archivi di sistema. Provenienza dei certificati pubblici in `cie_sign_sdk/trust`.
- I rami obsoleti Windows GUI/CSP sono conservati sotto `CIE_LEGACY_WINDOWS`,
  senza riattivarli nella build comune. Le implementazioni di piattaforma attive
  sono nel livello `platform` e in `../platform/pcsc_utf8.h`.

OpenSSL, Crypto++, PoDoFo e le altre dipendenze restano alle versioni e ai checksum
del lockfile. Le ricette portabili sono in `../../scripts/build_portable_dependencies.py`.
Gli avvisi di terze parti importati descrivono anche componenti della vecchia
app GUI (ad esempio SSZipArchive) che qui non vengono compilati; non sono un
elenco dei soli oggetti collegati nel prototipo.

Questa build serve a rilevamento CIE, firma documentale e verifica del prototipo.
Non è distribuita come middleware di sistema Windows/Linux, minidriver,
estensione CryptoTokenKit o sostituto della release macOS pubblicata.


## Marche temporali e validazione storica condivise

`Native/TemporalValidation.cpp` usa OpenSSL TS/CMS per legare la marca alla
firma corretta e verificare ESS, EKU TSA e catena alla data del token. Lo stato
storico richiede CRL complete autentiche applicabili alle due catene e lo
stato attuale TSA accertato; non trasforma una data dichiarata o una risposta
OCSP attuale in prova storica. Gestisce separatamente DocTimeStamp PDF della
revisione finale, senza promettere DSS/VRI o LTA. Policy e limiti:
`docs/TEMPORAL_VALIDATION.md` nel prototipo.

SDK e middleware condividono `TemporalValidation.h`: ricompilare tutti i client
per l'estensione di SIGNER_INFO/VERIFY_INFO. Le nuove funzioni C size-checked
`getTemporalValidation` e `getDocumentTimestampValidation` sono opzionali per
il ponte, che mantiene ABI v1 e `verifyInfo_t` invariata. Un vecchio backend
restituisce controlli temporali non disponibili, senza inventare esiti.

Il parser CMS legacy individua ora signerInfos dopo i campi opzionali certificati
e CRL; non presume più la posizione fissa che impediva la lettura di CMS con
prove di revoca incluse. Le fixture PAdES/CAdES verificano anche questo percorso
tramite il ponte pubblico.

Il ponte implementa un abbinamento privato separato con prefisso del PIN nel
Portachiavi macOS/Gestione credenziali Windows: `docs/PAIRING.md`. L’SDK riceve
sempre il PIN completo e la cache legacy resta disabilitata.
