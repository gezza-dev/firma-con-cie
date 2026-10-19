// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PairCardDialog extends StatefulWidget {
  const PairCardDialog({
    super.key,
    required this.card,
    this.webAccess = false,
    this.unified = false,
    this.componentAvailable = false,
  });
  final String card;
  final bool webAccess, unified, componentAvailable;
  @override
  State<PairCardDialog> createState() => _PairCardDialogState();
}

class _PairCardDialogState extends State<PairCardDialog> {
  final controller = TextEditingController();
  bool invalid = false;
  @override
  void dispose() {
    controller.clear();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.webAccess
          ? tr(context, "Configura accesso ai siti")
          : widget.unified
          ? tr(context, "Abbina la tua CIE")
          : tr(context, "Abbina CIE a questa applicazione"),
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.webAccess
                  ? tr(
                      context,
                      "Inserisci le otto cifre del PIN una sola volta per leggere e verificare il certificato pubblico. Il certificato e l’associazione alla chiave sulla carta saranno resi disponibili al sistema per l’accesso ai siti. Questa operazione non salva il PIN e non modifica gli abbinamenti.",
                    )
                  : widget.unified
                  ? tr(
                      context,
                      "Inserisci il PIN completo una sola volta per abbinare la CIE e predisporre l’accesso ai siti. Le prime quattro cifre restano nell’archivio protetto di questo utente; il PIN completo non viene salvato. Nome, Cognome e certificato pubblico vengono letti e verificati dalla carta.{p0}",
                      [
                        widget.componentAvailable
                            ? ''
                            : tr(
                                context,
                                ' Il componente per l’accesso ai siti richiede ancora l’attivazione: potrai completarla senza ripetere il PIN.',
                              ),
                      ],
                    )
                  : tr(
                      context,
                      "Inserisci le otto cifre del PIN. Le prime quattro saranno conservate nell’archivio protetto di questo utente. L’abbinamento non modifica il PIN e non abilita da solo l’accesso ai siti.",
                    ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              enableIMEPersonalizedLearning: false,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 8,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: tr(context, "PIN completo · 8 cifre"),
                errorText: invalid
                    ? tr(context, "Inserisci tutte le otto cifre del PIN.")
                    : null,
              ),
            ),
            Text(
              tr(
                context,
                "Un solo tentativo. Non viene eseguito alcun Cambio PIN o Sblocco Carta.",
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, "Annulla")),
      ),
      FilledButton(
        onPressed: () {
          if (RegExp(r'^\d{8}$').hasMatch(controller.text)) {
            final value = controller.text;
            controller.clear();
            Navigator.pop(context, value);
          } else {
            setState(() => invalid = true);
          }
        },
        child: Text(
          widget.webAccess
              ? tr(context, "Leggi certificato e configura")
              : tr(context, "Abbina"),
        ),
      ),
    ],
  );
}
