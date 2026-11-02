# Compilazioni desktop con GitHub Actions

Il workflow **Desktop packages** prepara gli eseguibili e i pacchetti dello
stesso commit per tutte le piattaforme. Si avvia **soltanto manualmente**:
un push su main, una pull request o una modifica al numero di versione non
avviano compilazioni e non pubblicano release.

## Avvio e risultati

1. Aprire [Actions → Desktop packages](https://github.com/gezza-dev/firma-con-cie/actions/workflows/desktop-packages.yml).
2. Premere **Run workflow**, scegliere il ramo e `all`, `windows`, `macos`
   oppure `linux`.
3. Al termine scaricare gli artefatti dalla pagina dell’esecuzione. Il riepilogo
   distingue gli esiti dei sistemi: un errore macOS non annulla le build Windows
   o Linux già riuscite.

| Piattaforma | Ambiente di compilazione | Prodotti |
| --- | --- | --- |
| Windows x86_64 | Dipendenze su Ubuntu 24.04; test e app su Windows 2022 x64 | Installer EXE e cartella Release |
| Windows ARM64 | Dipendenze su Ubuntu 24.04; test e app su Windows 11 ARM64 | Installer EXE e cartella Release |
| macOS Universal | macOS 26 Apple Silicon, Xcode 26+; due architetture native nel bundle | DMG e ZIP dell’app, firmati Developer ID e notarizzati |
| Linux x86_64 | Runner Ubuntu x64, contenitori Ubuntu 24.04 / 22.04 | DEB, bundle e AppImage |
| Linux ARM64 | Runner Ubuntu ARM64, contenitori Ubuntu 24.04 / 22.04 | DEB, bundle e AppImage |

RPM Fedora e pacchetto Arch mantengono le ricette separate già documentate:
questo workflow automatizza DEB e AppImage per entrambe le CPU Linux.
Il bundle tar Linux e lo ZIP macOS conservano i permessi Unix; non distribuire
un `.app` o un bundle Linux ottenuto caricando i singoli file come artefatto ZIP
generico, che potrebbe perdere tali permessi.

Sono disponibili anche gli avvii manuali separati **Windows package**,
**Windows ARM64 package**, **macOS Universal package** e **Linux packages**.
I workflow richiamati non aggiungono trigger automatici.

## Configurazione iniziale Apple

La firma macOS richiede il certificato **Developer ID Application** con la
relativa chiave privata e l’accesso al servizio Apple di notarizzazione.
Non occorrono certificati CIE, PIN della carta o credenziali degli utenti.

Un amministratore del repository deve impostare i seguenti **Repository secrets**
in [Settings → Secrets and variables → Actions](https://github.com/gezza-dev/firma-con-cie/settings/secrets/actions).
Non inserirne i valori in chat, nei sorgenti, nei log o nei file di documentazione.

| Secret | Valore |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Certificato Developer ID Application e chiave privata esportati in P12, codificati base64 |
| `MACOS_CERTIFICATE_PASSWORD` | Password del P12 esportato |
| `MACOS_SIGNING_IDENTITY` | Nome completo Developer ID Application o impronta SHA-1 dell’identità di firma |
| `MACOS_TEAM_ID` | Team ID Apple di dieci caratteri, quello già usato dall’app e da CryptoTokenKit |

Per la notarizzazione scegliere **uno** dei metodi seguenti.

| Metodo | Secret aggiuntivi |
| --- | --- |
| Apple Account | `MACOS_NOTARY_APPLE_ID`: account Apple; `MACOS_NOTARY_PASSWORD`: password specifica per app, non la password principale |
| App Store Connect API | `MACOS_NOTARY_KEY_P8_BASE64`: chiave API P8 in base64; `MACOS_NOTARY_KEY_ID`: Key ID; `MACOS_NOTARY_ISSUER_ID`: Issuer ID per una chiave di team; omettere l’issuer per una chiave individuale compatibile |

Se entrambi sono configurati, la chiave API ha precedenza. La presenza di una
configurazione API incompleta fa fallire il controllo iniziale, senza passare
silenziosamente all’altro account. Un profilo notarytool conservato nel
Portachiavi del Mac personale non esiste sui runner GitHub e non viene copiato.

Sul Mac, dopo avere esportato personalmente il certificato da Accesso Portachiavi,
si può copiare il P12 codificato negli appunti con:

```sh
base64 -i /percorso/privato/certificato.p12 | tr -d '\n' | pbcopy
```

Incollare il risultato soltanto nel secret GitHub corrispondente. Lo stesso
procedimento vale per una chiave P8 già disponibile. Conservare i materiali
originali secondo le proprie procedure; non collocarli nella cartella del progetto.

Il workflow controlla prima della compilazione che la configurazione sia
completa. Se manca, il solo job macOS fallisce con l’elenco dei nomi necessari:
non viene prodotto un pacchetto ad hoc presentato come release funzionante.

## Firma e notarizzazione

Il job macOS usa un checkout, SDK Flutter, cache Dart e workspace in
`/private/tmp`, fuori dal profilo del runner. Ricompila le dipendenze nelle due
CPU, le unisce con i controlli esistenti e incorpora middleware, observer,
CryptoTokenKit, PKCS#11 e DSS con entrambe le JVM private.

Il certificato viene importato in un portachiavi temporaneo isolato. Il comando
per le credenziali non viene stampato e l’elenco originale dei portachiavi viene
ripristinato in uscita; uno step `always()` elimina anche i materiali di una
sessione interrotta. Nessun P12, P8 o portachiavi entra negli artefatti.

Si firma tutto il codice incorporato con Developer ID/Hardened Runtime secondo
gli script esistenti. La notarizzazione deve restituire `Accepted` per l’app,
poi per il DMG. Seguono applicazione e validazione dei ticket e valutazione
Gatekeeper. I checksum finali sono calcolati **dopo** lo stapling del DMG.
L’archivio ZIP conserva l’app già notarizzata e il componente di accesso ai siti.

## Test, versioni e conservazione dei dati

Le versioni di app e pacchetti derivano da `pubspec.yaml`; Flutter, dipendenze
native, PDFium e JVM restano fissati dai lock del progetto. Ogni piattaforma
ricompila anche il middleware: il solo eseguibile Flutter non è un pacchetto
completo. Windows verifica CPU del Dart SDK, degli EXE/DLL, snapshot AOT,
helper e JVM; Linux verifica il PDFium della CPU scelta e l’ABI del provider;
il DMG controlla le architetture Universal dell’app e del componente CTK.

Si eseguono analisi Flutter, test della GUI, test nativi con fixture, verifiche
DSS e controlli dei pacchetti. Windows usa installer isolati con helper finto;
Linux usa un database dpkg temporaneo e namespace privati per le CA sintetiche.
I contenitori non ricevono home personali, USB o socket PC/SC del runner.
Non si installa il componente di produzione sul computer dell’utente, né si
leggono carte o si modificano abbinamenti, preferenze o profili browser reali.

I pacchetti e i rapporti di validazione restano negli artefatti Actions per
14 giorni. I rapporti registrano commit, architettura, checksum ed esiti software;
il collaudo reale con CIE resta distinto. Una build riuscita non equivale a un
nuovo collaudo hardware o all’autorizzazione a pubblicare una release.
Prima di distribuire i nuovi pacchetti vanno completate anche le verifiche e
i materiali sorgente corrispondenti indicati in [RELEASE.md](RELEASE.md).

## Verifica locale dell’automazione

```sh
python3 scripts/test_desktop_ci.py
python3 scripts/test_windows_arm64.py
python3 scripts/test_product_identity.py
python3 scripts/test_macos_signing.py
actionlint
```

Questi test verificano selezione CPU, percorsi indipendenti, gestione riservata
delle credenziali, ripristino del portachiavi, rifiuto di notarizzazioni non
accettate e checksum successivi allo stapling. Le build complete dei nuovi
workflow richiedono i rispettivi runner; la prima build macOS firmata richiede
prima la configurazione dei secret Apple. Non sono dichiarate collaudate dalla
sola validazione YAML sul PC Windows.

Riferimenti: [runner GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job),
[workflow riutilizzabili](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[notarizzazione Apple](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
