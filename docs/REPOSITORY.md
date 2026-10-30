# Preparazione del repository GitHub

Repository: [gezza-dev/firma-con-cie](https://github.com/gezza-dev/firma-con-cie), inizialmente **privato**.

Per aggiornare un checkout esistente dopo la rinomina, senza spostare cartelle
locali o cambiare i file di lavoro:

```sh
git remote set-url origin https://github.com/gezza-dev/firma-con-cie.git
git remote -v
git config --get-all remote.origin.pushurl
git ls-remote origin refs/heads/main
```

Se è configurato un `pushurl` separato, aggiornarlo con
`git remote set-url --push origin https://github.com/gezza-dev/firma-con-cie.git`
e verificare di nuovo entrambe le destinazioni. Non occorre rinominare il
checkout locale. Questi comandi non cambiano la visibilità del repository.

Descrizione:

> Applicazione desktop indipendente per la firma elettronica tramite Carta d’Identità Elettronica italiana (CIE). L'applicazione è compatibile con i sistemi Windows, macOS e Linux.

## Materiali da caricare

Sorgenti correnti, asset sintetici, icone, testi originali di licenza, documentazione e lockfile. Il repository ha una propria cronologia iniziale: non importa la storia dei vecchi progetti o i file rimossi dagli snapshot precedenti.

Le destinazioni personali di compilazione si configurano in `local-build.json` (vedere [BUILDING.md](BUILDING.md)); il file resta locale. Su GitHub si carica soltanto `local-build.example.json`, che contiene un esempio generico.

Sono esclusi runtime, output di compilazione, JAR/JVM, pacchetti Microsoft, identità/profili di firma, configurazioni locali, abbinamenti, report e documenti personali. I certificati CA pubblici versionati nel backend restano inclusi con provenienza e checksum. Il PDF `assets/prova.pdf` è una fixture sintetica; altri PDF e P7M sono ignorati.

Gli identificativi tecnici del package e del bundle non vengono rinominati: mantenerli conserva gli archivi protetti già creati dall’app.

## Controllo dello snapshot da caricare

Il controllo legge **l’indice Git**, cioè i contenuti effettivamente preparati per il commit, non una scansione generica delle cartelle di sviluppo. Prima verificare l’elenco dei file, poi preparare lo snapshot:

```sh
git status --short
git add .
python3 scripts/check_repository.py --report reports/repository-readiness.json
python3 scripts/prepare_repository.py --output dist/firma-con-cie-sources.zip
git diff --cached --stat
```

Il controllo verifica esclusioni, alcuni formati di credenziali, licenze richieste, copertura dei pacchetti Dart e JAR, hash dei testi Java e link della documentazione principale. Non sostituisce la lettura dei file e non garantisce di individuare ogni dato personale o segreto. Un file già tracciato non viene escluso retroattivamente dal solo `.gitignore`.

Lo ZIP contiene soltanto i blob dell’indice sotto la cartella `firma-con-cie/`, un manifest SHA-256 e il rapporto di verifica. Non contiene `.git`, configurazioni locali o vecchi oggetti Git; non è un installer né il pacchetto completo di sorgenti corrispondenti a una futura release binaria. L’output ZIP rimane locale e non viene aggiunto al commit.

## Caricamento

Verificare che il repository remoto sia ancora privato e che il remote sia quello corretto. Dopo il controllo del contenuto e il commit locale, il caricamento iniziale si esegue con:

```sh
git remote -v
gh repo view gezza-dev/firma-con-cie --json nameWithOwner,isPrivate
git push -u origin main
```

Questi comandi non cambiano la visibilità in pubblico. La preparazione dello snapshot non esegue automaticamente il push né crea release. Prima del caricamento usare un’identità Git appropriata, preferibilmente l’e-mail noreply del proprio account se si vuole mantenere privata quella personale.

Le workflow CI sono predisposte ad avvio manuale tramite Actions. Non vengono lanciate automaticamente compilazioni complete a ogni push. Non includono CIE, PIN, chiavi di firma o notarizzazione e non rappresentano un collaudo hardware.

Per rendere pubblico il repository o distribuire binari eseguire una verifica distinta dei materiali: vedere [LICENSING.md](LICENSING.md), [BUILDING.md](BUILDING.md) e [STATUS.md](STATUS.md).

## Download e ricerca aggiornamenti

I download appartengono alla pagina
[Release](https://github.com/gezza-dev/firma-con-cie/releases); il collegamento
all’[ultima release stabile](https://github.com/gezza-dev/firma-con-cie/releases/latest)
non incorpora un numero di versione. La prima release è preparata come bozza
nel repository privato. I download pubblici diventano disponibili dopo il
cambio di visibilità e la pubblicazione della release stabile, che rimangono
azioni distinte dalla preparazione dei materiali. [Procedura](RELEASE.md).

La ricerca manuale nell’app consulta
`https://api.github.com/repos/gezza-dev/firma-con-cie/releases/latest`, con
User-Agent `Firma-con-CIE/<versione>`. Accetta soltanto release stabili e link
HTTPS delle release di questo repository, senza redirect automatici, token,
download o esecuzione di pacchetti. Finché manca una release accessibile senza
autenticazione, segnala correttamente l’indisponibilità della verifica.
I pacchetti correnti contengono già questo riferimento. Aggiornare in futuro
i soli sorgenti o il remote non cambia i riferimenti di un binario compilato.
