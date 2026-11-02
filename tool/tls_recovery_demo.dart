// SPDX-License-Identifier: BSD-3-Clause
// Standalone interactive simulation. No backend, card, document, subprocess,
// network request or certificate-store operation is used by this entry point.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cie_flutter_prototype/network_settings.dart';
import 'package:cie_flutter_prototype/tls_recovery.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';

void main() => runApp(const TlsRecoveryDemo());

class TlsRecoveryDemo extends StatelessWidget {
  const TlsRecoveryDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Firma con CIE · SIMULAZIONE HTTPS',
    locale: const Locale('it'),
    supportedLocales: CieLocalizations.supportedLocales,
    localizationsDelegates: const [
      CieLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff4c65ad),
      useMaterial3: true,
    ),
    home: const _DemoPage(),
  );
}

class _DemoPage extends StatefulWidget {
  const _DemoPage();
  @override
  State<_DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<_DemoPage> {
  bool failRecovery = false, busy = false, recovering = false;
  String result = 'Pronto. Scegli uno scenario e avvia la simulazione.';

  Future<void> _simulate() async {
    if (busy) return;
    final failed = failRecovery;
    setState(() {
      busy = true;
      result = 'Errore HTTPS 60 simulato.';
    });
    var consented = false, checked = false;
    // Injection is confined to this diagnostic entry point. The production
    // application never accepts a flag which invents verification results.
    final recovery = TlsRecovery(
      operatingSystem: 'windows',
      enabled: true,
      executable: 'SIMULATO-NON-ESEGUITO',
      command: (_, args, input) async {
        if (args.contains('--version')) return (0, 'SIMULAZIONE Schannel');
        await Future<void>.delayed(const Duration(milliseconds: 750));
        return failed ? (60, '000') : (0, '200');
      },
    );
    await recovery.retry(
      original: {'ok': false, 'transportCode': 60, 'httpStatus': 0},
      network: const SessionNetworkConfig(),
      consent: () async {
        consented = await confirmTlsRecovery(context);
        return consented;
      },
      verify: () async {
        checked = true;
        return {'ok': true};
      },
      isCurrent: () => mounted,
      record: (_) {},
      onRecovery: (value) async {
        if (mounted) setState(() => recovering = value);
      },
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      result = !consented
          ? 'SIMULAZIONE: consenso negato. Nessun recupero e nessun nuovo controllo.'
          : checked
          ? 'SIMULAZIONE: recupero riuscito e controllo ripetuto una volta.'
          : 'SIMULAZIONE: recupero non riuscito. Esito originale mantenuto.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Firma con CIE · SIMULAZIONE HTTPS')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'SIMULAZIONE — nessun certificato viene rimosso o scaricato.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Questa finestra consente di collaudare il dialogo e le scelte dell’utente. '
                'Non usa rete, CIE, PIN, documenti, abbinamenti o impostazioni personali. '
                'Il pulsante «Consenti e riprova» avvia soltanto un recupero simulato.',
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Simula un recupero non riuscito'),
                value: failRecovery,
                onChanged: busy
                    ? null
                    : (value) => setState(() => failRecovery = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _simulate,
                child: const Text('Simula certificati HTTPS mancanti'),
              ),
              const SizedBox(height: 20),
              if (recovering) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Text(
                  'Recupero simulato in corso… Nessuna connessione di rete.',
                ),
              ],
              const SizedBox(height: 12),
              Text(result, key: const ValueKey('simulation-result')),
              const SizedBox(height: 24),
              const Text(
                'La prova non dimostra il recupero reale di certificati mancanti. '
                'Il dialogo visualizzato è lo stesso dell’app; in questa simulazione tutte le richieste sono sostituite da risposte sintetiche.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
