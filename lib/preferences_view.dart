// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'preferences.dart';

class PreferencesView extends StatefulWidget {
  const PreferencesView({
    super.key,
    required this.store,
    required this.value,
    required this.onChanged,
    this.onBusy,
  });
  final ValueChanged<bool>? onBusy;
  final PreferencesStore store;
  final SignaturePreferences value;
  final ValueChanged<SignaturePreferences> onChanged;
  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  bool busy = false;
  String? error;
  Future<void> _save(Future<SignaturePreferences> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusy?.call(true);
    try {
      final next = await action();
      if (mounted) widget.onChanged(next);
    } catch (_) {
      if (mounted) error = 'Impossibile salvare le preferenze. Verificare il file selezionato e riprovare.';
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusy?.call(false);
      }
    }
  }

  Future<void> _image() async {
    if (busy) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Immagine PNG o JPEG',
          extensions: ['png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (file != null && mounted) {
      await _save(() => widget.store.importImage(file.path));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, "Preferenze firma"),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Le preferenze vengono salvate su questo computer, senza PIN, PUK o documenti. Le immagini personalizzate per CIE restano associate alla singola carta nel solo archivio di questa applicazione.",
        ),
      ),
      const SizedBox(height: 20),
      AppNotification(
        message: error,
        error: true,
        enabled: !busy,
        onDismissed: () {
          if (mounted) setState(() => error = null);
        },
      ),
      if (busy) const LinearProgressIndicator(),
      DropdownButtonFormField<String>(
        key: ValueKey(widget.value.format),
        initialValue: widget.value.format,
        decoration: InputDecoration(
          labelText: tr(context, "Formato predefinito per i nuovi documenti"),
        ),
        items: [
          DropdownMenuItem(
            value: 'pdf',
            child: Text(tr(context, "PAdES · PDF")),
          ),
          DropdownMenuItem(
            value: 'p7m',
            child: Text(tr(context, "CAdES · P7M")),
          ),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) _save(() => widget.store.saveFormat(v));
              },
      ),
      const SizedBox(height: 20),
      Text(
        tr(context, "Immagine predefinita del segno grafico"),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        tr(
          context,
          "L’immagine viene copiata nelle preferenze. Sarà proposta nelle nuove anteprime PDF; la firma grafica resta facoltativa e richiede la conferma dell’anteprima.",
        ),
      ),
      const SizedBox(height: 12),
      if (widget.value.imagePath != null)
        Image.file(
          File(widget.value.imagePath!),
          height: 90,
          width: 360,
          fit: BoxFit.contain,
          errorBuilder: (_, e, s) => Text(
            tr(context, "Immagine non leggibile: rimuoverla o sostituirla."),
          ),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : _image,
            icon: const Icon(Icons.image_outlined),
            label: Text(tr(context, "Scegli immagine predefinita")),
          ),
          if (widget.value.imagePath != null)
            TextButton(
              onPressed: busy ? null : () => _save(widget.store.removeImage),
              child: Text(tr(context, "Rimuovi immagine predefinita")),
            ),
        ],
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: busy ? null : () => _save(widget.store.reset),
        child: Text(tr(context, "Ripristina preferenze iniziali")),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "Il ripristino rimuove solo l’immagine copiata e le preferenze di questa applicazione. Non modifica il file originale scelto né i documenti firmati.",
        ),
      ),
    ],
  );
}
