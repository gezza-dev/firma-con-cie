# Backend condiviso: macOS, Windows e Linux

Per il quadro corrente dei sistemi collaudati vedere [STATUS.md](STATUS.md).
I riferimenti successivi a prove Windows ancora da svolgere appartengono al
diario del porting: accesso Chrome con CIE reale e PIN completo è stato verificato.
Linux non ha ancora raggiunto la parità funzionale delle altre due piattaforme.

Il prototipo mantiene una sola interfaccia Dart e una sola copia versionata dei
sorgenti del backend in `native/backend`. Non modifica il repository o le release
dell'app macOS pubblicata. La base importata è il tag v1.5.2 del fork;
`native/backend-upstream.json` registra commit e checksum prima del porting.

```text
Flutter / Dart
    → cie_bridge: ABI C v1, JSON UTF-8, chiamate serializzate
        → PC/SC del sistema
        → verificaConCIE / getVerifyInfo / getNumberOfSign
        → cie_card_adapter: identificazione CIE e firma con PIN completo
            → IAS + SDK condivisi (CAdES/PAdES, OpenSSL, Crypto++, PoDoFo)
```

## Differenze di piattaforma isolate

| Servizio | macOS | Windows x64 | Linux |
| --- | --- | --- | --- |
| Lettore | PCSC.framework | Winscard, API Unicode | pcsc-lite |
| Librerie | dylib / dlopen | DLL / LoadLibraryExW | so / dlopen |
| Crittografia / PDF / revoca | Stesse sorgenti e dipendenze fissate | Stesse sorgenti e dipendenze fissate | Stesse sorgenti e dipendenze fissate |
| File | POSIX, UTF-8 | Conversione UTF-8 → UTF-16 | POSIX, UTF-8 |
| Sincronizzazione | std::recursive_mutex | std::recursive_mutex | std::recursive_mutex |

I tipi dei parametri PC/SC vengono dagli header del sistema: `DWORD` non è
ridefinito come `uint32_t`, perché pcsc-lite su Linux a 64 bit usa un tipo diverso.
Le strutture PKCS#11 conservano l'ABI della piattaforma. Gli handle degli oggetti
sono ID numerici, senza conversioni di puntatori in interi a 32 bit su Windows.

L'adattatore e il middleware vengono compilati insieme con lo stesso compilatore;
nessun oggetto C++ attraversa il confine Dart. Su Windows la prima toolchain è
MinGW-w64 POSIX x64: il runner Flutter può essere compilato con Visual Studio,
perché comunica soltanto tramite ABI C. Non è dichiarata una build MSVC del
backend. I runtime MinGW restano nella cartella privata dell'app, con i loro avvisi.

I rami dell'antica GUI/CSP Windows sono conservati sotto `CIE_LEGACY_WINDOWS`,
non abilitati nella build condivisa. Le selezioni attive di piattaforma usano
`_WIN32`/`__APPLE__` e CMake. Il vecchio IPC con l’app macOS non viene usato. La nuova estensione
CryptoTokenKit e il nuovo minidriver Windows consumano l’ABI C di `cie_web`;
non duplicano il protocollo IAS. Dettagli in [WEB_AUTHENTICATION.md](WEB_AUTHENTICATION.md).

## Autenticazione e log

L’SDK riceve il PIN completo di otto cifre, anche quando la UI usa il PIN
parziale. Il prototipo non legge né scrive la cache degli
abbinamenti dell'app originale. Nel backend condiviso gli ingressi della cache
persistente sono disabilitati esplicitamente. Questa libreria PKCS#11 resta **inadatta al login tramite cache legacy**.
L’autenticazione Web usa i nuovi adattatori dedicati e non riattiva quella cache;
la firma locale e il login al portale ufficiale CIE con Safari 27.0.1 sono
collaudati su macOS Apple Silicon; restano altri siti/browser e attivazione/prova
KSP reale su Windows.
Gli abbinamenti del prototipo sono ora separati dalla cache legacy: il prefisso
del PIN è custodito nelle credenziali native del sistema e ricomposto soltanto
nel ponte C++ per la firma; vedere [PAIRING.md](PAIRING.md). Cambio PIN e sblocco tramite PUK
sono esposti dal ponte C e dalla GUI condivisa, con il protocollo IAS originale,
connessione esclusiva e trasporto senza reinvio degli APDU. La modifica fisica
del PIN e il collaudo software hanno evidenze distinte: vedere [PIN_PUK.md](PIN_PUK.md).

