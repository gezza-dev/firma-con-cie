// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'package:flutter/material.dart';

import 'license_information.dart';
import 'app_updates.dart';

import 'package:url_launcher/url_launcher.dart';

class InformationView extends StatelessWidget {
  const InformationView({super.key, required this.ready});
  final bool ready;

  Future<void> openProject(BuildContext context) async {
    final page = Uri.parse('https://github.com/gezza-dev/firma-con-cie');
    var opened = false;
    try {
      opened = await launchUrl(page, mode: LaunchMode.externalApplication);
    } on Object {
      // Retain a readable link if the operating system cannot open a browser.
    }
    if (!opened && context.mounted) {
      await showAppNotification(
        context,
        message: tr(
          context,
          'Impossibile aprire il browser. Copia questo collegamento: {p0}',
          [page.toString()],
        ),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(tr(context, "Firma con CIE")),
      Text(tr(context, "Versione {p0}", [appVersion])),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Questo non è un prodotto ufficiale dell'Istituto Poligrafico e Zecca dello Stato italiano e non è supportato da IPZS.",
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => openProject(context),
        icon: const Icon(Icons.open_in_new),
        label: Text(tr(context, "Pagina del progetto Firma con CIE")),
      ),
      const SizedBox(height: 12),
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

  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    AppUpdate value;
    try {
      value = await widget.checker();
    } on Object {
      value = const AppUpdate(UpdateState.unavailable);
    }
    if (!mounted) return;
    setState(() => checking = false);
    final message = switch (value.state) {
      UpdateState.current => tr(
        context,
        'La versione installata è aggiornata.',
      ),
      UpdateState.unavailable => tr(
        context,
        'Impossibile verificare gli aggiornamenti. Controlla la connessione; il repository o una release potrebbero non essere accessibili.',
      ),
      UpdateState.available => tr(context, 'È disponibile la versione {p0}.', [
        value.version ?? '',
      ]),
    };
    final page = value.state == UpdateState.available ? value.page : null;
    await showAppNotification(
      context,
      title: 'Verifica aggiornamenti',
      message: message,
      error: value.state == UpdateState.unavailable,
      actionLabel: page == null ? null : 'Apri la pagina di aggiornamento',
      onAction: page == null ? null : () => openRelease(page),
    );
  }

  Future<void> openRelease(Uri page) async {
    if (!mounted) return;
    var opened = false;
    try {
      opened = await launchUrl(page, mode: LaunchMode.externalApplication);
    } on Object {
      // Keep the link available if the default browser cannot be opened.
    }
    if (!opened && mounted) {
      await showAppNotification(
        context,
        message: tr(
          context,
          'Impossibile aprire il browser. Copia questo collegamento: {p0}',
          [''],
        ),
        details: page.toString(),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: checking ? null : check,
    icon: const Icon(Icons.system_update_alt),
    label: Text(
      tr(
        context,
        checking ? 'Ricerca aggiornamenti…' : 'Verifica aggiornamenti',
      ),
    ),
  );
}
