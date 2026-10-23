# Configurazione guidata Firefox su Linux

**Configura Firefox** è disponibile solo in cima alla **Home**, anche senza
lettore o carta, se occorre configurare/aggiornare un profilo inizializzato,
correggere un conflitto o
verificare/autorizzare il permesso Snap. Se tutti i profili utilizzabili sono
configurati e il permesso Snap è collegato, il riquadro scompare. Anche l'assenza
di profili utilizzabili lascia la Home senza il riquadro. Se lo stato non è
leggibile, il riquadro resta disponibile per la diagnosi dalla procedura.
Il riquadro non compare nella pagina **Impostazioni**.

Il controllo automatico usa esclusivamente l'ispezione in sola lettura:
all'apertura della Home, al ritorno nell'app e alla chiusura della procedura.
Non carica moduli NSS, non registra dispositivi e non legge la CIE. Non ci
sono tentativi periodici; la registrazione richiede sempre la conferma
personale. La procedura riguarda Firefox desktop non confinato
e l'istanza Snap standard `firefox`. Non configura Chrome o altri browser.
La sola installazione del `.deb` non modifica alcun profilo o permesso Snap.

La lista della procedura mostra solo i profili ancora da configurare: quelli
già pronti e quelli non inizializzati sono esclusi. Se sono tutti pronti,
compare «Non ci sono profili da configurare». Un permesso Snap mancante
resta disponibile separatamente, senza registrare di nuovo alcun profilo.
Dopo la selezione «Rileggi profili» è nascosto; dopo una configurazione
riuscita il profilo viene rimosso dalla lista.

La ricerca usa gli indici `profiles.ini`, indipendentemente dalla posizione
del programma Firefox (anche se estratto nella cartella Download):

- Firefox desktop: `~/.mozilla/firefox`, `~/.config/mozilla/firefox` e
  `$XDG_CONFIG_HOME/mozilla/firefox` se il percorso assoluto è nella home.
- Firefox Snap: `~/snap/firefox/common/.mozilla/firefox` e il corrispondente
  percorso `~/snap/firefox/common/.config/mozilla/firefox`.

I profili presenti in più indici vengono elencati una sola volta per tipo
di browser. Un errore di lettura viene mostrato come errore, senza il messaggio
fuorviante «nessun profilo». I profili non ancora inizializzati, privi di uno
dei file `cert9.db`, `key4.db` o `pkcs11.txt`, sono esclusi dalla lista e non
fanno comparire il riquadro nella Home. Non vengono inizializzati, eliminati
o modificati. Un profilo inizializzato con configurazione danneggiata resta
visibile per consentire la diagnosi.

## Procedura nell'app

1. Aprire **Configura Firefox**. L'app legge l'elenco dei profili Firefox e
   Firefox Snap già esistenti, senza caricare moduli NSS o leggere la carta.
   Se non ci sono profili, avviare e chiudere il browser desiderato e premere
   **Rileggi profili**. L'app non crea nuovi profili.
2. Scegliere esplicitamente il profilo. Non viene selezionato automaticamente
   un profilo predefinito o quello della prima installazione trovata.
3. Premere **Continua** e leggere il riepilogo. Questo passaggio
   non scrive nel profilo e non copia librerie.
4. Chiudere tutte le finestre/processi Firefox. Premere **Configura profilo**, poi **Configura** nella conferma finale. Annullando non viene
   applicata alcuna modifica.
5. Per Snap, se il permesso non è già collegato, usare **Autorizza lettore** dopo la registrazione. C'è una conferma separata;
   l'eventuale password amministrativa va inserita soltanto nella finestra
   del sistema. Il comando è limitato a `snap connect firefox:pcscd`.
6. Riaprire Firefox quando si vuole usare il modulo. Per Snap completare
   anche la preparazione del certificato pubblico dalla Home, con **Completa
   accesso ai siti** se necessario. Registrare il modulo non equivale a
   preparare un'identità o ad aver effettuato un accesso a un sito.

La procedura non chiede PIN, non avvia Firefox, non apre siti e non esegue
autenticazioni o firme. Il successivo browser richiede il PIN completo di
otto cifre. Abbinamenti, prefissi PIN e certificati della CIE non vengono
letti o modificati dalla procedura di registrazione.

## Ambito delle modifiche

Viene aggiornato soltanto il `pkcs11.txt` del profilo scelto. I database
`cert9.db` e `key4.db`, preferenze, password, segnalibri, CA e altri moduli
restano conservati. Non si applicano policy globali, non si modificano TLS,
AppArmor o gli archivi NSS di Chrome. Profili gestiti da policy possono
richiedere l'intervento del loro amministratore.

Il profilo deve appartenere all'utente corrente, senza percorsi simbolici o
file condivisi/scrivibili da altri. Il solo indice `profiles.ini`, letto ma
mai modificato, può avere i normali permessi 0664 creati da Firefox su Ubuntu:
viene trattato come elenco non attendibile e non come destinazione di scrittura.
Directory del profilo e file NSS selezionati mantengono i controlli più
restrittivi; indici scrivibili da tutti o simbolici sono rifiutati.
Sono supportati profili relativi e
assoluti entro la home; i profili Snap devono essere nel suo `common`.
Percorsi esterni, Flatpak e istanze Snap parallele richiedono una procedura
distinta. Per evitare concorrenza vengono controllati i processi Firefox e
acquisito il blocco POSIX del profilo. Un riepilogo diventato obsoleto non
può essere applicato: occorre prepararlo di nuovo e confermarlo.