I logger legacy sono sostituiti da implementazioni silenziose, senza formattare
parametri potenzialmente sensibili. Gli errori operativi tornano attraverso il
ponte. Ogni comando di firma effettua un solo tentativo; non ci sono retry del PIN.
Il ponte azzera il buffer ricevuto e il cleanup dell'SDK azzera la propria copia.
Dart/Python possono creare copie gestite che non consentono una garanzia completa
di azzeramento: resta un punto da approfondire prima della produzione.

## Stato delle prove

Vedere [VALIDATION.md](VALIDATION.md) per gli esiti osservati e
[BUILD_NATIVE.md](BUILD_NATIVE.md) per riprodurre le compilazioni e le prove.
Sul PC Windows x64 sono riusciti rilevamento, firme reali PAdES/CAdES e verifica
indipendente dei risultati. Le stesse prove sono riuscite su macOS Apple Silicon
con il backend condiviso. La VM Linux usata per compilare non dispone del lettore USB
del Mac; le prove hardware e della GUI Linux sono rinviate finché non sarà
disponibile un ambiente adatto.

La verifica distingue integrità, validità temporale, percorso di fiducia e revoca.
Il percorso è costruito e verificato da OpenSSL con l'ancora CIE ministeriale
incorporata. Per altre autorità macOS usa la policy Basic X.509 di Security e
Windows la policy BASE di Crypt32; solo un percorso accettato dal sistema viene
ricontrollato da OpenSSL. Certificati del CMS, SubCA incluse e risposte AIA sono
candidati non attendibili fino alla verifica; non aggiornano gli archivi di sistema.

Firma dei certificati, vincoli CA, profondità, robustezza crittografica, uso della
chiave e validità temporale vengono controllati alla data corrente. Il tempo
dichiarato dal documento non sostituisce questo controllo. Non viene attestata
la qualificazione giuridica. La validità alla data di una marca viene valutata
separatamente, con le prove e i limiti descritti in TEMPORAL_VALIDATION.md.
L'archivio Linux di sistema non è ancora integrato: l'ancora CIE incorporata resta
utilizzabile, ma le prove hardware Linux sono in sospeso.

OCSP e CRL devono essere firmati dall'autorità corretta, riferiti al certificato
e validi temporalmente. Si verifica la revoca di tutti i certificati del percorso,
esclusa la radice di policy; solo tutti gli esiti positivi producono uno stato
di catena non revocata. Un emittente revocato prevale sull'OCSP positivo del
firmatario. Rete assente, dati scaduti o non autenticabili restano sconosciuti.
Ogni controllo ha un budget di 20 secondi e 12 richieste, con dimensioni massime
di 1 MiB per AIA/OCSP e 64 MiB per CRL. La root CIE cambia solo con revisione
esplicita dei sorgenti e della provenienza registrata in `trust/manifest.json`.

Il prototipo supporta PAdES con segno grafico facoltativo e anteprima PDF locale,
CAdES incapsulato, estrazione P7M e trascinamento. Dettagli e limiti sono in
[DOCUMENT_WORKFLOWS.md](DOCUMENT_WORKFLOWS.md). Non comprende
controfirma dedicata o gestione di sistema dei
certificati o un installer Windows/Linux. I percorsi troppo lunghi per i campi
fissi dell'SDK vengono rifiutati; su Windows il limite dei campi è `MAX_PATH`.

Il workflow CI prepara compilazioni/test dei backend e dei runner, senza carte,
PIN o identità di firma. La configurazione locale del workflow non equivale a
un'esecuzione su GitHub.

## Marche e controlli storici

Il nuovo motore temporale è condiviso fra macOS e Windows. Per la distinzione
fra firma, marca e prove storiche native vedere
[TEMPORAL_VALIDATION.md](TEMPORAL_VALIDATION.md); il nuovo worker DSS/LTA,
condiviso fra Mac e Windows e con JVM private, è descritto in
[LONG_TERM_VALIDATION.md](LONG_TERM_VALIDATION.md). Linux resta senza una nuova
validazione hardware o GUI.
