# Compilazioni desktop con GitHub Actions

Il workflow **Desktop packages** prepara gli eseguibili e i pacchetti dello
stesso commit per tutte le piattaforme. Si avvia **soltanto manualmente**:
un push su main, una pull request o una modifica al numero di versione non
avviano compilazioni e non pubblicano release.

## Avvio e risultati

1. Aprire [Actions → Desktop packages](https://github.com/gezza-dev/firma-con-cie/actions/workflows/desktop-packages.yml).
2. Premere **Run workflow**, scegliere il ramo e `all`, `windows`, `macos`
   oppure `linux`. La scelta `linux-distributions` esegue soltanto Fedora e Arch.
3. Al termine scaricare gli artefatti dalla pagina dell’esecuzione. Il riepilogo
   distingue gli esiti dei sistemi: un errore macOS non annulla le build Windows
   o Linux già riuscite.

Se un job fallisce per un errore temporaneo di rete, la pagina dell’esecuzione
consente di ripetere il solo job fallito dopo il completamento del workflow.
La ripetizione usa lo stesso commit; gli artefatti degli altri target riusciti
rimangono disponibili. Per confrontare i pacchetti usare il commit nei rapporti
e i checksum, senza mescolare build di revisioni differenti.

| Piattaforma | Ambiente di compilazione | Prodotti |
| --- | --- | --- |
| Windows x86_64 | Dipendenze su Ubuntu 24.04; test e app su Windows 2022 x64 | Installer EXE e cartella Release |
| Windows ARM64 | Dipendenze su Ubuntu 24.04; test e app su Windows 11 ARM64 | Installer EXE e cartella Release |
| macOS Universal | macOS 26 Apple Silicon, Xcode 26+; due architetture native nel bundle | DMG e ZIP dell’app, firmati Developer ID e notarizzati |
| Linux x86_64 | Runner Ubuntu x64, contenitori Ubuntu 24.04 / 22.04 | DEB, bundle e AppImage |
| Linux ARM64 | Runner Ubuntu ARM64, contenitori Ubuntu 24.04 / 22.04 | DEB, bundle e AppImage |
| Fedora 44 x86_64 | Runner Ubuntu x64, container ufficiale Fedora 44 | RPM |
| Fedora 44 aarch64 | Runner Ubuntu ARM64, container ufficiale Fedora 44 aarch64 | RPM |
| Arch Linux x86_64 | Runner Ubuntu x64, container ufficiale Arch base-devel | `.pkg.tar.zst` |

Fedora e Arch sono richiamati anche dalle scelte `all` e `linux`. Il workflow
separato **Linux distribution packages** permette di scegliere `all`, `fedora`
o `arch`, sempre manualmente. Compila la GUI nella distribuzione di destinazione;
il middleware e DSS vengono compilati dallo stesso commit in Ubuntu 24.04,
separatamente per CPU, per conservare il limite ABI dei provider browser core24.
Il runtime trasferito è verificato per commit, CPU, checksum e hash dei sorgenti,
poi nuovamente caricato e provato nella distribuzione di destinazione.
Le immagini di base sono fissate per digest; il rapporto include il loro
inventario dei pacchetti. Dettagli: [LINUX_DISTRIBUTION_PACKAGES.md](LINUX_DISTRIBUTION_PACKAGES.md).
Gli artefatti `linux-distribution-runtime-*` sono intermedi di compilazione,
con strumenti di test e materiali per lo sviluppo. Per installare l’app
scaricare gli artefatti `firma-con-cie-linux-fedora-*` o
`firma-con-cie-linux-arch-*`: contengono il pacchetto utente, checksum,
manifesto e ricetta, con test e sorgenti delle dipendenze esclusi dal payload.
Il collaudo completo di Fedora e Arch è riuscito, incluse le prove dei pacchetti
nelle due CPU Fedora: [esiti e checksum](LINUX_DISTRIBUTION_CI_VALIDATION.md).
Il bundle tar Linux è un artefatto per sviluppo e riconfezionamento; per gli
utenti scegliere DEB o AppImage. Il bundle tar Linux e lo ZIP macOS conservano
i permessi Unix; non distribuire
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
Fedora e Arch eseguono installazione, aggiornamento di sola release del pacchetto,
avvio su Xvfb con PC/SC bloccato e rimozione in un secondo container Docker
marcato, conservando dati utente sintetici. L’artefatto per l’aggiornamento è
una fixture privata e non viene caricato tra i pacchetti utente. Lo script
mantiene anche il precedente modo rootless con namespace utente; il modo Docker
richiede un’opzione esplicita, i marcatori dell’immagine e l’assenza di interfacce CIE.
La compilazione e il confezionamento Linux girano come utente ordinario; il
solo test TLS usa un secondo contenitore root con capacità di creare namespace
di mount. Non usa una mappatura UID annidata, non modifica sysctl del runner e
non scrive nell’archivio CA dell’host. Il supporto ai namespace viene controllato
prima della compilazione. Il rapporto finale viene dichiarato riuscito soltanto
dopo il superamento anche di questa fase TLS.
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
workflow richiedono i rispettivi runner e i secret Apple per macOS. Il collaudo
ha eseguito realmente i target Windows, macOS e Linux, incluse firma Developer ID
e notarizzazione: esiti, commit e limiti sono registrati in
[DESKTOP_CI_VALIDATION.md](DESKTOP_CI_VALIDATION.md). I test locali e la sola
validazione YAML non sostituiscono queste esecuzioni complete.

Riferimenti: [runner GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job),
[workflow riutilizzabili](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[notarizzazione Apple](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
