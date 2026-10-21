# Confronto con il middleware CIE ufficiale

Il confronto iniziale seguente è conservato come fotografia dell'analisi.
L'implementazione successiva di C1/C3/C4/C5 è descritta in
[MIDDLEWARE_COMPATIBILITY_UPDATE.md](MIDDLEWARE_COMPATIBILITY_UPDATE.md).
C2 rimane escluso per conservare la gestione del PIN richiesta dall'utente.

Analisi dei sorgenti del 21 ottobre 2026, durante la preparazione di CIE ID
Desktop 1.0.0. Il confronto riguarda le funzioni e i controlli del middleware,
oltre ai percorsi dell'app necessari per usarli. Non confronta soltanto i nomi
delle funzioni esportate: alcune API ufficiali sono dichiarate ma restituiscono
«non supportato».

**La policy del nuovo PIN è intenzionale.** L'utente ha confermato che accettare
otto cifre anche uguali o consecutive è una propria scelta. La differenza
rispetto ai filtri delle app ufficiali non costituisce una mancanza da correggere.
Restano il controllo delle otto cifre e della conferma. La richiesta delle otto
cifre nel browser, invece delle quattro dell'ufficiale abbinato, è anch'essa
una scelta già richiesta e collaudata.

## Riferimenti e metodo

