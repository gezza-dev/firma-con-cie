# Validazione a lungo termine DSS/LTA

Il prototipo usa **EU DSS 6.5.1**, con il processo `ARCHIVAL_DATA`, per la
validazione di PAdES e CAdES. Il worker Java, la policy e il coordinatore Dart
sono gli stessi su macOS e Windows. Il middleware C/C++ continua a gestire carta,
firma e controlli nativi. Il worker è eseguito localmente con JVM Temurin 21
private, senza installare Java nel sistema e senza inviare documenti a servizi.

## Prove e risultati

DSS analizza DSS/VRI, certificati e risposte OCSP/CRL incorporati, marche della
firma e di archivio, revisioni PDF e rinnovi PAdES/CAdES archive-time-stamp-v3.
Applica i controlli di esistenza delle prove, catene e revoca nel tempo, oltre
alla policy crittografica mantenuta dal progetto DSS. Non basta trovare una
chiave DSS o il nome BASELINE-LTA nel documento.

Un esito LTA positivo richiede il profilo tecnico LTA, `TOTAL_PASSED`, processo
archivistico `PASSED` e ultima marca di archivio verificata. Per i PDF la policy
locale richiede anche che l'ultima marca copra la revisione corrente e rifiuta
modifiche di pagina/aspetto e modifiche indefinite rilevate da DSS. Una
successiva revisione non protetta richiede un nuovo rinnovo; non viene
automaticamente promossa a documento interamente protetto. Le firme si
riferiscono comunque ai rispettivi contenuti e ambiti di sottoscrizione.

L'esito LTA non è ricavato dal certificato valido oggi né dal solo `signingTime`.
Un firmatario o una vecchia TSA possono essere scaduti oggi: un rinnovo provato
e le opportune informazioni di revoca possono consentire la validazione
storica. Una TSA scaduta non può rendere attendibile da sola la propria vecchia
marca. Revoca antecedente alla prova, dati alterati o prove mancanti impediscono
un esito positivo. La policy di riferimento resta verificabile nei JAR DSS
originali e nei relativi sorgenti inclusi, non viene indebolita per i test.

`longTermStatus` distingue `passed`, `failed`, `indeterminate` e
`no_archive_data`. `allSignaturesLtaValid` è positivo solo per un insieme non
vuoto di firme tutte conformi ai requisiti. Il profilo rilevato e l'indicazione
DSS sono riportati separatamente. L'interfaccia distingue questo risultato dai
controlli attuali nativi e non presenta un controllo non disponibile come valido.

## Fiducia e connessioni

