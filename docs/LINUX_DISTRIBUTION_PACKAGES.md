# Pacchetti Linux di test per distribuzione — x86_64

I formati previsti sono `.deb` per Ubuntu/Debian, `.rpm` per Fedora e
`.pkg.tar.zst` per Arch Linux. Non sono pubblicazioni nei repository delle
distribuzioni. Ogni dichiarazione di compatibilità si riferisce alle versioni
e alle prove riportate qui, non a tutte le distribuzioni o architetture.

## Contenuto e comportamento

I tre formati condividono la validazione e la preparazione del contenuto in
`scripts/linux_package_common.py`: app Flutter, runtime nativo, provider
PKCS#11, DSS con Java privato, launcher, icone e documentazione con licenze.
Restano i percorsi `/opt/firma-con-cie`, `/usr/bin/Firma con CIE` e
`/usr/share/doc/cie-id-desktop`. I programmi di test sono esclusi.

L'installazione non avvia l'app, non registra moduli nei browser, non collega
permessi Snap e non legge la CIE. Le configurazioni browser restano attivabili
dall'utente nella Home. Nessuno script di installazione o rimozione modifica
gli abbinamenti, le preferenze o i documenti dell'utente. I normali hook delle
distribuzioni aggiornano le cache di menu e icone.

Le dipendenze sono determinate nell'ambiente della distribuzione: il `.deb`
usa `dpkg-shlibdeps`; l'RPM usa le dipendenze ELF di RPM, escludendo le librerie
private già incluse; Arch risolve le librerie di sistema nei pacchetti che le
possiedono. Per RPM e Arch tutti gli ELF devono essere x86_64 e risolversi
contro le librerie della distribuzione prima della creazione del pacchetto.
PC/SC, Python, strumenti NSS e CA sono dichiarati esplicitamente. Il driver
CCID è raccomandato/opzionale secondo il formato.
EGL, OpenGL e GLES sono dipendenze esplicite: GTK/libepoxy le caricano anche
dinamicamente, quindi non basta l'analisi delle dipendenze ELF. I driver grafici
restano quelli del sistema; i collaudi virtuali usano Mesa software.

## Costruzione

Usare ambienti puliti delle distribuzioni di destinazione, senza montare
home reale, profili browser, `/run/pcscd`, USB o socket della sessione grafica.
Il bundle di ingresso deve essere compilato su una base compatibile e ogni
componente nativo riutilizzato deve conservare manifest e provenienza.
Condividere un bundle tra distribuzioni richiede la verifica dell'ABI e dei
caricamenti in ognuna; la sola estensione del pacchetto non dà compatibilità.

Esempi dalla radice dei sorgenti, all'interno dell'ambiente appropriato:

```sh
python3 scripts/package_linux_deb.py --bundle /bundle --output /output/deb \
  --version '0.1.0~test20261024.19'
python3 scripts/package_linux_distribution.py --format rpm \
  --bundle /bundle --output /output/rpm --version '0.1.0~test20261024.19'
python3 scripts/package_linux_distribution.py --format arch \
  --bundle /bundle --output /output/arch --version '0.1.0~test20261024.19'
```

Per Fedora servono `rpm-build`, Python, binutils, gli strumenti desktop e le
dipendenze del bundle. Per Arch servono `base-devel`, Python, binutils e le
dipendenze del bundle; eseguire `makepkg` come utente ordinario, con fakeroot.
La ricetta `.spec` e il `PKGBUILD` generati sono conservati insieme al manifest
del pacchetto e ai checksum. Le librerie private non diventano fornitori
globali RPM e i tool di packaging non modificano i binari già verificati.

L'identità dei sorgenti esportati senza `.git` può essere fornita dal file
locale `.linux-package-source.json`: `baseCommit`, `workingTreeModified` e
`sourceDateEpoch`. Va prodotto dalla copia Git originale e conservato con gli
hash dello snapshot e il digest delle immagini di compilazione. Non attribuire
le modifiche locali o i binari nativi riutilizzati a un commit successivo.

## Pacchetti di test del 24 ottobre 2026

GUI Release ricompilata con Flutter 3.47.7 e due job in Ubuntu 24.04 LTS;
sorgenti applicativi del commit `b12a1c242dd2272bfbc490c6cb2142f75a8d98d2`,
con modifiche locali agli strumenti di packaging e alla documentazione.
Il runtime nativo/DSS rimane byte per byte quello già verificato: 714 file
confrontati prima del confezionamento, con manifest originale conservato.
Non è attribuito al nuovo lavoro di packaging una nuova compilazione del middleware.