| Sistema | Release ufficiale | Commit esaminato |
| --- | --- | --- |
| Windows | [1.4.3.12](https://github.com/italia/cie-middleware/releases/tag/1.4.3.12) | `8dd385e9b867c98fa099df689e427cfd6cb06d44` |
| macOS | [v.1.4.3.13](https://github.com/italia/cie-middleware-macos/releases/tag/v.1.4.3.13) | `43da456fb3002e34beccda73b9bc4b149acae534` |
| Linux | [1.4.3.12](https://github.com/italia/cie-middleware-linux/releases/tag/1.4.3.12) | `a05337fc3ea3a526e6f173634c0f5ed0eb059859` |

I tre HEAD ufficiali sono stati risolti tramite API GitHub. Sono stati acquisiti
811 file di sorgente/configurazione pertinenti, verificando ogni blob rispetto
all'albero Git della revisione e registrando anche SHA-256. Acquisire un file
non equivale a revisionarne ogni riga: la lettura approfondita è concentrata su
IAS, ATR, abbinamento/SOD, PIN/PUK, minidriver, PKCS#11, CryptoTokenKit,
pubblicazione dei certificati, cache, firma/verifica e aggiornamenti.

Evidenze riproducibili esterne al repository:
`../reports/middleware-official-comparison-20261021/`: `references.json`,
`source-inventory.json`, alberi Git, copie dei sorgenti, diff IAS e risultati.
Il nostro punto di partenza Git è `131eedf2fb4d83b90ee00bf033fb3618704bd3a6`,
con le modifiche locali presenti alla data dell'analisi. Non è un audit dei
binari distribuiti da IPZS né un collaudo di tutte le carte e applicazioni.

## Differenze funzionali confermate

### C1 — Compatibilità CryptoAPI con AT_KEYEXCHANGE: parziale

Il minidriver ufficiale espone la stessa chiave anche attraverso il contenitore
CryptoAPI `AT_KEYEXCHANGE`; il nostro espone soltanto `AT_SIGNATURE`.
`keySizes()` e `signData()` rifiutano l'altro identificatore, il contenitore non
espone `pbKeyExPublicKey` e `cmapfile` non dichiara la relativa dimensione.
Il test isolato del nostro minidriver conferma esplicitamente il rifiuto.

Questo può impedire l'integrazione di programmi CryptoAPI meno recenti che
cercano la chiave con quell'identificatore. Non dimostra un guasto dei browser
già collaudati e **non significa aggiungere la decifratura RSA**, non supportata
nemmeno dal minidriver ufficiale. Priorità media, se si desidera compatibilità
con programmi esterni oltre ai browser provati.

Fonti: ufficiale [CSP.cpp](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/CSP/CSP.cpp)
(`CardReadFile`, `CardGetContainerInfo`, `CardSignData`);
nostri [minidriver.cpp](../native/platform/windows/web/minidriver.cpp)
(`keySizes`, `signData`, `containerInfo`, `readFile`) e
[test isolati](../native/platform/windows/web/minidriver_tests.cpp).

### C2 — API standard per cambio/sblocco PIN: non esposte dal componente Web

L'ufficiale implementa cambio e sblocco tramite minidriver Windows e tramite
PKCS#11 (`C_SetPIN`, `C_InitPIN`, con relative condizioni di login).
Il nostro componente Windows rifiuta esplicitamente i callback di modifica;
il modulo Linux Web non assegna quelle funzioni nella propria function list.

**Cambia PIN e Sblocca Carta nell'app sono presenti** e usano un percorso
dedicato con controllo della carta, un solo tentativo e invalidazione
dell'abbinamento. La differenza riguarda programmi esterni che vogliono gestire
il PIN attraverso le API standard, non la disponibilità delle due funzioni
nell'app. Il componente Web è volutamente limitato all'autenticazione/firma;
ampliarlo richiederebbe mantenere gli stessi controlli del percorso dedicato.
Nessuna estensione di quelle API è stata eseguita in questa attività.

Fonti: ufficiale `CSP.cpp` (`CardChangeAuthenticatorEx`, `CardUnblockPin`) e
[CIEP11Template.cpp](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/PKCS11/CIEP11Template.cpp)
(`CIEtemplateInitPIN`, `CIEtemplateSetPIN`); nostri `minidriver.cpp`,
[pkcs11.cpp](../native/platform/linux/web/pkcs11.cpp),
[pin_operations.h](../native/src/pin_operations.h) e
[pin_management.dart](../lib/pin_management.dart).

### C3 — PKCS#11 generale: compatibilità più ristretta

L'ufficiale Windows presenta PKCS#11 e minidriver nella stessa `CIEPKI.dll`.
Il nostro ingresso Windows collaudato è il minidriver/CSP/KSP: non distribuiamo
una `CIEPKI.dll` intercambiabile con quella ufficiale. Il backend privato
contiene codice PKCS#11 ereditato, ma la sua cache legacy è disattivata:
la sola presenza di `C_GetFunctionList` non prova un modulo sostitutivo pronto
per programmi esterni.

Il nostro modulo Linux per browser implementa ricerca degli oggetti, login,
firma singola/multipart, eventi e casualità; non espone `C_Digest*` o
`C_Verify*`, presenti nell'implementazione PKCS#11 ufficiale. Ciò limita alcuni
client PKCS#11 generici. **La verifica PDF/P7M dell'app resta presente**:
usa il motore documentale, non quei callback. Le API dichiarate dall'ufficiale
che terminano in «non supportato» non sono state conteggiate come vantaggi.

Fonti: [README ufficiale Windows](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/README.md),
[PKCS11Functions.cpp](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/PKCS11/PKCS11Functions.cpp),
`Mechanism.cpp` della stessa revisione; nostri `pkcs11.cpp` (`functionList`) e
[Cache.cpp](../native/backend/platform/Cache.cpp).

### C4 — Avviso preventivo di certificato scaduto: assente nel percorso Web

Il minidriver ufficiale confronta `NotAfter` con l'ora corrente durante la
lettura del contenitore e può mostrare una notifica di scadenza nel desktop.
Non si tratta, in quel punto, di un blocco crittografico della firma.
Il nostro minidriver non offre quell'avviso autonomo; i browser valutano il
certificato secondo le proprie regole. La Home non mostra una data/stato di
scadenza della carta abbinata.

La verifica dei documenti nel nostro motore controlla già validità temporale,
catena e revoca: l'assenza riguarda il preavviso nell'uso della carta/browser.
Priorità medio-bassa per un messaggio comprensibile prima di un accesso fallito.

Fonti ufficiali: `CSP.cpp` (`CardReadFile`),
[IAS.cpp](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/CSP/IAS.cpp)
(`IconaCertificatoScaduto`) e `CIEScaduta.cpp`;
nostri `minidriver.cpp`, [cie_web.cpp](../native/src/cie_web.cpp),
[CertificateTrust.cpp](../native/backend/cie_sign_sdk/src/Native/CertificateTrust.cpp).

### C5 — Ricerca di aggiornamenti: assente

L'installer ufficiale Windows registra un'attività all'accesso dell'utente e un
collegamento per controllare gli aggiornamenti; il codice `Update` consulta
la lista versioni del portale CIE. Il nostro installer aggiorna correttamente
app e componente quando viene eseguito un nuovo pacchetto, ma non cerca o
segnala nuove versioni. Non sono presenti aggiornamenti automatici equivalenti.
Priorità media per la manutenzione: un eventuale aggiornamento dovrà provenire
dal nostro progetto e verificarne provenienza/integrità.

Fonti: ufficiali [CIEMiddleware.nsi](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/Setup/CIEMiddleware.nsi),
`Setup/UpdateTask.xml` e
[update.cpp](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/CSP/update.cpp);
nostro [CIE-ID.iss](../packaging/windows/CIE-ID.iss).

## Controlli e funzioni riscontrati

| Ambito | Esito del confronto |
| --- | --- |
| Riconoscimento CIE | Stesse 12 firme ATR nei tre riferimenti e nel backend; catalogo Windows con ATR completi e maschere già derivato dall'ufficiale. Non equivale a 12 collaudi hardware. |
| IAS, Diffie-Hellman, DAPP, secure messaging | Tutti i metodi IAS dei riferimenti macOS/Linux sono presenti. Rispetto al macOS ufficiale, `IAS.cpp` differisce solo per tre include e due chiamate al minimo portabile. |
| PIN/PUK e tentativi residui | Percorsi dedicati presenti; controllo di identità prima dell'autenticazione, nessun tentativo privato automatico dopo un errore. Collaudo reale di cambio/sblocco ancora separato. |
| SOD SHA-256 e RSA-PSS/SHA-512 | Entrambi presenti. Il nostro abbinamento/Web aggiunge il confronto rigoroso dei sei DG e del certificato vivo. |
| Firma privata Web | RSA PKCS#1 v1.5 con SHA-256/384/512, verifica locale della firma restituita, identità/sessione vincolate. |
| RSA-PSS per login | Nessuna mancanza specifica rispetto al percorso di autenticazione ufficiale individuato; PSS del SOD non prova PSS con la chiave privata. Rimane valido [RSA_PSS_FEASIBILITY.md](RSA_PSS_FEASIBILITY.md). |
| SHA-1/MD5 per nuove firme Web | Esclusi deliberatamente dal nostro percorso Web. Non si propone di ripristinarli per imitare API legacy. |
| Decifratura, nuove chiavi, scrittura oggetti | Non supportate anche nei relativi percorsi ufficiali: nessuna funzione mancante da implementare sulla base del solo nome API. |
| Accesso a siti con app chiusa | Architettura presente in entrambi; i nostri componenti sono Windows CSP/KSP, macOS CryptoTokenKit e Linux PKCS#11. I precedenti login confermati restano le evidenze hardware. |
| Pubblicazione certificato Windows | Ufficiale: store provider/propagazione. Nostro: pubblicazione MY per utente durante abbinamento e recupero dai dati verificati. Diversa implementazione, stessa funzione per i browser collaudati. |
| PAdES, CAdES, firma grafica, estrazione, firme multiple | Presenti nel nostro prodotto; i riferimenti esaminati non evidenziano una funzione utente essenziale assente nei flussi PDF/P7M. Cofirma e controfirma crittografica sono operazioni distinte. |
| Catena, date e revoca documenti | Il nostro motore distingue integrità, fiducia, revoca e stato indeterminato; controlla le prove e non promuove una firma solo perché matematicamente integra. |
| Marche e validità storica | Ulteriori controlli del nostro motore e DSS/JVM dove incluso; rilevare un profilo LTA non significa validazione storica positiva. |
| Cache | Nostra cache per utente, AES-256-CBC con HMAC-SHA256, IV casuale, vincolo record/carta e controlli ACL/link. La chiave locale è un file, non un segreto isolato nel gestore credenziali. Il `CacheLib` pubblico Windows ufficiale è esplicitamente dimostrativo: non vi è un controllo DPAPI da esso presente e qui omesso. |
| Installazione/aggiornamento | Nostri controlli aggiuntivi su manifest, conflitti, proprietà e ripristino del registro; preservazione di cache, preferenze e certificati estranei. Nessuna CIE richiesta dall'installer. |

## Limiti condivisi e compatibilità da non sovrastimare

La firma del SOD e i digest sono verificati, ma il codice IAS legacy dei
riferimenti mantiene commentato il percorso di costruzione della catena CSCA.
Lo stesso vale per la nostra copia IAS. Non si deve descrivere quella sola
verifica come una validazione indipendente completa della catena del firmatario
del SOD; è un limite condiviso, non un controllo ufficiale che abbiamo rimosso.
La fiducia dei certificati documentali nel nostro motore è un percorso distinto.

Il pacchetto attuale Windows è x64 e il componente richiede ABI minidriver v7.
L'ufficiale ha sorgenti/progetti Win32 oltre a x64; il suo README parla anche
di distribuzione a 32 bit, mentre nell'NSIS esaminato alcune righe Win32 sono
commentate. Non è stata verificata una release ufficiale x86 attualmente
installabile. Il nostro pacchetto non attesta compatibilità con client x86 o
Windows ARM64 nativi. Sono limiti di distribuzione, non funzioni crittografiche
che si possano dichiarare mancanti solo dal README.

Non è stata individuata una sottrazione dei controlli essenziali di IAS/DAPP/SOD
nel perimetro revisionato. Questo risultato non costituisce una certificazione
di sicurezza, né esclude difetti nei parser o nelle dipendenze non revisionati
integralmente. Le differenze C1–C5 riguardano integrazioni e funzioni accessorie;
prima di ampliare il middleware occorre definire i client da supportare e
conservare i login già collaudati.

## Verifiche eseguite e modifiche consegnate

- Versione Flutter e pagina Informazioni: `1.0.0` (build `1`); installer `1.0.0`.
- Rimosso dalla Guida il link CIE ID Universal e le relative voci di traduzione.
  I riconoscimenti/licenze dovuti ai sorgenti riutilizzati rimangono presenti.
- Analisi Flutter senza errori e 30 test superati per Guida, traduzioni, temi,
  impostazioni di sistema e flussi base.
- Tre gruppi CTest Windows superati: 410 controlli catalogo/registro isolato,
  75 controlli di setup e 124 controlli del minidriver con carta simulata.
  Sono confermate anche le restrizioni documentate in C1/C2 e sugli algoritmi.
- Compilazione app Windows Release e installer completate; payload nativo e
  componente Web conservati, nessuna correzione automatica delle differenze
  C1–C5 applicata durante l'analisi.
- Nessuna operazione sulla CIE reale, richiesta PIN, modifica degli abbinamenti,
  installazione del nuovo pacchetto o tentativo di login in questa attività.

Ordine proposto per eventuali lavori successivi: valutare C1 con un client
CryptoAPI concreto, introdurre il preavviso C4, definire l'aggiornamento C5;
estendere C2/C3 soltanto se servono effettivamente programmi esterni che usano
quelle API. Le scelte deliberate sul PIN restano escluse.