Il validatore usa la Root CA CIE ministeriale, le CA ufficiali di firma e TSA
della PKI Difesa e il `cacerts` Temurin fissato nel manifest, identici sulle due
piattaforme. Le CA Difesa sono scaricate indipendentemente via HTTPS dal
[portale istituzionale](https://pki.difesa.it/IT/default.aspx), confrontate con
le impronte pubblicate e fissate con SHA-256 in `trust/difesa/manifest.json`.
I file non provengono dal documento da verificare. Le SubCA CIE sono solo candidati.
I certificati contenuti nei documenti non diventano radici attendibili. Non
vengono modificati portachiavi o archivi Windows e non si sincronizzano Trusted
List europee: il controllo non attesta qualificazione eIDAS o valore legale.
Le radici di sistema del motore nativo e questa policy DSS hanno provenienze
separate ed esplicite, senza copiare certificati non attendibili dal documento.

L'elaborazione DSS resta locale. Sono abilitate le sole richieste GET delle CRL
indicate dai certificati tramite il helper C++ privato, con budget di 8 URL,
20 secondi, 24 MiB per risposta e 64 MiB di prove uniche ammesse; TLS verificato e socket
verso indirizzi privati/locali bloccate anche sui reindirizzamenti. Non si
carica il documento online e non si cercano automaticamente copie su archivi
Web. AIA, OCSP online e policy/certificati tramite URL restano disabilitati.
Senza helper o senza rete il verificatore usa le prove incorporate; il materiale
mancante non diventa un esito positivo. File detached senza contenuto esterno
fornito non diventano validi.

## Recupero CRL e verdetto storico condiviso

`CrlEvidence.java` applica la stessa policy sulle due piattaforme. Il risultato
`historicalStatus` è separato dagli esiti grezzi DSS e da `longTermStatus`.
Per un esito storico positivo servono una marca della firma autenticata da DSS,
il relativo riferimento accettato, le catene fidate e prove di revoca sufficienti
per tutti i certificati non radice del firmatario e della TSA. Si considera
l'intervallo di accuratezza della marca, includendo un secondo conservativo
per la precisione del tempo codificato. Accuratezza assente/non supportata,
revoca nell'intervallo o certificate validity insufficiente restano indeterminate.

Le CRL esterne devono essere complete, autentiche, attuali e prodotte dopo
l'intervallo della marca e l'emissione del certificato. Delta CRL, CRL indirette
o con ambito ristretto non sostituiscono una CRL completa. Per certificati oggi
scaduti si richiede `expiredCertsOnCRL` pertinente; dati incorporati più vecchi
possono essere coperti dal percorso archivistico LTA validato da DSS. La
sola emissione corrente di una CRL non la trasforma in un oggetto prodotto nel
passato, ma i suoi dati firmati possono contribuire alla validazione storica.

Revoche successive per motivi riconosciuti, come `superseded`, possono conservare
la validità alla marca. Il confronto include `invalidityDate`, quando presente.
Compromissioni senza data effettiva, sospensioni ambigue e motivi non riconosciuti
non autorizzano un esito positivo. Il controllo dei motivi sconosciuti riguarda
anche le risposte OCSP incorporate autenticate ed è indipendente dalla cache DSS.
Rete assente, errori TLS, dati alterati, limiti o prove insufficienti mantengono
un risultato storico indeterminato. `TOTAL_PASSED` da solo non è un verdetto storico.

Per il PDF reale di prova: la prima firma supera lo storico alle 11:19:57 UTC
del 10 dicembre 2020 con le CRL ufficiali recuperate; la seconda resta
`indeterminate / revocation_reason_unknown` per il motivo 7. Entrambe restano
prive di archivio LTA. Il precedente risultato offline è conservato sotto come
cronologia, non come esito della nuova integrazione.

## Processo e riproducibilità

I due motori leggono la stessa copia temporanea privata del documento. La copia
è rimossa al termine, anche in caso di errore o timeout. Un confronto del
contenuto con il file originale impedisce di usare risultati quando questo
cambia durante la verifica.

Il worker è lanciato senza shell e senza opzioni/agent Java ereditati, con heap
massimo 512 MiB, input massimo 256 MiB, limite di 128 firme/marche e output
massimo 4 MiB. Il coordinatore interrompe il worker al timeout; errori, memoria
insufficiente e output malformato non producono una validazione positiva.
Il worker emette un riepilogo senza nomi, seriali o certificati completi. I test
non richiedono carta, PIN, nuove firme CIE o servizi di marcatura esterni.

`scripts/build_ltv.py` costruisce il JAR condiviso, verifica i checksum delle
dipendenze e crea i runtime macOS (ARM64 e Intel) e Windows x64. JAR, sorgenti
Maven, avvisi e licenze Java sono inclusi separatamente. Il bundle Mac firma
anche launcher e librerie JVM. Le classi delle prove sintetiche sono in un JAR
separato, fuori dal classpath di produzione. Vedere `native/ltv/README.md` per
licenze, sorgenti e condizioni da completare prima di una distribuzione pubblica.

```bash
python3 scripts/test_ltv.py --runtime native/runtime/macos-lta --report reports/ltv.json
```

La suite genera localmente PDF e P7M con DSS/VRI, OCSP e CRL firmati e rinnovi
archivistici. Comprende firmatario/TSA originali scaduti, radice non attendibile,
marca finale alterata, pagina e DSS aggiunti dopo l'archivio e revoca antecedente
alla prova. La policy pubblica deve rifiutare la radice sintetica: non si
installano CA di prova. La prova positiva su documenti CIE reali marcati resta
separata: i PDF/P7M già prodotti non contengono materiale LTA.

## Documenti reali e campioni esterni — 16 ottobre 2026

La verifica è eseguita su macOS ARM64 e Windows x64, con esiti DSS coincidenti
e hash del worker e dell'archivio di fiducia identici. Il PDF reale fornito
per la verifica contiene due firme (`PKCS7-T` e
`PAdES-BASELINE-T`) e due marche della firma RFC 3161, del 10 dicembre 2020
alle 11:19:57 e 11:20:00 UTC. OpenSSL conferma indipendentemente l'integrità
di entrambe le firme CMS e dei due token temporali; il ricalcolo SHA-256 del
valore di ogni firma coincide con il `messageImprint` della relativa marca.
Questi controlli crittografici **non attestano fiducia, revoca o validità storica**.
Il file originale resta invariato e non viene caricato su servizi di validazione.

Non sono presenti dizionari DSS né marche di archivio: è un documento realmente
marcato, ma non un campione LTA. La prima revisione del worker restituiva per
entrambe le firme `no_archive_data`, `INDETERMINATE / NO_CERTIFICATE_CHAIN_FOUND`
e `allSignaturesLtaValid=false`, perché la policy CIE/Temurin non ricostruiva
le catene del Ministero della Difesa. La revisione con le CA ufficiali Difesa
permetteva al motore nativo di verificare entrambe le catene TSA; il worker offline
resta `INDETERMINATE / CERTIFICATE_CHAIN_GENERAL_FAILURE`, senza prove
archivistiche di revoca. Il controllo corrente autentica anche la revoca del
secondo firmatario dal 16 gennaio 2024, confermata da OpenSSL; lo stato attuale
non viene usato come prova sufficiente per il 2020. La validità storica e LTA
del documento restano indeterminate.
Le radici contenute nel documento non sono aggiunte all'archivio attendibile.
Uno dei certificati dei firmatari è scaduto oggi; la scadenza corrente, da sola,
non dimostra che una firma fosse invalida alla data della marca.

La prima prova ha evidenziato un limite del motore C++ preliminare: entrambe le
TSTInfo contengono un'estensione non critica `1.3.6.1.5.5.7.1.3`. Il controllo
`TS_TST_INFO_get_ext_count(info)>0` in `TemporalValidation.cpp` rifiutava qualsiasi
estensione con `timestamp_malformed_or_unsupported`; la GUI mostrava quindi
«Marca temporale non valida». Il messaggio non distingueva un formato non
supportato da una firma crittografica errata. Questo limite è corretto nella
revisione successiva del prototipo, separatamente dai problemi di fiducia.
Le estensioni non critiche sono permesse e restano protette dalla verifica
crittografica del token; duplicati e manomissioni sono rifiutati. Estensioni
critiche, versioni e algoritmi non supportati danno esito indeterminato con
motivazione specifica. La GUI distingue questi casi da una marca non valida e
spiega quando la catena TSA non è ricostruibile o attendibile. La presenza di estensioni
opzionali è prevista da [RFC 3161, §2.4.2](https://www.rfc-editor.org/rfc/rfc3161.html#section-2.4.2).

Sono esaminati anche quattro PDF pubblici del repository ufficiale
[EU DSS, commit 98ab6c1](https://github.com/esig/dss/tree/98ab6c136fc90bfca78352b4e673e2eae72b7d5a/dss-pades/src/test/resources/validation),
con URL e SHA-256 registrati localmente. Due contengono firme LuxTrust e marche
Universign; gli altri due usano un certificato commerciale di test Certipost.
I campioni Certipost sono riconosciuti `PAdES-BASELINE-LTA` con due/tre dizionari
DSS e due/tre marche di archivio. Le impronte risultano integre, ma la policy
di produzione restituisce `NO_CERTIFICATE_CHAIN_FOUND`, senza promuoverli a LTA
valido. Non si cambia la data di validazione per ottenere un esito positivo.

Queste prove non sostituiscono il test positivo completo su un documento reale
LTA, con catene attendibili, prove di revoca sufficienti e rinnovi validabili
alla data corrente. I casi LTA positivi della suite restano sintetici.

Riferimenti primari: [DSS 6.5.1](https://github.com/esig/dss/releases/tag/6.5.1),
[documentazione DSS](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/doc/dss-documentation.html),
[ETSI EN 319 142-1](https://www.etsi.org/deliver/etsi_en/319100_319199/31914201/01.02.01_60/en_31914201v010201p.pdf).
