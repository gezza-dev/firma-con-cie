# Collaudo CI Fedora e Arch — versione 1.0.1

Il workflow manuale [Linux distribution packages](https://github.com/gezza-dev/firma-con-cie/actions/workflows/linux-distributions.yml)
compila la GUI in container delle distribuzioni di destinazione. Middleware e
DSS sono prodotti su Ubuntu 24.04 per x86_64 e ARM64, conservando il controllo
ABI core24 dei provider browser. Il runtime trasferito deve corrispondere a
commit, CPU, checksum e hash dei sorgenti del checkout di destinazione.

Le immagini ufficiali Fedora 44 e Arch base-devel sono fissate per digest nei
Dockerfile; le versioni dei pacchetti installati nel container sono registrate
nei rapporti. I job lavorano senza home, sessione grafica, lettori o dispositivi
USB dell’host. Le build Windows, macOS, DEB e AppImage mantengono i workflow
già esistenti. [Guida](DESKTOP_CI.md) e [pacchetti nativi](LINUX_DISTRIBUTION_PACKAGES.md).

## Collaudo completo riuscito

[Actions 41490103835](https://github.com/gezza-dev/firma-con-cie/actions/runs/41490103835)
è concluso con **successo per tutti i job**, sul commit
`818e954bdf65ab142224da85e39296456f0718a2`, versione app **1.0.1+2**.
Ogni CPU supera tutti i 40 test nativi su Ubuntu 24.04. In ciascuno dei tre
container di destinazione l’analisi Flutter non segnala problemi e la suite
supera 446 test, con cinque prove opzionali saltate.

| Target | Pacchetto | Hash del payload ricontrollati localmente | ELF della CPU corretta |
| --- | --- | ---: | ---: |
| Fedora 44 x86_64 | `firma-con-cie-1.0.1-1.fc44.x86_64.rpm` | 737 | 61 |
| Fedora 44 aarch64 | `firma-con-cie-1.0.1-1.fc44.aarch64.rpm` | 736 | 60 |
| Arch Linux x86_64 | `firma-con-cie-1.0.1-1-x86_64.pkg.tar.zst` | 737 | 61 |

Tutti i target superano anche caricamento del runtime nativo, DSS/JVM privato,
controllo ABI del provider, i cinque scenari TLS, installazione, aggiornamento,
avvio grafico Xvfb e rimozione. Restano intatti i dati utente sintetici. I
rapporti attestano proprietari root, assenza di script di installazione
dell’app, hash del runtime installato e ispezione degli helper browser in
home vuote. Le catture Xvfb mostrano la Home renderizzata; sono state
controllate anche visivamente le schermate Arch e Fedora aarch64.

Dopo il download sono stati verificati i digest degli artefatti Actions e
dei pacchetti, i metadati RPM/Arch, tutti gli hash del payload e le intestazioni
ELF, leggendo gli archivi senza installarli sul PC Windows. I file originali
sono conservati insieme a `SHA256SUMS` e ai rapporti JSON. Le cartelle estratte
su Windows sono copie per ispezione: per installare usare gli archivi originali,
che conservano i metadati Unix. Il successivo commit documentale non cambia
la revisione `818e954` incorporata nei pacchetti.

| Pacchetto | SHA-256 |
| --- | --- |
| Fedora x86_64 | `c935c428f2ec301e64a9a21328bcbd8d523b0cbc60d91423dd595ae18b2938cc` |
| Fedora aarch64 | `282fef0761130a8467de321cdf6de78a8ea84b6756b01a5618ddb5767f7a39e7` |
| Arch x86_64 | `2c383b21b7e0cb60f691ca5c8cd08e59c8b4db4ec1b089e3b92d7fb404bcf8d1` |

## Primo risultato Arch verificato

L’esecuzione [41486363584](https://github.com/gezza-dev/firma-con-cie/actions/runs/41486363584),
commit `2a5b2b6ea89f42f92df23faa565eb82944207980`, completa il target Arch x86_64.
Il pacchetto `firma-con-cie-1.0.1-1-x86_64.pkg.tar.zst` è stato scaricato e
controllato senza installarlo sul PC Windows: **737 hash del payload** e
**61 intestazioni ELF x86_64** confrontati, insieme a metadati e checksum.

SHA-256: `1e08b84e318439b580ed56f351fea68fc18a31685984be442ccfcc6a9a678d48`.

I rapporti attestano installazione, aggiornamento da release `1` a `2`, rimozione,
proprietari root e conservazione di dati utente sintetici. La GUI è avviata su
Xvfb con PC/SC bloccato, con cattura verificata anche visivamente. Analisi
Flutter senza segnalazioni, 446 test superati e cinque prove opzionali saltate.
Superati anche i test nativi, DSS e i cinque scenari TLS isolati.

Nella stessa esecuzione Fedora produce GUI e RPM per entrambe le CPU, ma il test
TLS si ferma perché manca il comando `openssl`: `openssl-devel` contiene le
librerie, non il CLI. Questo esito è una build incompleta, non un pacchetto
Fedora dichiarato collaudato. La correzione è nel commit `818e954`, poi
verificato con successo come descritto sopra.

## Controlli e limiti

I test TLS verificano CA valida, CA sconosciuta rifiutata, nome host errato
rifiutato, proxy HTTPS attendibile e proxy HTTPS non attendibile rifiutato.
Le CA sintetiche esistono soltanto nel namespace del processo di prova;
l’archivio di fiducia dell’host non viene modificato. La fixture risolve il
percorso reale della cartella CA prima dei mount, conservando i symlink delle
distribuzioni e la compatibilità con le versioni recenti di bubblewrap.

Il secondo pacchetto di release `2` è una fixture con gli stessi binari e
non viene caricato tra gli artefatti utente. I rapporti diventano positivi
soltanto dopo test TLS e ciclo completo del pacchetto. Un avvio grafico Xvfb
non sostituisce il collaudo di un desktop completo, delle policy SELinux o
delle operazioni reali con CIE e browser: queste prove restano distinte.

Sono disponibili 14 regressioni dedicate a matrici, architettura RPM, archivi,
provenienza, prerequisiti e limiti dei test privilegiati. Il controllo locale
comprende anche i 19 test desktop CI, gli otto dell’identità del prodotto,
actionlint e il controllo dei sorgenti/licenze.

Non sono stati eseguiti accessi o firme con CIE, né installazioni sull’host.
Non sono stati pubblicati tag o release GitHub.
