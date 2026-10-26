# Compatibilità e funzioni successive al confronto ufficiale

Implementazione del 21 ottobre 2026 per Firma con CIE 1.0.0, successiva a
[OFFICIAL_MIDDLEWARE_COMPARISON.md](OFFICIAL_MIDDLEWARE_COMPARISON.md).

## Perimetro e PIN

Sono implementati C1, C3, il preavviso C4 nella Home e la ricerca manuale C5.
Le regole del nuovo PIN, il cambio/sblocco nelle pagine dedicate, il PIN
completo nel browser e il PIN parziale per la firma abbinata restano invariati.
I callback standard di modifica PIN/PUK nel componente Web rimangono non
supportati (C2): estenderli contrasterebbe con il vincolo di conservare quella
gestione. Nessuna migrazione della cache o modifica delle credenziali.

## CryptoAPI Windows — C1

Il minidriver rende disponibile la stessa chiave anche come `AT_KEYEXCHANGE`:
dimensioni, contenitore pubblico, `kxc01`, enumerazione e firma. L'alias usa
lo stesso motore PKCS#1 e lo stesso contesto autenticato di `AT_SIGNATURE`.
La decifratura RSA resta non supportata. Il GUID del contenitore di firma e il
collegamento certificato/KSP già pubblicato rimangono identici.

Il collaudo reale successivo ha rilevato `No_client_certificate` prima del PIN:
con entrambi i ruoli nello stesso contenitore `NCryptOpenKey` con specifica 0
restituisce `NTE_BAD_KEYSET` (0x80090016); le specifiche esplicite 1 e 2 riescono.
La correzione espone due contenitori distinti per la stessa chiave fisica:
indice 0, nome originale, sola firma e predefinito; indice 1, nome derivato
stabile e solo alias `AT_KEYEXCHANGE`. Ogni nome risolve una sola chiave anche
quando il browser non indica il ruolo. Il certificato DER è lo stesso per i
due alias; nessuna nuova chiave o identità viene generata. La revisione dei
metadati `cardcf` invalida la vecchia mappa senza modificare la cache PIN.

I test verificano unicità e stabilità dei nomi, permanenza del GUID originale,
coerenza tra mappa, file e blob pubblici, e firma attraverso l'alias senza
nuovi callback PIN. `scripts/check_windows_web_key.py --expect-open` verifica
l'apertura effettiva usata dal browser tramite Windows KSP, in modalità
silenziosa e senza riparazioni, firme o PIN. Legge solo i certificati marcati
dall'app e i metadati pubblici della carta, senza registrare identificativi.
Riferimenti: [NCryptOpenKey](https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptopenkey)
e [mappa dei contenitori](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/file-system-requirements).
L'installer corretto è stato eseguito sul PC Windows con conferma UAC: exit 0,
12 registrazioni aggiornate e checksum del minidriver verificato. La stessa
`CryptAcquireCertificatePrivateKey(ONLY_NCRYPT | SILENT | NO_HEALING)` che
falliva prima ora riesce con `CERT_NCRYPT_KEY_SPEC`, senza PIN o firma.
Il collaudo completo Chrome successivo all'aggiornamento è riuscito:
l'utente conferma l'apertura dell'area riservata dopo il PIN completo e
«Prosegui» nella schermata di rilascio attributi. Nel log opt-in i callback
di autenticazione e firma restituiscono tutti 0. I callback di disconnessione
restituiscono intenzionalmente `SCARD_E_UNSUPPORTED_FEATURE`, come previsto
dal contratto che demanda il reset al chiamante; non sono errori di firma.
Il numero di callback di autenticazione non indica il numero di finestre PIN:
Windows può riutilizzare la propria cache temporanea. La pagina bianca
osservata nella prova precedente non si è ripresentata; senza una traccia di
quella richiesta la sua causa resta indeterminata. Il launcher diagnostico
aggiunge solo `CIE_WEB_DIAGNOSTIC_FILE` al processo Chrome: nessun nuovo profilo,
flag di rete o modifica di sicurezza, e nessuna ulteriore modifica del driver.
Il 21 ottobre 2026 l'utente ha confermato il collaudo riuscito con tutti e tre
i browser Windows: Chrome, Microsoft Edge e Mozilla Firefox, usando il
componente corretto. L'evidenza tecnica dettagliata riguarda il log opt-in
di Chrome; gli esiti Edge e Firefox sono conferme del collaudo manuale.
La cache PIN del sistema rimane di 60 secondi. SHA-1, MD5 e RSA-PSS non vengono
aggiunti alle firme Web.

