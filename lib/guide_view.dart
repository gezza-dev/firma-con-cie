// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'license_information.dart';

import 'package:url_launcher/url_launcher.dart';

const assistanceFaq =
    'https://www.cartaidentita.interno.gov.it/Assistenza/#FAQ';
const prototypeIssues =
    'https://github.com/gezza-dev/cie-id-macos-universal/issues';

typedef LinkOpener = Future<bool> Function(Uri uri);
const guideLinks = {
  'Software CIE ufficiale':
      'https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/',
  'CIE ID Universal: progetto macOS di riferimento':
      'https://github.com/gezza-dev/cie-id-macos-universal',
  'Ultima release dell’app macOS di riferimento':
      'https://github.com/gezza-dev/cie-id-macos-universal/releases/latest',
};
Future<bool> openGuideLink(Uri uri) async {
  if (uri.scheme != 'https' ||
      !{
        ...guideLinks.values,
        assistanceFaq,
        prototypeIssues,
      }.contains(uri.toString())) {
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

const guideSections = <String, String>{
  "1. Collegare il lettore e abbinare la CIE": "Collega un lettore contactless compatibile e appoggia la CIE. Su Windows installa il driver del produttore se necessario. L’applicazione riconosce automaticamente lettore e carta, senza chiedere il PIN e senza cambiare la pagina aperta. Se un’altra applicazione sta usando la carta, attendi che abbia terminato. Se ci sono più CIE, scegli quella corretta per l’operazione.\n\nNella Home premi Abbina CIE. Su Windows, se il componente per l’accesso ai siti manca, l’app richiede prima l’autorizzazione amministrativa di Windows per installarlo e attivarlo. Dopo l’attivazione inserisci le otto cifre del PIN una sola volta: vengono verificati i dati della carta e predisposti sia la firma con PIN parziale sia l’accesso ai siti. Le prime quattro cifre restano nel Portachiavi macOS o nella Gestione credenziali Windows; Nome, Cognome e certificato pubblico verificati sono conservati separatamente. Il PIN completo non viene salvato. Il componente per l’accesso ai siti deve essere attivo: se manca, l’abbinamento per firmare resta disponibile e la Home indica come completare la preparazione senza un altro PIN.\n\nLe vecchie CIE abbinate a questa applicazione restano utilizzabili per firmare. Completa abbinamento aggiorna esplicitamente la configurazione con il PIN completo; non vengono usate di nascosto le ultime quattro cifre. Rimuovi CIE elimina, dopo conferma, abbinamento e configurazione Web di questa applicazione, anche senza carta. Le configurazioni dell’app originale restano separate.",
  '2. Firmare PDF o altri documenti': 'Apri Firma Elettronica. Se hai CIE abbinate, scegli la carta oppure Firma con CIE non abbinata. Seleziona un documento o trascinalo nell’area di caricamento: puoi prepararlo anche senza lettore collegato. È accettato un solo file alla volta. Il formato viene controllato leggendo il documento: PAdES è disponibile solo per PDF supportati; CAdES produce un P7M. Scegli il tipo e premi Prosegui.\n\nAppoggia la CIE scelta al lettore. Per una carta abbinata vengono richieste automaticamente le ultime quattro cifre del PIN; senza abbinamento servono tutte le otto cifre. Se l’archivio protetto non è accessibile puoi scegliere esplicitamente il PIN completo: non vengono provate automaticamente modalità alternative. Premi Firma e scegli dove salvare il documento. Se il nome è già presente, la finestra di sistema chiede conferma prima di sostituirlo. Annullando il salvataggio il PIN viene cancellato e non viene inviata alcuna autenticazione alla carta.\n\nLa firma esegue un solo tentativo e il PIN viene rimosso dal campo. Il risultato viene controllato crittograficamente prima del salvataggio. Un file esistente viene sostituito solo dopo una firma riuscita e verificata: in caso di errore resta intatto. File firmato con successo conferma il salvataggio; i dettagli espandibili distinguono integrità, fiducia e revoca. Una revoca indeterminata non equivale a certificato valido. Indietro conserva le scelte ma cancella il PIN; Annulla e Concludi tornano alla scelta del documento. Se il PIN viene modificato, ripeti l’abbinamento.',
  '3. Aggiungere un segno grafico al PDF': 'Con PAdES selezionato attiva Aggiungi firma grafica e premi Prosegui. Apri Anteprima e personalizzazione: il PDF viene visualizzato localmente. Scegli la pagina, trascina il riquadro oppure usa i pulsanti e regola la dimensione. Puoi personalizzare con un PNG/JPEG oppure usare Ripristina firma testuale predefinita. Il nome proviene dai dati verificati della CIE abbinata; senza questi dati l’anteprima mostra un segnaposto. Il Nome e Cognome effettivi sono sempre letti direttamente dalla CIE durante la firma, dopo il PIN e senza una seconda autenticazione, anche se usi un’immagine personalizzata.\n\nPer una CIE abbinata l’immagine personalizzata viene copiata nell’archivio di questa applicazione e riusata solo per quella carta. L’eventuale immagine globale precedente può essere importata esplicitamente, conservando l’originale. Tornando indietro rimangono pagina e posizione; cambiando documento l’anteprima viene annullata. La grafica senza abbinamento è una funzione aggiuntiva di questa applicazione e non viene associata a una carta. Confermare l’anteprima non firma: premi poi Prosegui per arrivare al PIN.\n\nLa grafica è facoltativa e non sostituisce la firma crittografica. Sono supportate immagini fino a 10 MiB e 16 megapixel, documenti fino a 256 MiB e PDF senza password. Le nuove prove grafiche con CIE reale restano da eseguire su macOS e Windows.',
  '4. Cofirmare un P7M': 'Seleziona un file P7M in Firma Elettronica. Se contiene firme integre e un contenuto supportato, viene proposta Aggiungi una firma. La cofirma aggiunge un sottoscrittore allo stesso contenuto: conserva le firme esistenti senza creare un P7M annidato. Premi Aggiungi una firma per arrivare al PIN, poi Firma per scegliere una nuova destinazione.\n\nPrima di chiedere il PIN vengono rifiutati contenitori danneggiati, privi di contenuto incorporato o con firme crittograficamente non valide. L’integrità non equivale alla fiducia nei certificati. Dopo la cofirma vengono controllate tutte le firme e la conservazione del contenuto originale. Le prove storiche e LTA vanno rivalutate: aggiungere una firma non rinnova automaticamente marche o prove di revoca.',
  '5. Verificare una firma ed estrarre un documento': 'Apri Verifica Firma e scegli un PDF/P7M oppure trascinalo nell’area di caricamento. Il controllo parte subito, senza un altro pulsante e senza lettore, carta o PIN. Puoi annullare o scegliere un altro documento durante l’attesa: gli esiti superati vengono scartati. Il controllo già avviato può richiedere ancora qualche istante per terminare; non vengono avviate operazioni sulla CIE.\n\nOgni firmatario ha una scheda con integrità della firma, certificato e revoca. Un risultato non determinato non significa non revocato; un problema di connessione non significa firma non valida. La data dichiarata dal firmatario è distinta dalla data di una marca verificata. Apri Dettagli del firmatario per catena, marche ed esiti storici; Validità storica e a lungo termine mostra separatamente l’analisi DSS, senza associare firmatari dei due motori sulla sola base dell’ordine. Questa applicazione non attesta la qualificazione giuridica di una firma.\n\nRipeti verifica aggiorna i controlli sul file originale. Scegli un altro documento apre il selettore; Concludi torna alla selezione. Per un P7M leggibile, dopo l’analisi compare Estrai documento anche se la firma o il certificato non sono validi. Scegli una destinazione nuova: i file esistenti non vengono sovrascritti. L’estrazione usa la stessa copia analizzata, conserva i byte incorporati e non apre automaticamente il documento. Se il file originale è cambiato, occorre verificarlo di nuovo. Per contenitori annidati si estrae un livello alla volta.',
  '6. Cambio PIN e Sblocco Carta': 'Le pagine Cambia PIN e Sblocca Carta richiedono rispettivamente PIN corrente o PUK, un nuovo PIN e la relativa conferma. Operano sulla CIE selezionata, con una conferma esplicita e senza tentativi automatici. Non comunicare PIN o PUK in chat o nei report.\n\nIn questa applicazione le prove software di queste funzioni sono separate dai test sulla carta: le prove reali di Cambio PIN e Sblocco Carta sono rinviate. Un errore dopo l’invio di un comando può richiedere una verifica manuale dello stato della carta.',
  '7. Preferenze e dati locali': 'Impostazioni permette di scegliere il formato proposto per i nuovi documenti e di importare un’immagine per le anteprime PDF. Una copia dell’immagine viene conservata nella cartella delle preferenze di questa applicazione. Cambiare le preferenze non modifica documenti o firme già preparati. Rimuovi immagine predefinita e Ripristina preferenze iniziali cancellano soltanto i dati gestiti da questa applicazione, lasciando intatto il file originale scelto.\n\nPIN, PUK e documenti non vengono salvati nelle preferenze. Le immagini per CIE sono associate localmente all’identificativo della carta in una cartella distinta dalle preferenze globali; Rimuovi CIE le elimina, mentre il ripristino globale le conserva. Le copie temporanee dei documenti e delle anteprime vengono eliminate annullando o concludendo il flusso; un arresto anomalo può lasciare file temporanei da rimuovere.',
  '8. Aiuto e limiti di questa applicazione': 'Se il lettore non compare, verifica cavo, driver e disponibilità del servizio smart card; evita che un’altra applicazione o macchina virtuale occupi il dispositivo. Se la carta cambia, attendi il nuovo riconoscimento automatico prima di firmare. Per errori di rete controlla la connessione e il proxy in Impostazioni: l’assenza di risposte attendibili sulla revoca mantiene l’esito indeterminato.\n\nLa pagina Assistenza riporta FAQ, contatti ufficiali CIE e i riferimenti del progetto indipendente. In Impostazioni puoi attivare una diagnostica limitata a esiti e tempi, vedere il rapporto ed esportarlo senza invii automatici. Il proxy è usato dalla verifica ordinaria e dalle CRL storiche; le credenziali restano solo nella sessione.\n\nQuesta guida descrive il applicazione per macOS e Windows. Linux e gli installer di distribuzione restano da completare. I nuovi componenti per l’accesso ai siti sono sperimentali e richiedono il collaudo indicato al punto 9. Gli abbinamenti sono locali a questa applicazione: non vengono migrati dall’app originale e non abilitano da soli l’accesso ai siti. L’applicazione non sostituisce l’app macOS pubblicata e non attesta la qualificazione giuridica di una firma.',

  "9. Accedere ai siti con la CIE": "L’accesso con carta fisica e lettore (livello 3) viene predisposto insieme all’abbinamento nella Home. Richiede il componente CryptoTokenKit su macOS o il componente smart card su Windows. Su Windows l’app propone automaticamente l’installazione con autorizzazione amministrativa prima del PIN di abbinamento. Se rifiuti, puoi annullare oppure scegliere esplicitamente di proseguire solo per firmare. L’applicazione indica distintamente abbinamento per firmare, certificato pubblicato, disponibilità del componente e riconoscimento dell’identità da parte del sistema: nessuno di questi, da solo, conferma il login a un sito.\n\nPer una CIE già abbinata, Attiva accesso ai siti installa e attiva il componente Windows con autorizzazione amministrativa, mantenendo la CIE sul lettore. Completa accesso ai siti riusa i dati pubblici verificati già salvati: non viene chiesto un nuovo PIN. Se il sistema deve rileggere la carta, rimuovila e riappoggiala. Apri poi il sito nel browser, scegli Entra con CIE e la modalità con carta e lettore. Seleziona il certificato quando proposto e inserisci personalmente il PIN nella finestra del sistema. Per accedere ai siti servono tutte le otto cifre del PIN sia su macOS sia su Windows, anche per una CIE abbinata.\n\nIn Impostazioni, Prove avanzate accesso ai siti conserva il test locale del componente e le funzioni tecniche di recupero. Non sono passaggi ordinari prima di ogni login. Il login al portale ufficiale CIE con Safari è riuscito con la precedente build; il nuovo flusso unico e altri siti/browser, oltre al login Windows, richiedono prove separate. Non si eseguono consensi sul sito o tentativi PIN automatici. Cambio PIN e Sblocco Carta reali restano rinviati.",
};

class GuideView extends StatefulWidget {
  const GuideView({super.key, this.opener = openGuideLink});
  final LinkOpener opener;
  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  String? error;
  bool opening = false;
  Future<void> _open(String link) async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    var ok = false;
    try {
      ok = await widget.opener(Uri.parse(link));
    } catch (_) {}
    if (mounted) {
      setState(() {
        opening = false;
        if (!ok) {
          error =
              'Impossibile aprire il browser. Riprova oppure apri il collegamento riportato qui sotto:\n$link';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Guida inclusa nell’app, consultabile anche senza connessione. I collegamenti esterni si aprono nel browser predefinito e richiedono Internet.",
        ),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Applicazione indipendente. Non è un prodotto ufficiale dell’Istituto Poligrafico e Zecca dello Stato Italiano e non è supportato da IPZS.",
        ),
      ),
      const SizedBox(height: 20),
      for (final entry in guideSections.entries)
        ExpansionTile(
          key: PageStorageKey(entry.key),
          title: Text(tr(context, entry.key)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              tr(context, entry.value),
              key: PageStorageKey('${entry.key}-body'),
            ),
          ],
        ),
      const SizedBox(height: 20),
      Text(
        tr(context, "Collegamenti utili"),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SelectableText(
            tr(context, error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      for (final entry in guideLinks.entries)
        TextButton.icon(
          onPressed: opening ? null : () => _open(entry.value),
          icon: const Icon(Icons.open_in_new),
          label: Text(tr(context, entry.key)),
        ),
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: () => showCieLicenses(context),
        icon: const Icon(Icons.description_outlined),
        label: Text(tr(context, "Informazioni e licenze")),
      ),
    ],
  );
}
