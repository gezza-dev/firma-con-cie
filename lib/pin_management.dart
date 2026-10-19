// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_bridge.dart';

String? pinInputError(
  String authentication,
  String replacement,
  String confirmation,
  bool unblock,
) {
  final digits = RegExp(r'^\d{8}$');
  if (!digits.hasMatch(authentication)) {
    return unblock
        ? 'Inserire le otto cifre del PUK.'
        : 'Inserire le otto cifre del PIN attuale.';
  }
  if (!digits.hasMatch(replacement)) {
    return 'Il nuovo PIN deve contenere otto cifre.';
  }
  if (replacement != confirmation) {
    return 'Il nuovo PIN e la conferma non corrispondono.';
  }
  return null;
}

class PinManagementPage extends StatefulWidget {
  const PinManagementPage({
    super.key,
    required this.service,
    required this.unblock,
    required this.busy,
    required this.available,
    required this.selected,
    required this.onRun,
    required this.onDetect,
    this.automaticDetection = false,
    this.onPairingsChanged,
  });
  final CieService service;
  final bool unblock, busy, available, automaticDetection;
  final JsonResult? selected;
  final Future<void> Function(String, Future<void> Function()) onRun;
  final Future<void> Function() onDetect;
  final Future<void> Function()? onPairingsChanged;
  @override
  State<PinManagementPage> createState() => _PinManagementState();
}