Una registrazione riconoscibile come appartenente a questa app viene
aggiornata conservandone il nome. Registrazioni ambigue, librerie non
riconoscibili, duplicati o un proxy p11-kit non verificato causano un errore
senza sostituire moduli. Un modulo p11-kit di sola fiducia non è un proxy
smart card e resta conservato. Nei conflitti, controllare personalmente i
dispositivi di sicurezza di Firefox prima di riprovare. Non vengono rimossi
automaticamente middleware ufficiali o registrazioni estranee.

Per recupero viene conservata una copia privata della precedente sola
configurazione moduli in `cie-firefox-setup-backup.json`, all'interno del
profilo. Non vengono copiati i database dei certificati o delle chiavi.
Un errore durante la generazione NSS lascia invariata la configurazione
originale; non vengono eseguiti tentativi automatici.

## Firefox Snap e aggiornamenti

La procedura copia soltanto `libcie_linux_pkcs11.so`, `libcie_web.so` e
`libcie-pkcs11.so`, verificate contro il manifest del runtime, in:

```text
~/snap/firefox/common/firma-con-cie-module-v1/<digest-delle-tre-librerie>/
```

La directory è privata (0700), i tre file e il marcatore di proprietà sono
0600. Le generazioni precedenti vengono conservate; un contenuto esistente
alterato o non riconoscibile non viene sovrascritto. Non sono copiati helper,
guardie PC/SC, archivi di abbinamento, chiavi o certificati personali.

Dopo un aggiornamento dell'app, riaprire la procedura a browser chiuso per
aggiornare la registrazione Snap alla generazione corrispondente. Per Firefox
desktop viene usata la libreria nel bundle corrente: mantenere l'app in un
percorso stabile. La procedura è idempotente se la registrazione coincide.
Il 23 ottobre 2026 l'utente ha confermato il collaudo della Home condizionale
e della lista dei profili, e successivamente l'accesso ai siti con Firefox
dopo l'installazione della versione `.7`. La variante standard/Snap di
quest'ultimo esito non è stata distinta nella conferma. Restano separati i
precedenti login Firefox e Firefox Snap con PIN completo e configurazione
manuale, già confermati dall'utente. La verifica dell'icona nella barra del
titolo sui diversi desktop resta un collaudo visivo distinto.

## Implementazione e test senza CIE

`lib/firefox_setup.dart` gestisce il dialogo e richiama il solo helper Python
incorporato nel runtime. I comandi non vengono costruiti tramite una shell.
Gli errori mostrano codici tradotti, senza esportare dati del profilo. Il
monitor della carta dell'app viene sospeso mentre il dialogo è aperto.

`native/platform/linux/browser_setup/firefox_setup.py` legge `profiles.ini`
e prepara un piano legato a profilo, hash della configurazione e runtime.
L'helper usa NSS per generare il record in un database moduli temporaneo
vuoto: il normale inserimento diretto può inizializzare anche moduli estranei.
Il solo record CIE generato viene inserito/sostituito atomicamente nel file
originale, conservando i byte delle altre voci. Il processo NSS riceve una
guardia PC/SC privata verificata, caricata tramite descrittore ereditato per
supportare percorsi con spazi. La guardia non viene installata nei browser,
non modifica pcscd e non influenza i loro successivi avvii.

Test software:

```sh
flutter test --no-pub test/firefox_setup_test.dart test/linux_firefox_web_test.dart
ctest --test-dir .build/native-linux --output-on-failure
python3 native/platform/linux/browser_setup/tests/setup_tests.py --native .build/native-linux -v
```

I test Flutter usano un servizio simulato; il backend usa esclusivamente
home, profili e cartelle Snap temporanei. La prova NSS aggiunge un modulo
estraneo sentinella che non deve essere caricato. Verifica anche la
conservazione byte per byte degli archivi certificati/chiavi, blocco del
profilo/processo, piano cambiato, conflitti, copie Snap, aggiornamenti,
idempotenza e autorizzazione separata. Non configura Firefox dell'host e
non accede alla CIE. Il `.deb` include helper e guardia, con dipendenze
`python3` e `libnss3-tools`; non contiene la sentinella o programmi di test.

Fonti primarie:

- [Profili Firefox](https://firefox-source-docs.mozilla.org/toolkit/profile/index.html)
- [Percorsi legacy e XDG di Firefox su Linux](https://github.com/mozilla-firefox/firefox/blob/main/toolkit/xre/nsXREDirProvider.cpp)
- [Inizializzazione NSS in modutil](https://github.com/nss-dev/nss/blob/master/cmd/modutil/modutil.c)
- [Registrazione dei moduli NSS](https://github.com/nss-dev/nss/blob/master/cmd/modutil/pk11.c)
- [Blocco dei profili Unix](https://searchfox.org/firefox-main/source/toolkit/profile/nsProfileLock.cpp)
- [Interfaccia Snap pcscd](https://snapcraft.io/docs/reference/interfaces/pcscd-interface/)
