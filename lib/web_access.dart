// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'pairing_view.dart';

typedef WebPublisher = Future<void> Function(
  String card,
  String? certificateHex,
);
typedef WebTester = Future<JsonResult> Function(String card);
Future<void> publishWebCertificate(String card, String? hex) async {
  if (!Platform.isMacOS) return; // Windows publishes in the native bridge.
  const channel = MethodChannel('cie.prototype/web');
  final published = await channel.invokeMethod<bool>(
    hex == null ? 'forget' : 'configure',
    {'card': card, 'certificateHex': ?hex},
  );
  if (published != true) {
    throw PlatformException(code: 'web_publication_failed');
  }
}

class WebAccessCard extends StatefulWidget {
  const WebAccessCard({
    super.key,
    required this.service,
    required this.reader,
    required this.card,
    required this.enabled,
    required this.onBusy,
    this.busy = false,
    this.publisher = publishWebCertificate,
    this.tester,
  });
  final WebAccessService service;
  final String reader, card;
  final bool enabled, busy;
  final FutureOr<void> Function(bool) onBusy;
  final WebPublisher publisher;
  final WebTester? tester;
  @override
  State<WebAccessCard> createState() => _WebAccessCardState();
}

class _WebAccessCardState extends State<WebAccessCard> {
  bool working = false;
  String? pendingCertificate, message;
  Future<void> configure() async {
    if (working || widget.busy || !widget.enabled) return;
    setState(() {
      working = true;
      message = null;
    });
    var started = false;
    try {
      await widget.onBusy(true);
      started = true;
      if (!mounted) return;
      if (pendingCertificate == null) {
        String? pin = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PairCardDialog(card: widget.card, webAccess: true),
        );
        if (pin == null || !mounted) return;

        final result = await widget.service.enrollWeb(
          widget.reader,
          widget.card,
          pin,
        );
        pin = null;
        if (!mounted) return;
        if (result['ok'] != true) {
          message = result['message'] as String? ?? 'Configurazione non completata. Nessun nuovo tentativo automatico.';
          return;
        }
        final hex = result['certificateHex'];
        if (hex is! String ||
            hex.isEmpty ||
            hex.length > 16384 ||
            !RegExp(r'^(?:[a-f0-9]{2})+$').hasMatch(hex)) {
          message = 'Il runtime ha restituito un certificato non valido.';
          return;
        }
        pendingCertificate = hex;
      }
      await widget.publisher(widget.card, pendingCertificate);
      pendingCertificate = null;
      message = 'Certificato pubblico configurato per l’accesso ai siti. Apri il sito nel browser.';
    } on PlatformException catch (error) {
      message = error.message ?? 'Componente di sistema non disponibile. Puoi completare la configurazione senza reinserire il PIN.';
    } catch (_) {
      message = 'Configurazione non completata. Nessun tentativo sulla carta viene ripetuto automaticamente.';
    } finally {
      if (started) await widget.onBusy(false);
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> forget() async {
    if (working || widget.busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, "Rimuovi accesso ai siti")),
        content: Text(
          tr(
            context,
            "Rimuovere la configurazione Web di questa applicazione per questa CIE? La carta, il PIN e i componenti ufficiali non vengono modificati.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, "Annulla")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, "Rimuovi")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      working = true;
      message = null;
      pendingCertificate = null;
    });
    await widget.onBusy(true);
    try {
      final result = await widget.service.forgetWeb(widget.card);
      if (result['ok'] != true) {
        message = result['message'] as String? ?? 'Rimozione non completata.';
        return;
      }
      await widget.publisher(widget.card, null);
      message = 'Configurazione Web di questa applicazione rimossa.';
    } catch (_) {
      message =
          'Rimozione dal sistema non completata. Puoi riprovare senza PIN.';
    } finally {
      await widget.onBusy(false);
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> testSystem() async {
    if (working || widget.busy || !widget.enabled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, "Prova del componente di sistema")),
        content: Text(
          tr(
            context,
            "Verrà firmata e verificata una richiesta locale di prova. Il sistema potrebbe chiedere il PIN nella propria finestra. Nessun sito viene contattato e non vengono eseguiti Cambio PIN o Sblocco Carta.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, "Annulla")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, "Avvia prova")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      working = true;
      message = null;
    });
    await widget.onBusy(true);
    try {
      JsonResult result;
      if (widget.tester != null) {
        result = await widget.tester!(widget.card);
      } else if (Platform.isMacOS) {
        const channel = MethodChannel('cie.prototype/web');
        final response = await channel.invokeMapMethod<String, dynamic>(
          'test',
          {'card': widget.card},
        );
        result = response ?? {'ok': false};
      } else {
        result = await widget.service.testWeb(widget.card);
      }
      message =
          result['message'] as String? ??
          (result['ok'] == true
              ? 'Prova locale riuscita. Il login a un sito resta da verificare.'
              : 'Prova non riuscita. Nessun tentativo automatico.');
    } on PlatformException catch (error) {
      message = error.message ?? 'Componente di sistema non disponibile.';
    } catch (_) {
      message =
          'Prova del componente non completata. Nessun tentativo automatico.';
    } finally {
      await widget.onBusy(false);
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, "Accesso ai siti con CIE"),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            "Configurazione separata dall’abbinamento per firmare documenti. Il certificato pubblico viene conservato dal sistema; il PIN non viene salvato da questa procedura. Per accedere ai siti, sia su macOS sia su Windows, inserisci tutte le otto cifre del PIN nella finestra protetta del sistema, anche se la CIE è abbinata.",
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: !widget.enabled || widget.busy || working
                  ? null
                  : configure,
              child: Text(
                pendingCertificate == null
                    ? tr(context, "Configura accesso ai siti")
                    : tr(context, "Completa configurazione senza PIN"),
              ),
            ),
            TextButton(
              onPressed: widget.busy || working ? null : forget,
              child: Text(tr(context, "Rimuovi configurazione Web")),
            ),
            OutlinedButton(
              onPressed: !widget.enabled || widget.busy || working
                  ? null
                  : testSystem,
              child: Text(tr(context, "Prova componente di sistema")),
            ),
          ],
        ),
        if (!widget.enabled)
          Text(
            tr(
              context,
              "Il componente per configurare l’accesso ai siti manca nel runtime.",
            ),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(tr(context, message!)),
          ),
      ],
    ),
  );
}
