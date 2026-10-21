// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'license_information.dart';
import 'app_updates.dart';

import 'package:url_launcher/url_launcher.dart';

class InformationView extends StatelessWidget {
  const InformationView({super.key, required this.ready});
  final bool ready;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(tr(context, "CIE ID")),
      Text(tr(context, "Versione 1.0.0")),
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
      const AppUpdatesView(),
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

class AppUpdatesView extends StatefulWidget {
  const AppUpdatesView({super.key, this.checker = checkAppUpdates});
  final Future<AppUpdate> Function() checker;
  @override
  State<AppUpdatesView> createState() => _AppUpdatesViewState();
}

class _AppUpdatesViewState extends State<AppUpdatesView> {
  bool checking = false;
  AppUpdate? result;
  String? error;
  Future<void> check() async {
    if (checking) return;
    setState(() {
      checking = true;
      error = null;
    });
    AppUpdate value;
    try {
      value = await widget.checker();
    } on Object {
      value = const AppUpdate(UpdateState.unavailable);
    }
    if (mounted) {
      setState(() {
        result = value;
        checking = false;
      });
    }
  }

  Future<void> openRelease() async {
    final page = result?.page;
    if (page == null) return;
    var opened = false;
    try {
      opened = await launchUrl(page, mode: LaunchMode.externalApplication);
    } on Object {
      /* Show the URL below. */
    }
    if (!opened && mounted) {
      setState(() {
        error = page.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: checking ? null : check,
        icon: const Icon(Icons.system_update_alt),
        label: Text(
          tr(
            context,
            checking ? 'Ricerca aggiornamenti…' : 'Verifica aggiornamenti',
          ),
        ),
      ),
      if (result?.state == UpdateState.current)
        Text(tr(context, 'La versione installata è aggiornata.')),
      if (result?.state == UpdateState.unavailable)
        Text(
          tr(
            context,
            'Impossibile verificare gli aggiornamenti. Controlla la connessione; il repository o una release potrebbero non essere accessibili.',
          ),
        ),
      if (result?.state == UpdateState.available) ...[
        Text(
          tr(context, 'È disponibile la versione {p0}.', [result!.version!]),
        ),
        TextButton(
          onPressed: openRelease,
          child: Text(tr(context, 'Apri la pagina di aggiornamento')),
        ),
      ],
      if (error != null) SelectableText(error!),
    ],
  );
}