## PKCS#11 — C3

Il provider condiviso aggiunge `C_DigestInit/Digest/Update/Final` per SHA-256,
SHA-384 e SHA-512 e `C_VerifyInit/Verify/Update/Final` per RSA PKCS#1 v1.5 con
gli stessi hash. Supporta le richieste di dimensione e i buffer insufficienti
senza consumare l'operazione. Verifica e digest hanno stato separato dalla
firma e non richiedono login, PIN o operazioni private sulla carta.

Su Windows è incluso il nuovo modulo x64 `backend/cie_pkcs11.dll` nel payload
Web. Riusa lo stesso codice del provider Linux e il motore `cie_web.dll`
esistente; le primitive OpenSSL vengono importate mediante la loro ABI C dal
backend privato invariato, compilato con OpenSSL 3.5.9. Ogni oggetto viene
liberato dalla stessa libreria che lo ha allocato. Nessun oggetto C++ passa
tra moduli compilati con toolchain differenti.

Per un programma Windows che richiede esplicitamente PKCS#11, il percorso
preferito dopo l'installazione è:

```text
C:\Program Files\CIE ID Flutter Prototype\WebToken\<hash del payload>\backend\cie_pkcs11.dll
```

La directory immutabile conserva le versioni già caricate dai processi. La
copia `web-component/backend/cie_pkcs11.dll` accanto all'app contiene lo stesso
file. Per gli accessi Windows già configurati si continua a usare CSP/KSP:
l'installer non aggiunge un secondo modulo a Firefox e non modifica i profili
dei browser. Il nome `CIEPKI.dll` e l'ABI completa della distribuzione ufficiale
non vengono impersonati.

Le sorgenti Linux sono aggiornate con le stesse operazioni. In questa attività
il codice comune e tutti i test con carta simulata sono compilati/eseguiti su
Windows; la compilazione del pacchetto Linux, le integrazioni NSS su Linux e i
login reali dopo questa modifica restano da ripetere sul relativo sistema.
Il componente macOS non viene ricompilato né modificato qui.

Compilazione Windows in un ambiente sviluppatore Visual Studio x64:

```powershell
python scripts/build_windows_pkcs11.py `
  --runtime native/runtime/windows `
  --openssl-include <OpenSSL-3.5.9-configurato>/include `
  --build-dir .build/windows-pkcs11-msvc