| Artefatto x86_64 | Ambienti di verifica |
| --- | --- |
| `cie-id-desktop_0.1.0~test20261024.19_amd64.deb` | Ubuntu 24.04 LTS e Debian 13 |
| `cie-id-desktop-0.1.0-0.test20261024.19.fc44.x86_64.rpm` | Fedora 44 |
| `cie-id-desktop-0.1.0_test20261024.19-1-x86_64.pkg.tar.zst` | Arch rolling, snapshot del 24 ottobre 2026 |

Verificati in ogni ambiente 737 file installati, 61 ELF, proprietario root,
hash del runtime, icone/launcher, provider Snap e analisi DSS con Java privato
di un PDF sintetico non firmato. Superati installazione, aggiornamento a una
seconda versione di sola prova e rimozione con dati utente sintetici conservati.
Entrambi gli helper browser sono stati ispezionati in sola lettura con home
vuote. La GUI Release è stata avviata e acquisita su Xvfb con PC/SC bloccato;
il processo e il suo observer sono stati terminati nella sola radice di test.
Superato lo smoke nativo senza `--detect` in tutti e quattro gli ambienti.

Gli 11 test del confezionamento coprono corruzioni, file inattesi, percorsi non
validi, link/permessi privilegiati, esclusione dei test, dipendenze grafiche
caricate dinamicamente e rifiuto di installare fuori dalle radici marcate.
Un ulteriore test verifica l'avvio di Xvfb quando il numero del display e il
terminatore arrivano separatamente: in totale 12 test Python superati,
ripetuti anche prima del commit degli strumenti.
La suite Flutter conta 331 test superati, incluse quattro integrazioni native,
con analisi senza problemi. Rimane il warning di hit-test già noto in
`pairing_test.dart`. Nessun test fallito o saltato in questa suite.

Le immagini ufficiali OCI sono state verificate tramite digest e SHA-256 dei
layer, senza installare motori container sull'host. Le prove usano bubblewrap,
namespace utente con un solo UID, `/run` e `/tmp` privati e nessun dispositivo
USB o socket PC/SC. Solo per predisporre gli strumenti nelle radici minime,
gli UID/GID di servizio non rappresentabili sono stati mantenuti al proprietario
locale; questo adattamento non è usato nelle prove dei pacchetti dell'app.
Le esclusioni di documentazione delle immagini minime sono disattivate solo
nelle transazioni di test, per poter confrontare l'intero contenuto installato.

Digest delle immagini, inventari delle dipendenze, snapshot dei sorgenti,
checksum dei pacchetti, log e catture restano in `reports/linux-multidistro`
e `.build/linux-multidistro`, esclusi da Git. I pacchetti di test non sono
firmati né pubblicati. Al termine di queste prove isolate la versione `.18`
installata sull'host era rimasta invariata; nessuna configurazione browser,
permesso Snap o prova sulla CIE era stata eseguita.

Successivamente, su richiesta dell'utente, sono stati installati su questo
computer il `.deb` `.19` e poi il `.deb` `.20`, che include il nuovo menu
condiviso con hover e puntatore a mano. Per la `.20` sono stati verificati
737 file installati e l'utente ha confermato il collaudo dell'interfaccia.
Gli artefatti RPM e Arch elencati sopra restano alla `.19`, precedente alla
modifica del menu. Questi aggiornamenti non estendono a Fedora e Arch il
collaudo dell'interfaccia della `.20`. Vedi [stato e collaudi](STATUS.md).

## Verifiche e limiti

Controllare checksum, contenuto, proprietario root, assenza di script invasivi,
icone/launcher, risoluzione degli ELF, provider Snap e Java/DSS privato.
Le prove di installazione, aggiornamento e rimozione vanno eseguite soltanto
in radici isolate. I collaudi grafici possono usare un display virtuale senza
lettore. Il desktop completo, le policy SELinux di Fedora e le prove reali
di firma/accesso ai siti richiedono collaudi distinti prima di una release.
La disponibilità di un pacchetto non certifica questi collaudi né completa
gli adempimenti di distribuzione descritti in [LICENSING.md](LICENSING.md).

`scripts/test_linux_distribution_package.py` richiede una radice usa e getta
marcata `/.cie-isolated-root` e un namespace utente diverso dall'host prima
di invocare qualsiasi gestore pacchetti. Riceve un artefatto e un secondo
artefatto di versione maggiore tramite `--upgrade-package`, oltre al formato,
al percorso del rapporto e alla guardia PC/SC di test. Non creare il marcatore
sull'host e non usare questa procedura sulla propria installazione desktop.
