# Materiali e verifica delle release

Le release di Firma con CIE sono preparate come bozze nel repository privato.
La preparazione non cambia la visibilità e non pubblica automaticamente pacchetti.
Il tag stabile viene fissato soltanto dopo la verifica dei materiali definitivi.

## Contenuti

- DMG Universal macOS firmato Developer ID Application, con app e contenitore notarizzati e ticket applicati.
- Installer Windows x64 e ARM64, con stato Authenticode dichiarato separatamente dalla firma Microsoft dei prerequisiti.
- AppImage Linux x86_64/AArch64 e pacchetti nativi disponibili per le distribuzioni documentate.
- Archivio dei sorgenti del progetto, esportato da uno snapshot controllato.
- Archivio separato dei sorgenti delle dipendenze: archivi nativi fissati, sorgenti OpenJDK completi e source JAR corrispondenti.
- Supplemento Linux con i sorgenti Ubuntu delle librerie effettivamente incluse nelle AppImage e materiali di compilazione ARM64. Le librerie fornite dal sistema restano distinte da quelle distribuite.
- `SHA256SUMS.txt` e manifest pubblico di provenienza con nomi, dimensioni, architetture, revisioni di compilazione ed esiti verificati.

I binari sono allegati alla release, non committati nei sorgenti. I file ZIP/tar
creati automaticamente da GitHub dal tag non contengono le dipendenze esterne:
non sostituiscono l'archivio separato dei sorgenti corrispondenti.

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
2. Controllare anche la cronologia e i log/artefatti Actions: il passaggio a pubblico rende visibili i materiali conservati da GitHub.
3. Verificare nome/versione/architettura dei pacchetti, manifest interni e corrispondenza con i materiali sorgente.
4. Su macOS verificare firma Developer ID, Hardened Runtime e timestamp, accettazione Apple, ticket dell'app e del DMG e valutazione Gatekeeper. Calcolare gli hash dopo l'applicazione dei ticket.
5. Provare download e hash dei file allegati alla bozza, senza confondere una compilazione incrociata con un collaudo reale.
6. Solo al completamento dei controlli rendere pubblico il repository e pubblicare la release stabile come ultima release.

Il supplemento Linux conserva le versioni sorgente esatte per entrambe le architetture, compresi eventuali aggiornamenti differenti dello stesso pacchetto. I file originali e le patch Ubuntu sono verificati con SHA-256 e con i descriptor `.dsc`. Le modifiche agli strumenti Flutter sono fornite separatamente con revisioni e istruzioni di applicazione.

Le verifiche automatiche non vengono descritte come prove di accesso reali con
CIE. I dati personali, i documenti e i rapporti diagnostici locali non sono
allegati alla release; i riepiloghi pubblici contengono soltanto evidenze tecniche
necessarie alla verifica dei pacchetti.
