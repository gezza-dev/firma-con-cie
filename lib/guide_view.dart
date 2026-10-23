// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'package:flutter/material.dart';

import 'license_information.dart';

import 'package:url_launcher/url_launcher.dart';

const assistanceFaq =
    'https://www.cartaidentita.interno.gov.it/Assistenza/#FAQ';
const prototypeIssues = 'https://github.com/gezza-dev/cie-id-desktop/issues';

typedef LinkOpener = Future<bool> Function(Uri uri);
const guideLinks = {
  'Firma con CIE: progetto e documentazione':
      'https://github.com/gezza-dev/cie-id-desktop',
  'Software CIE ufficiale':
      'https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/',
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
  "1. Collegare il lettore e abbinare la CIE": "Collega al computer un lettore contactless compatibile e appoggia la CIE. L’app riconosce automaticamente il lettore e la carta, senza richiedere il PIN. Se un’altra applicazione sta usando la carta, attendi che abbia terminato.\n\nSu macOS usa un lettore compatibile con il sistema. Su Windows installa il driver del produttore, se necessario. Su Linux devono essere disponibili il servizio PC/SC (pcscd) e un driver compatibile con il lettore, ad esempio CCID.\n\nNella Home premi «Abbina CIE» e inserisci il PIN completo di otto cifre. Se hai già una carta abbinata, premi «Abbina un’altra CIE» per aggiungerne una. Dopo l’abbinamento, la Home mostra il nome del titolare e il numero della carta; per firmare bastano le ultime quattro cifre del PIN. La preparazione dell’accesso ai siti è descritta nella sezione 9.\n\nPer eliminare una carta da questo computer, premi «Rimuovi CIE» e conferma. L’operazione elimina l’abbinamento e i dati locali della carta gestiti da questa applicazione; non cambia il PIN né i dati della CIE. Non serve appoggiare la carta al lettore. Se la rimozione non viene completata, usa «Riprova rimozione».",
  "2. Firmare PDF o altri documenti": "Apri «Firma Elettronica» e seleziona la CIE con cui firmare tra quelle in elenco. Se la carta non è elencata, premi «Firma con CIE non presente in elenco»: in questo caso userai il PIN completo, senza salvare un abbinamento.\n\nNel passaggio «Documento» premi «Seleziona un documento» oppure trascina il file nell’area di caricamento. Puoi preparare il documento anche senza lettore collegato. È accettato un solo file alla volta. Scegli quindi il tipo di firma: PAdES mantiene il formato PDF; CAdES crea un file P7M. PAdES è disponibile per i PDF supportati e non protetti da password.\n\nSelezionando PAdES, l’opzione «Aggiungi firma grafica» è attiva per impostazione predefinita. Puoi disattivarla oppure proseguire con la personalizzazione descritta nella sezione 3.\n\nNel passaggio «PIN e salvataggio» appoggia al lettore la CIE selezionata e inserisci le ultime quattro cifre del PIN se è abbinata, oppure tutte le otto cifre negli altri casi. Premi «Firma» e scegli dove salvare il file. Se il nome è già presente, il dialogo di salvataggio chiede conferma prima della sostituzione. Annullando il salvataggio, il PIN viene cancellato dal campo e la firma non viene avviata.\n\nIl file viene salvato dopo la firma e il controllo della sua integrità. In caso di errore, un documento già presente nella destinazione rimane intatto. La pagina di esito conferma il salvataggio e permette di consultare i dettagli della verifica. «Indietro» torna al passaggio precedente; «Annulla» e «Concludi» riportano alla scelta del documento. Quando lasci il passaggio del PIN, il campo viene svuotato.",
  "3. Aggiungere un segno grafico al PDF": "Con «Aggiungi firma grafica» selezionato, apri «Anteprima e personalizzazione». Il segno viene proposto nella prima pagina, in basso a destra, con un margine dai bordi. Puoi scegliere un’altra pagina, trascinare il riquadro, usare le frecce di spostamento e regolarne la dimensione.\n\nLa firma testuale riporta nome e cognome del titolare, data, ora e fuso orario. Nell’anteprima il nome proviene dai dati verificati durante l’abbinamento; se non sono disponibili, compare un segnaposto. Al momento della firma, nome e cognome vengono letti dalla CIE effettivamente usata, dopo l’inserimento del PIN. Data e ora dell’anteprima sono indicative: nel documento vengono inserite quelle della firma.\n\n«Personalizza immagine» permette di scegliere un PNG o un JPEG. «Ripristina firma testuale predefinita» ripristina il testo ed è disabilitato quando la firma testuale è già attiva. Un’immagine personalizzata viene comunque accompagnata dai dati del titolare. Per una CIE abbinata, l’immagine viene conservata localmente e proposta solo per quella carta.\n\nPremi «Conferma anteprima», poi «Prosegui» per arrivare al PIN. La conferma dell’anteprima non firma il documento. Il segno grafico è facoltativo: la firma elettronica resta nel file anche senza un’immagine visibile. La data stampata nel segno grafico non è una marca temporale. Sono accettate immagini fino a 10 MiB e 16 megapixel.",
  "4. Cofirmare un P7M": "Seleziona un file P7M in «Firma Elettronica». Se contiene un documento incorporato e firme integre, l’app propone «Aggiungi una firma». La cofirma aggiunge un sottoscrittore allo stesso contenuto, senza creare un P7M annidato.\n\nPremi «Aggiungi una firma», inserisci il PIN richiesto e premi «Firma» per scegliere dove salvare il risultato. I contenitori danneggiati, privi di contenuto incorporato o con firme crittograficamente non valide vengono rifiutati prima della richiesta del PIN.\n\nLa cofirma conserva il contenuto e le firme già presenti, che vengono ricontrollati dopo l’operazione. L’integrità delle firme non garantisce da sola l’attendibilità dei certificati. Aggiungere una firma non rinnova automaticamente le marche temporali o le prove di revoca: per una valutazione storica, ripeti la verifica del documento risultante.",
  "5. Verificare una firma ed estrarre un documento": "Apri «Verifica Firma» e seleziona un PDF o un P7M, oppure trascinalo nell’area di caricamento. La verifica parte automaticamente e non richiede lettore, carta o PIN. I documenti possono avere dimensioni fino a 256 MiB. Durante l’attesa puoi annullare o scegliere un altro file; l’app mostra soltanto l’esito della richiesta corrente.\n\nOgni firmatario ha una scheda che distingue integrità della firma, validità del certificato e stato di revoca. Un esito indeterminato indica che le informazioni disponibili non permettono di concludere il controllo. Un problema di connessione non dimostra che la firma sia non valida; allo stesso modo, una revoca non verificata non equivale a un certificato valido.\n\nLa sezione «Dettagli del firmatario» mostra i controlli sulla catena dei certificati e sulle marche temporali. La data dichiarata dal firmatario è distinta dalla data attestata da una marca temporale verificata. Se disponibile nel pacchetto installato, «Validità storica e a lungo termine» analizza anche le prove conservate nel documento o recuperate per la verifica. Il risultato dipende dalla disponibilità di prove sufficienti e attendibili.\n\n«Ripeti verifica» aggiorna i controlli sul file originale; «Scegli un altro documento» apre il selettore; «Concludi» torna alla selezione iniziale.\n\nPer un P7M leggibile puoi usare «Estrai documento», anche se una firma o un certificato risultano non validi. Scegli una destinazione nuova: l’estrazione non sovrascrive file esistenti e non apre automaticamente il documento salvato. Il contenuto viene estratto dalla stessa copia analizzata, senza modificarne i byte. Se il file originale è cambiato, ripeti prima la verifica. Per contenitori annidati si estrae un livello alla volta.",
  "6. Cambiare il PIN e sbloccare la CIE": "In «Cambia PIN» inserisci il PIN attuale, il nuovo PIN e la sua conferma. In «Sblocca Carta» inserisci invece il PUK, il nuovo PIN e la conferma. PIN e PUK devono essere composti da otto cifre. Mantieni la CIE selezionata sul lettore fino alla conclusione dell’operazione.\n\nPrima di procedere, l’app chiede conferma e avvisa che l’abbinamento locale viene disabilitato, anche se l’operazione non riesce. Dopo il cambio del PIN o lo sblocco, abbina nuovamente la CIE dalla Home usando il PIN completo. Eventuali abbinamenti conservati in altre applicazioni non vengono aggiornati.\n\nUn PIN o un PUK errato riduce i tentativi disponibili. L’app non ripete automaticamente l’operazione e mostra l’esito in un dialogo. Se l’esito non è determinabile, il PIN potrebbe essere già cambiato: verifica lo stato della carta prima di riprovare. Non comunicare PIN o PUK nei messaggi di assistenza o nei rapporti diagnostici.",
  "7. Impostazioni e dati locali": "La pagina «Impostazioni» comprende tre schede: «Generali», «Proxy» e «Log».\n\nIn «Generali» scegli la lingua, il tema e le preferenze di firma. «Segui il sistema» usa la lingua del sistema operativo: italiano o inglese; per le altre lingue, o quando la lingua non è rilevabile, viene usato l’inglese. Puoi anche selezionare manualmente italiano o inglese. Per il tema puoi scegliere «Segui il sistema», chiaro o scuro.\n\nLe preferenze di firma stabiliscono il formato proposto per i nuovi documenti e l’eventuale immagine predefinita. Le immagini personalizzate per una CIE restano associate soltanto a quella carta. «Rimuovi immagine predefinita» e «Ripristina preferenze iniziali» non modificano il file originale scelto né cancellano gli abbinamenti. «Rimuovi CIE» elimina anche l’immagine associata alla carta rimossa.\n\nIn «Proxy» configura la connessione usata dai controlli online e usa «Test connessione» per verificarla. Le credenziali del proxy restano soltanto nella sessione corrente. In «Log» scegli il livello di diagnostica e consulta o esporta il rapporto locale. I rapporti non vengono inviati automaticamente.\n\nL’abbinamento conserva in un archivio locale cifrato le prime quattro cifre del PIN e i dati verificati della CIE. Il PIN completo e il PUK non vengono salvati. Preferenze e abbinamenti appartengono a questa applicazione e non vengono importati automaticamente da altre app. Le copie temporanee dei documenti vengono eliminate quando annulli o concludi la procedura; una chiusura anomala può lasciare file temporanei sul computer.",
  "8. Risolvere i problemi più comuni": "Se il lettore non compare, controlla il collegamento e il driver. Su Windows verifica il servizio Smart Card; su Linux verifica il servizio PC/SC e il driver del lettore. Una macchina virtuale o un’altra applicazione può trattenere il dispositivo: rendilo nuovamente disponibile al sistema prima di riprovare.\n\nSe la carta non viene riconosciuta, controlla che sia appoggiata correttamente e attendi il rilevamento automatico. Se l’app chiede di rimuoverla e riappoggiarla, segui l’indicazione. Non ripetere l’abbinamento soltanto perché un sito non riesce ad accedere: consulta prima la sezione 9.\n\nPer problemi di connessione, controlla la rete e la scheda «Proxy». Se mancano risposte attendibili dai servizi di verifica, alcuni esiti rimangono indeterminati. Per chiedere assistenza, usa la pagina «Assistenza», che distingue i contatti ufficiali CIE dalle segnalazioni relative a questa applicazione.\n\nGli avvisi operativi compaiono in finestre di dialogo: leggi il messaggio e premi «OK» per chiuderlo. I risultati della firma e della verifica restano nelle pagine dedicate. Se serve un rapporto diagnostico, esportalo dalla scheda «Log» e controllalo prima di condividerlo. Non inviare PIN, PUK o documenti personali insieme alla segnalazione.",
  "9. Accedere ai siti con la CIE": "Per accedere con carta fisica e lettore, apri il sito nel browser, scegli «Entra con CIE» e segui la modalità con carta e lettore, cioè l’accesso di livello 3. La disponibilità del lettore nell’app e il corretto accesso a un sito sono controlli distinti.\n\nSu macOS, l’accesso usa il componente CryptoTokenKit incluso nell’app. La configurazione viene predisposta durante l’abbinamento. Se la Home mostra «Attiva accesso ai siti», premi il pulsante e conferma con «Attiva»: viene riabilitato soltanto il componente di questa applicazione, conservando l’abbinamento e senza richiedere nuovamente il PIN.\n\nSu Windows, il pacchetto di installazione installa l’app e il componente per l’accesso ai siti con un’unica autorizzazione amministrativa. Durante l’installazione non servono il lettore, la CIE o il PIN: vengono configurati automaticamente i modelli di carta presenti nel catalogo verificato del middleware ufficiale. Gli aggiornamenti conservano gli abbinamenti e le impostazioni. Durante l’abbinamento l’app controlla soltanto il componente e non richiede privilegi amministrativi. Se il componente manca, esegui nuovamente il pacchetto di installazione; per modelli non ancora presenti nel catalogo occorre un aggiornamento dell’app. «Completa accesso ai siti» riutilizza i dati pubblici già salvati senza installare componenti e senza richiedere nuovamente il PIN.\n\nSu Linux, il lettore comunica tramite PC/SC. Per l’accesso ai siti serve anche un modulo smart card compatibile con la CIE e con il browser. Nei browser che gestiscono moduli PKCS#11, configura il modulo CIE seguendo le istruzioni del pacchetto installato; il percorso della libreria e le impostazioni dipendono dal browser e dalla distribuzione. Il solo servizio PC/SC non configura l’autenticazione del browser. Su Chrome desktop, il modulo va registrato nell’archivio NSS dell’utente seguendo le istruzioni Linux del pacchetto. Per Firefox e Firefox Snap usa «Configura Firefox» nelle Impostazioni generali. Il riquadro compare anche in cima alla Home quando occorre intervenire sulla configurazione; i profili non ancora inizializzati sono esclusi dall’elenco: scegli il profilo, prepara il riepilogo e conferma la registrazione a browser chiuso. Per Snap il permesso del lettore ha una conferma separata. Non servono carta o PIN per configurare il browser. Su entrambi i browser inserisci tutte le otto cifre del PIN durante il successivo accesso a un sito.\n\nSu macOS e Windows, «Completa accesso ai siti» riutilizza i dati pubblici verificati già salvati e non richiede una nuova lettura con il PIN. Una volta terminata la configurazione, segui il percorso di accesso nel browser. Quando viene proposta, seleziona l’identità della CIE e inserisci il PIN nella finestra di autenticazione. Su macOS e Windows inserisci tutte le otto cifre del PIN, anche se la CIE è abbinata. Su Linux segui le richieste del modulo di autenticazione configurato nel browser.\n\nLa pagina del sito può chiedere di confermare l’invio dei tuoi dati prima di proseguire. Leggila e conferma personalmente. Le prove avanzate del componente, disponibili nella scheda «Log», sono strumenti di diagnostica e non passaggi da eseguire prima di ogni accesso.",
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
          "Guida all’uso di Firma con CIE su Windows, macOS e Linux. È inclusa nell’app e si può consultare anche senza connessione. I collegamenti esterni si aprono nel browser predefinito e richiedono Internet.",
        ),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Questa applicazione indipendente non è un prodotto ufficiale dell’Istituto Poligrafico e Zecca dello Stato italiano e non è supportata da IPZS.",
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
      AppNotification(
        message: error,
        error: true,
        enabled: !opening,
        onDismissed: () {
          if (mounted) setState(() => error = null);
        },
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
