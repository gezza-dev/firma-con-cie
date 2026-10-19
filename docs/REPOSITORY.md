# Preparazione del repository GitHub

Repository: [gezza-dev/cie-id-desktop](https://github.com/gezza-dev/cie-id-desktop), inizialmente **privato**.

Descrizione:

> Applicazione desktop indipendente per la firma elettronica tramite Carta d’Identità Elettronica italiana (CIE). L'applicazione è compatibile con i sistemi Windows, macOS e Linux.

## Materiali da caricare

Sorgenti correnti, asset sintetici, icone, testi originali di licenza, documentazione e lockfile. Il repository ha una propria cronologia iniziale: non importa la storia dei vecchi progetti o i file rimossi dagli snapshot precedenti.

Sono esclusi runtime, output di compilazione, JAR/JVM, pacchetti Microsoft, identità/profili di firma, configurazioni locali, abbinamenti, report e documenti personali. I certificati CA pubblici versionati nel backend restano inclusi con provenienza e checksum. Il PDF `assets/prova.pdf` è una fixture sintetica; altri PDF e P7M sono ignorati.

Gli identificativi tecnici del package e del bundle non vengono rinominati: mantenerli conserva gli archivi protetti già creati dall’app.

## Controllo dello snapshot da caricare

Il controllo legge **l’indice Git**, cioè i contenuti effettivamente preparati per il commit, non una scansione generica delle cartelle di sviluppo. Prima verificare l’elenco dei file, poi preparare lo snapshot:

```sh
git status --short
git add .
python3 scripts/check_repository.py --report reports/repository-readiness.json
python3 scripts/prepare_repository.py --output dist/cie-id-desktop-sources.zip
git diff --cached --stat
```

Il controllo verifica esclusioni, alcuni formati di credenziali, licenze richieste, copertura dei pacchetti Dart e JAR, hash dei testi Java e link della documentazione principale. Non sostituisce la lettura dei file e non garantisce di individuare ogni dato personale o segreto. Un file già tracciato non viene escluso retroattivamente dal solo `.gitignore`.

Lo ZIP contiene soltanto i blob dell’indice, un manifest SHA-256 e il rapporto di verifica. Non contiene `.git`, configurazioni locali o vecchi oggetti Git; non è un installer né il pacchetto completo di sorgenti corrispondenti a una futura release binaria. L’output ZIP rimane locale e non viene aggiunto al commit.

## Caricamento

Verificare che il repository remoto sia ancora privato e che il remote sia quello corretto. Dopo il controllo del contenuto e il commit locale, il caricamento iniziale si esegue con:

```sh
git remote -v
gh repo view gezza-dev/cie-id-desktop --json nameWithOwner,isPrivate
git push -u origin main
```

Questi comandi non cambiano la visibilità in pubblico. La preparazione dello snapshot non esegue automaticamente il push né crea release. Prima del caricamento usare un’identità Git appropriata, preferibilmente l’e-mail noreply del proprio account se si vuole mantenere privata quella personale.

Le workflow CI sono predisposte ad avvio manuale tramite Actions. Non vengono lanciate automaticamente compilazioni complete a ogni push. Non includono CIE, PIN, chiavi di firma o notarizzazione e non rappresentano un collaudo hardware.

Per rendere pubblico il repository o distribuire binari eseguire una verifica distinta dei materiali: vedere [LICENSING.md](LICENSING.md), [BUILDING.md](BUILDING.md) e [STATUS.md](STATUS.md).