class _PinManagementState extends State<PinManagementPage> {
  final authentication = TextEditingController(),
      replacement = TextEditingController(),
      confirmation = TextEditingController();
  JsonResult? result;
  bool submitting = false;
  @override
  void didUpdateWidget(covariant PinManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected?['cardId'] != widget.selected?['cardId'] ||
        oldWidget.selected?['name'] != widget.selected?['name'] ||
        (widget.selected?['occupied'] == true &&
            oldWidget.selected?['occupied'] != true)) {
      clear();
      result = null;
    }
  }

  void clear() {
    authentication.clear();
    replacement.clear();
    confirmation.clear();
  }

  @override
  void dispose() {
    clear();
    authentication.dispose();
    replacement.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.busy ||
        submitting ||
        !widget.available ||
        widget.selected?['occupied'] == true ||
        widget.selected == null) {
      return;
    }
    final issue = pinInputError(
      authentication.text,
      replacement.text,
      confirmation.text,
      widget.unblock,
    );
    if (issue != null) {
      setState(() => result = {'ok': false, 'message': issue});
      return;
    }
    final target = Map<String, dynamic>.from(widget.selected!);
    setState(() => submitting = true);
    final operationNotice = widget.unblock
        ? 'Questa operazione usa il PUK e imposta realmente un nuovo PIN sulla CIE selezionata. Un PUK errato riduce i tentativi disponibili. Mantieni la carta sul lettore. Nessun tentativo viene ripetuto automaticamente.'
        : 'Questa operazione modifica realmente il PIN della CIE selezionata. Un PIN attuale errato riduce i tentativi disponibili. Mantieni la carta sul lettore. Nessun tentativo viene ripetuto automaticamente.';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.unblock
              ? tr(context, "Conferma sblocco della carta")
              : tr(context, "Conferma cambio PIN"),
        ),
        content: SingleChildScrollView(
          child: Text(
            tr(
              context,
              "{p0}\n\nConfermando disabiliti l’abbinamento locale della CIE, anche se l’operazione non riesce. Dopo dovrai abbinare nuovamente la carta dalla Home con il PIN completo.",
              [tr(context, operationNotice)],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, "Annulla")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, "Conferma operazione")),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (approved != true) {
      clear();
      setState(() => submitting = false);
      return;
    }
    final secret = authentication.text, next = replacement.text;
    clear();
    await widget.onRun(widget.unblock ? 'Sblocco della carta in corso…' : 'Cambio PIN in corso…', () async {
      JsonResult response;
      try {
        response = await widget.service.updatePin(
          reader: target['name'] as String,
          card: target['cardId'] as String,
          authentication: secret,
          newPin: next,
          unblock: widget.unblock,
        );
      } catch (_) {
        response = {
          'ok': false,
          'code': 'pin_operation_indeterminate',
          'message': 'Esito della modifica non confermato. Il PIN potrebbe essere già cambiato: non ripetere automaticamente l’operazione.',
        };
      }
      // Do not let a secondary refresh failure replace a confirmed card result.
      try {
        await widget.onPairingsChanged?.call();
      } catch (_) {}
      if (mounted) setState(() => result = response);
    });
    if (mounted) setState(() => submitting = false);
  }

  Widget field(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled:
          !widget.busy &&
          !submitting &&
          widget.available &&
          widget.selected?['occupied'] != true,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      maxLength: 8,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: tr(context, label)),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text(
        widget.unblock
            ? tr(
                context,
                "Usa il PUK completo di otto cifre e scegli un nuovo PIN.",
              )
            : tr(
                context,
                "Inserisci il PIN attuale completo e scegli un nuovo PIN.",
              ),
      ),
      const SizedBox(height: 12),
      Text(
        widget.selected == null
            ? tr(context, "Nessuna CIE selezionata.")
            : tr(context, "CIE selezionata: {p0} · {p1}", [
                widget.selected!['fullName'] ?? tr(context, 'Carta CIE'),
                widget.selected!['name'],
              ]),
      ),
      if (!widget.automaticDetection)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.busy || submitting ? null : widget.onDetect,
            child: Text(tr(context, "Rileva carta")),
          ),
        ),
      if (widget.automaticDetection && widget.selected == null)
        Text(
          tr(
            context,
            "Appoggia la CIE al lettore; verrà riconosciuta automaticamente.",
          ),
        ),
      if (widget.selected?['occupied'] == true)
        Text(
          tr(
            context,
            "Carta in uso: attendi che l’altra applicazione abbia terminato.",
          ),
        ),
      if (!widget.available)
        Text(
          tr(
            context,
            "Questa operazione richiede il runtime aggiornato per PIN e PUK.",
          ),
        ),
      const SizedBox(height: 16),
      field(
        widget.unblock ? 'PUK completo · 8 cifre' : 'PIN attuale · 8 cifre',
        authentication,
      ),
      field('Nuovo PIN · 8 cifre', replacement),
      field('Conferma nuovo PIN', confirmation),
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "Confermando l’operazione disabiliti l’abbinamento locale della CIE, anche se il cambio PIN o lo sblocco non riesce. Dovrai abbinarla nuovamente dalla Home con il PIN completo.",
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed:
              widget.busy ||
                  submitting ||
                  !widget.available ||
                  widget.selected?['occupied'] == true ||
                  widget.selected == null
              ? null
              : submit,
          child: Text(
            widget.unblock
                ? tr(context, "Sblocca e imposta il PIN")
                : tr(context, "Modifica il PIN"),
          ),
        ),
      ),
      if (result != null) ...[
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result!['ok'] == true
                      ? tr(context, "Operazione completata")
                      : result!['code'] == 'pin_operation_indeterminate'
                      ? tr(context, "Esito non determinabile")
                      : tr(context, "Operazione non completata"),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    result!['code'] == 'pairing_store_unavailable' ||
                            result!['message'] == 'pairing_store_unavailable'
                        ? 'Archivio protetto non accessibile. Questa versione del runtime ha interrotto l’operazione prima di inviare il PIN alla carta. Aggiorna il runtime; nessun tentativo automatico verrà eseguito.'
                        : result!['message'] as String? ??
                              'Operazione non completata.',
                  ),
                ),
                if (result!['cleanupWarning'] is String) ...[
                  const SizedBox(height: 8),
                  Text(result!['cleanupWarning'] as String),
                ],
                if (result!['attemptsRemaining'] is int)
                  Text(
                    tr(context, "Tentativi residui: {p0}", [
                      result!['attemptsRemaining'],
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}
