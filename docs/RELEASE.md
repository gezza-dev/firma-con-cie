# Materiali e verifica delle release

Le nuove release di Firma con CIE sono preparate come bozze.
La preparazione non cambia la visibilità del repository e non pubblica automaticamente pacchetti.
Il tag stabile viene fissato soltanto dopo la verifica dei materiali definitivi.
I workflow di confezionamento raccolgono automaticamente i pacchetti nella
bozza della versione in `pubspec.yaml`, vincolata a un unico commit. Non
pubblicano release e rifiutano versioni già pubblicate. I trasferimenti intermedi
e la diagnostica restano in bozze **CI staging** separate, da non pubblicare.
I rapporti JSON di provenienza restano nella bozza `CI metadata <versione>`,
anch’essa da non pubblicare, e non sono allegati alla release utente.
Sorgenti del progetto, archivi delle dipendenze fissate e checksum vengono
aggiunti dal job dei metadati. Le vecchie release non vengono aggiornate.
Vedere [DESKTOP_CI.md](DESKTOP_CI.md) per avvio, visibilità e ripetizione dei job.
La versione in preparazione è **1.0.2** (build interna Flutter **3**). La 1.0.1
rimane l’ultima release pubblicata fino alla pubblicazione manuale della nuova
versione. La 1.0.0 rimane
documentata come prima release storica. I manifest conservano la revisione
effettiva di ciascun pacchetto e gli esiti software distinti dai collaudi con CIE.

## Contenuti

- Solo DMG Universal macOS, con `macOS` nel nome, firmato Developer ID Application, con app e contenitore notarizzati e ticket applicati. Lo ZIP dell’app non è un allegato da pubblicare.
- Installer Windows x64 e ARM64, con `windows` nel nome, con stato Authenticode dichiarato separatamente dalla firma Microsoft dei prerequisiti.
- AppImage Linux x86_64/AArch64 e pacchetti nativi disponibili per le distribuzioni documentate, con `linux` nel nome.
- Archivio dei sorgenti del progetto, esportato da uno snapshot controllato.
- Archivio separato dei sorgenti delle dipendenze: archivi nativi fissati, sorgenti OpenJDK completi e source JAR corrispondenti.
- Supplemento Linux con i sorgenti Ubuntu delle librerie e dei dati effettivamente inclusi nelle AppImage, più materiali di compilazione per entrambe le architetture. Le librerie fornite dal sistema restano distinte da quelle distribuite.
- `SHA256SUMS.txt` e checksum `.txt` per ciascun target e per i sorgenti.
  I manifest JSON con nomi, dimensioni, architetture, revisioni ed esiti verificati
  sono conservati soltanto nella bozza tecnica privata dei metadati.

I binari sono allegati alla release, non committati nei sorgenti. I file ZIP/tar
creati automaticamente da GitHub dal tag non contengono le dipendenze esterne:
non sostituiscono l'archivio separato dei sorgenti corrispondenti.

I pacchetti Linux non duplicano i source JAR Java nel runtime: i sorgenti
originali, incluse le annotazioni generate a monte, restano invariati in
`firma-con-cie_<versione>_dependency-sources.zip`. I JAR di produzione, i testi
di licenza e gli avvisi delle dipendenze restano inclusi nei pacchetti.

## Corrispondenza tra sorgenti e pacchetti

Per ciascun pacchetto si conserva la revisione di compilazione. Un pacchetto
collaudato da un commit precedente può essere riutilizzato soltanto quando il
confronto dei sorgenti e degli ingredienti relativi alla sua piattaforma prova
che non vi sono differenze funzionali. Il manifest dichiara la revisione reale;
non attribuisce al binario una ricompilazione mai avvenuta.

Gli archivi delle dipendenze native mantengono i propri testi e gli hash dei
lock. Sono inclusi i sorgenti completi OpenJDK della versione Temurin fissata,
non il solo `src.zip` delle classi Java. I source JAR sono separati e i JAR di
produzione restano sostituibili; per ricompilare o ricollegare si seguono le
ricette del progetto e si rigenerano i manifest della propria build. Una build
modificata va firmata con la propria identità oppure, per i soli test locali,
secondo le modalità ad hoc documentate. Non occorrono le chiavi del distributore.

## Controlli prima della pubblicazione

1. Verificare sorgenti effettivamente destinati al commit, avvisi e link con `scripts/check_repository.py`.
2. Controllare anche cronologia, log e artefatti Actions, considerando la visibilità corrente del repository.
3. Verificare nome/versione/architettura dei pacchetti, manifest interni e corrispondenza con i materiali sorgente.
4. Su macOS verificare firma Developer ID, Hardened Runtime e timestamp, accettazione Apple, ticket dell'app e del DMG e valutazione Gatekeeper. Calcolare gli hash dopo l'applicazione dei ticket.
5. Provare download e hash dei file allegati alla bozza, senza confondere una compilazione incrociata con un collaudo reale.
6. Solo al completamento dei controlli pubblicare la release stabile come ultima release, preservando la visibilità corrente del repository.

Il supplemento Linux conserva le versioni sorgente esatte per entrambe le architetture, compresi eventuali aggiornamenti differenti dello stesso pacchetto. I file originali e le patch Ubuntu sono verificati con SHA-256 e con i descriptor `.dsc`. I materiali di compilazione riportano le revisioni e le ricette realmente utilizzate: la CI corrente usa Flutter fissato su runner nativi, senza le vecchie patch SDK o wrapper QEMU della 1.0.0. L’archivio del progetto comprende anche gli snapshot delle revisioni effettive dei binari riutilizzati.

Le verifiche automatiche non vengono descritte come prove di accesso reali con
CIE. I dati personali, i documenti e i rapporti diagnostici locali non sono
allegati alla release; i riepiloghi pubblici contengono soltanto evidenze tecniche
necessarie alla verifica dei pacchetti.
