// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'guide_view.dart';

class AssistanceView extends StatefulWidget {
  const AssistanceView({super.key, this.opener = openGuideLink});
  final LinkOpener opener;
  @override
  State<AssistanceView> createState() => _AssistanceViewState();
}

class _AssistanceViewState extends State<AssistanceView> {
  String? error;
  bool opening = false;
  Future<void> _open(String url) async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    bool opened = false;
    try {
      opened = await widget.opener(Uri.parse(url));
    } catch (_) {}
    if (mounted) {
      setState(() {
        opening = false;
        if (!opened) {
          error =
              'Impossibile aprire il browser. Copia questo collegamento: $url';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "Per assistenza sull’app CieID ufficiale e sulle credenziali CIE puoi consultare la sezione Domande frequenti.",
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: opening ? null : () => _open(assistanceFaq),
        icon: const Icon(Icons.open_in_new),
        label: Text(tr(context, "Domande frequenti")),
      ),
      if (error != null)
        SelectableText(
          tr(context, error!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "Se non hai trovato la risposta che stavi cercando, puoi contattare l’assistenza CIE ai seguenti canali:",
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mail_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      'cie.cittadini@interno.it',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.phone_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      '06 4298 5699',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Il servizio di assistenza è attivo dal lunedì al venerdì dalle ore 9:00 alle ore 16:00 e il sabato dalle ore 9:00 alle ore 13:00.",
        ),
      ),
      const SizedBox(height: 28),
      Text(
        tr(context, "Blocco della Carta di Identità Elettronica"),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Nel caso di furto o smarrimento della tua CIE puoi richiedere il blocco della carta contattando il numero seguente e fornendo i dati richiesti:",
        ),
      ),
      const SizedBox(height: 12),
      const Row(
        children: [
          Icon(Icons.phone_outlined),
          SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              '800 098 558',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "• Nome\n• Cognome\n• Codice fiscale\n• Numero della CIE, se disponibile\n• Estremi della denuncia presentata alle forze dell’ordine\n• Città dove è stata sporta la denuncia",
        ),
      ),
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "Il servizio blocco carta è attivo dal lunedì al venerdì dalle ore 8:00 alle ore 18:00 e il sabato dalle ore 8:00 alle ore 14:00.",
        ),
      ),
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "I riferimenti sono quelli dell’assistenza ufficiale CIE, verificati il 17 ottobre 2026. Per le CIE emesse prima del 4 luglio 2016, la pagina ufficiale indica di rivolgersi al Comune di rilascio dopo aver sporto denuncia. Contatti e orari aggiornati sono disponibili nelle Domande frequenti.",
        ),
      ),
      const SizedBox(height: 28),
      Text(
        tr(context, "Supporto a questa applicazione indipendente"),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Questa applicazione non è un prodotto ufficiale e non è supportato da IPZS o dal Ministero dell’Interno. Per problemi specifici del fork consulta il progetto GitHub. Dalla pagina Impostazioni puoi esportare un rapporto diagnostico locale da controllare prima di condividerlo.",
        ),
      ),
      TextButton.icon(
        onPressed: opening ? null : () => _open(prototypeIssues),
        icon: const Icon(Icons.open_in_new),
        label: Text(tr(context, "Segnalazioni del progetto su GitHub")),
      ),
    ],
  );
}
