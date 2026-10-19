// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'license_information.dart';

class InformationView extends StatelessWidget {
  const InformationView({super.key, required this.ready});
  final bool ready;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(tr(context, "CIE ID")),
      Text(tr(context, "Versione 0.1.0")),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Questo non è un prodotto ufficiale dell'Istituto Poligrafico e Zecca dello Stato italiano e non è supportato da IPZS.",
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => showCieLicenses(context),
        icon: const Icon(Icons.description_outlined),
        label: Text(tr(context, "Licenze e riconoscimenti")),
      ),
      const SizedBox(height: 16),
      ExpansionTile(
        title: Text(tr(context, "Dettagli tecnici")),
        tilePadding: EdgeInsets.zero,
        children: [
          ListTile(
            title: Text(
              tr(context, "Applicazione nativa per Windows, macOS e Linux."),
            ),
          ),
          ListTile(
            title: Text(
              ready
                  ? tr(context, "Middleware caricato")
                  : tr(context, "Middleware non disponibile"),
            ),
          ),
        ],
      ),
    ],
  );
}
