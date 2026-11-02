# Collaudo delle compilazioni desktop 1.0.1

## Ambito

La procedura manuale descritta in [DESKTOP_CI.md](DESKTOP_CI.md) ricompila app,
middleware e pacchetti. Il collaudo usa runner GitHub distinti per CPU e sistema
operativo; non installa ambienti Linux o componenti di produzione sul PC
Windows dell’utente. Non sono state eseguite operazioni reali su CIE o PIN.

Le verifiche locali dell’automazione comprendono 19 test dedicati, le regressioni
Windows, i controlli dell’identità del prodotto, della firma macOS e del
confezionamento Windows. La sintassi dei workflow è controllata con actionlint.
I trigger restano esclusivamente manuali, senza pubblicazioni automatiche.

La prova unica **Desktop packages**, esecuzione `41468237696`, si è conclusa
con **successo** per tutti i target sul commit
`d43d3d78d2d405bb97662637d4ad02c22f99ab54`. Ha prodotto sette pacchetti utente:
due installer Windows, un DMG macOS e quattro pacchetti Linux.

## Pacchetti Windows dello stesso commit

Sorgenti: `d43d3d78d2d405bb97662637d4ad02c22f99ab54`, versione **1.0.1+2**;
[esecuzione Desktop packages](https://github.com/gezza-dev/firma-con-cie/actions/runs/41468237696).

| CPU | Hash del payload ricontrollati dopo il download | Oggetti controllati per CPU | Controlli isolati dell’installer |
| --- | ---: | ---: | ---: |
| x86_64 | 890 | 128 | 60 |
| ARM64 | 877 | 71 | 60 |

Per entrambe le CPU sono riusciti compilazione del backend, test nativi,
analisi e test Flutter, verifiche DSS/JVM e confezionamento. Dopo il download
sono stati verificati versione, checksum dell’installer, manifesti e 38 hash
dei sorgenti del componente rispetto al commit esatto.
Il log Windows x86_64 registra 434 test Flutter superati e 17 prove opzionali
saltate, con analisi senza segnalazioni.

Gli installer sono stati inoltre estratti e controllati senza eseguirli:
1.036 file per x86_64 e 1.063 per ARM64, con 104 archivi annidati per ciascuno,
senza rilievi sui percorsi dei profili personali. I test dell’installer usano
helper sintetici e verificano anche la conservazione dei dati di prova.

| Installer | SHA-256 |
| --- | --- |
| `firma-con-cie_1.0.1_windows_x64_setup.exe` | `d02f90e4c5f8fda5114c5b498988dcb816c26adab78ad3dbf501e56443c6a281` |
| `firma-con-cie_1.0.1_windows_arm64_setup.exe` | `ec03f3654d812dc57b4acfa7fda5bc801eea5a3923a2d1a2a09376a16de7a86c` |

## macOS Universal dello stesso commit

Anche il job macOS di `41468237696`, sul commit `d43d3d7`, ha completato la
compilazione Universal, firma e due notarizzazioni `Accepted`. Analisi Flutter
senza segnalazioni, 434 test superati e 17 prove opzionali saltate. Dopo il
download sono stati ricontrollati i due checksum finali, quattro binari
Universal, le due JVM private e versione/build dell’app.

SHA-256 del DMG `firma-con-cie_1.0.1_universal.dmg`:
`11c5fad3ae36a67519464df32f7dbce16e1b4f7634e27660c3ace2e9c892eb47`.

## Prime esecuzioni complete degli altri target

La build [macOS Universal 41459305309](https://github.com/gezza-dev/firma-con-cie/actions/runs/41459305309)
del commit `0efade9` ha completato firma Developer ID, notarizzazione accettata
dell’app e del DMG, applicazione/validazione dei ticket e valutazione Gatekeeper.
I secret configurati dall’utente sono stati quindi verificati realmente sul
runner Apple. L’archivio scaricato contiene quattro componenti Mach-O Universal
controllati e due JVM private corrispondenti alle rispettive CPU. I checksum
sono riferiti ai file finali, successivi alla notarizzazione.

La build [Linux 41464877476](https://github.com/gezza-dev/firma-con-cie/actions/runs/41464877476)
del commit `d43d3d7` ha completato tutti e quattro i target: DEB e AppImage,
ciascuno per x86_64 e ARM64. Ha eseguito analisi/test Flutter, 40 test nativi,
verifiche DSS e test TLS isolati. I DEB sono controllati con database dpkg
temporanei; gli AppImage includono il controllo dell’ABI e del payload.

La prima esecuzione unica sullo stesso commit ha incontrato un errore di rete
nel download ufficiale di GNU libiconv per il solo AppImage x86_64. Il precedente
collaudo completo dello stesso target era riuscito; l’errore di trasporto non
è stato classificato come un controllo software superato. Dopo il completamento
degli altri target è stato ripetuto il solo job fallito, sullo stesso commit:
il secondo tentativo è riuscito e il workflow complessivo risulta verde.

## Linux dello stesso commit

Anche nell’esecuzione unica `41468237696` sono riusciti tutti e quattro i target.
Il log DEB x86_64 registra analisi senza segnalazioni, 446 test Flutter superati
e cinque prove opzionali saltate, oltre a tutti i 40 test nativi.

I rapporti TLS attestano cinque scenari su loopback: destinazione con CA valida,
CA sconosciuta rifiutata, nome host errato rifiutato, proxy HTTPS attendibile e
proxy HTTPS non attendibile rifiutato. La verifica non modifica l’archivio CA
dell’host. Il risultato finale software viene emesso solo dopo questi controlli.

Dopo il download sono stati confrontati checksum e commit dei quattro
pacchetti. I DEB sono stati aperti senza installarli e sono stati ricontrollati
737 hash del payload x86_64 e 736 ARM64, con proprietari root nel pacchetto.
Per gli AppImage il runner verifica tutti gli hash del payload e l’ABI massima
glibc 2.35; sul PC Windows sono stati ricontrollati il checksum dell’intero file,
il runtime fissato dal lock della CPU corretta e la struttura SquashFS.

| Formato | x86_64 | ARM64 |
| --- | --- | --- |
| DEB | Compilato, testato, scaricato e verificato | Compilato, testato, scaricato e verificato |
| AppImage | Compilato, testato, scaricato e verificato | Compilato, testato, scaricato e verificato |

I file SHA256SUMS e i rapporti JSON accompagnano i pacchetti negli artefatti
Actions. I pacchetti locali conservano gli stessi byte dei prodotti verificati.
Il successivo commit documentale registra gli esiti e non ricompila né cambia
la revisione `d43d3d7` incorporata nei pacchetti.

## Limiti del collaudo

I risultati attestano compilazione, test software e integrità dei pacchetti,
senza sostituire il collaudo hardware degli accessi ai siti, delle firme e
dell’abbinamento su ciascun sistema. I dati utente, gli archivi CA dell’host e
i profili browser reali non sono stati modificati. Gli archivi Linux del bundle
sono artefatti per sviluppo e riconfezionamento; DEB e AppImage sono i pacchetti
destinati agli utenti. RPM e Arch conservano le ricette manuali separate.

Non sono stati creati tag né pubblicate o aggiornate release GitHub.