```

Lo script verifica i checksum del runtime e la versione degli header, genera
le librerie di importazione dalle esportazioni effettive e compila/testa il
modulo. Gli header usati per questa build sono generati dal tarball OpenSSL
del lockfile, verificato SHA-256; non è stata ricompilata o sostituita la
libreria crittografica del backend. Il packager Web accetta `--pkcs11` e include
nel manifest gli hash delle sorgenti del nuovo modulo e dei motori riutilizzati.

## Certificato e Home — C4

La Home legge `notBefore` e `notAfter` dal certificato pubblico conservato
dall'abbinamento verificato. Mostra la scadenza e un avviso se il certificato è
scaduto o non ancora valido. La lettura DER è limitata a 8192 byte, gestisce
UTCTime e GeneralizedTime UTC e rifiuta lunghezze indefinite, dati troncati,
date impossibili e byte estranei alla sequenza esterna.

Non richiede lettore, rete o PIN; non cambia i flag dell'abbinamento e non
promuove queste date a esito di fiducia/revoca. Il browser e il verificatore
documentale mantengono le proprie verifiche. L'avviso è nell'app: non viene
creata una notifica desktop autonoma dentro il processo del browser.

## Aggiornamenti — C5

Informazioni contiene «Verifica aggiornamenti». Consulta via HTTPS le release
stabili di `gezza-dev/firma-con-cie`, confronta le versioni numericamente e
propone soltanto la pagina GitHub della release di quello stesso repository.
L’endpoint è `https://api.github.com/repos/gezza-dev/firma-con-cie/releases/latest`
e lo User-Agent è `Firma-con-CIE/<versione>`. Il vecchio nome del repository
non è ammesso negli URL di release restituiti dal servizio.
Non segue redirect di rete, non scarica/esegue installer, non include token o
credenziali e non confonde un errore con «versione aggiornata». Le risposte
hanno un limite di 256 KiB e l'intera richiesta un timeout di 12 secondi.

L'utente ha richiesto di mantenere questo repository, che diventerà pubblico
solo dopo il completamento dei test. Finché è privato o manca una release
accessibile, il controllo segnala indisponibilità. Non è stata cambiata la
visibilità del repository. Non vengono installati task pianificati o controlli
periodici in background; la ricerca disponibile in questa versione è manuale.

## Verifiche e distribuzione

- Analisi statica Flutter senza problemi; 220 test superati, 3 integrazioni
  facoltative saltate. Inclusi test delle date e degli errori/versioni/URL del
  canale di aggiornamento, dei flussi PIN, firma, abbinamento e accesso Web.
- Minidriver: 161 controlli isolati; catalogo/registro 410; policy setup 75.
  La regressione Chrome verifica nomi distinti, GUID preesistente conservato,
  ruolo univoco per nome, revisione della cache pubblica e coerenza dell'alias
  anche tramite `CCP_CONTAINER_INFO`, oltre alla firma senza nuove richieste PIN.
- PKCS#11: 199 controlli con PC/SC e carta simulati, senza collegamento a
  Winscard nel modulo di test. Compresi hash confrontati con OpenSSL, firme
  valide/alterate, verifica singola/multipart senza login, buffer piccoli,
  consumo degli stati, nessuna nuova autenticazione o firma per le operazioni
  pubbliche, errori/timeout/rimozione e mancata ripetizione del PIN.
- Il motore crittografico `cie-pkcs11.dll`, `cie_web.dll` e le dipendenze del
  payload Web conservano i checksum precedenti. Cambiano il minidriver, il
  helper con il nuovo manifest ed è aggiunto il modulo PKCS#11.
- Installer: 49 verifiche di installazione/aggiornamento/riparazione/rimozione
  con motore Inno reale e componente simulato in una destinazione isolata.
  Il controllo preliminare del helper effettivamente distribuito termina con
  codice 0 sul PC attuale, senza elevazione, installazione o uso della carta.
  Il modulo PKCS#11 effettivamente incluso si carica e restituisce la propria
  function list 2.20; la prova non chiama `C_Initialize` e non enumera lettori.
- Le suite automatiche restano isolate dalla CIE reale. Successivamente
  l'installer corretto è stato eseguito con conferma UAC e sono stati verificati
  registrazioni, checksum e apertura KSP silenziosa. L'utente ha poi eseguito
  con successo gli accessi completi Chrome/Edge/Firefox. Il controllo finale
  prima del commit ha inoltre corretto l'inoltro dell'indice dell'alias in
  `CCP_CONTAINER_INFO`, coperto da un ulteriore test isolato; il contenitore
  di firma usato dai browser rimane invariato.

Evidenze locali (non incluse nel repository):
`../reports/middleware-parity-implementation-20261021/`,
`../reports/chrome-no-pin-20261021/` e `../reports/chrome-post-consent-20261021/`.
