// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'diagnostics.dart';
import 'native_bridge.dart';

enum _SettingsTab { general, proxy, log }

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.value,
    required this.network,
    required this.onSave,
    required this.onProbe,
    required this.diagnostics,
    required this.capabilities,
    required this.onBusy,
    this.configurationValid = true,
    this.preferences,
    this.advanced,
    this.diagnosticDetails,
    this.webDiagnostics,
    this.enrollmentReadable,
    this.interactionBusy = false,
  });
  final bool configurationValid, interactionBusy;
  final Widget? preferences, advanced, diagnosticDetails;
  final List<Map<String, bool>>? webDiagnostics;
  final bool? enrollmentReadable;
  final AppSettings value;
  final SessionNetworkConfig network;
  final Future<void> Function(AppSettings, SessionNetworkConfig) onSave;
  final Future<JsonResult> Function(SessionNetworkConfig) onProbe;
  final DiagnosticRecorder diagnostics;
  final JsonResult? capabilities;
  final ValueChanged<bool> onBusy;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late ProxyMode mode = widget.value.proxy.mode;
  late AppDiagnosticLevel level = widget.value.diagnostics;
  late final host = TextEditingController(text: widget.value.proxy.host);
  late final port = TextEditingController(
    text: widget.value.proxy.port == 0
        ? ''
        : widget.value.proxy.port.toString(),
  );
  late final username = TextEditingController(text: widget.network.username);
  late final password = TextEditingController(text: widget.network.password);
  bool busy = false;
  _SettingsTab tab = _SettingsTab.general;
  bool get locked => busy || widget.interactionBusy;
  String? message;
  bool failed = false;
  @override
  void dispose() {
    for (final c in [host, port, username, password]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (message != null) {
      setState(() {
        message = null;
        failed = false;
      });
    }
  }

  SessionNetworkConfig _draft() {
    final result = SessionNetworkConfig(
      proxy: mode == ProxyMode.direct
          ? const ProxySettings()
          : ProxySettings(
              mode: mode,
              host: host.text.trim(),
              port: int.tryParse(port.text.trim()) ?? 0,
            ),
      username: mode == ProxyMode.direct ? '' : username.text,
      password: mode == ProxyMode.direct ? '' : password.text,
    );
    result.validate();
    return result;
  }

  Future<void> _run(Future<String> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    widget.onBusy(true);
    try {
      final text = await action();
      if (mounted) message = text;
    } on FormatException catch (e) {
      if (mounted) {
        message = e.message;
        failed = true;
      }
    } catch (_) {
      if (mounted) {
        message =
            'Operazione non completata. Controlla la configurazione e riprova.';
        failed = true;
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<void> _save() => _run(() async {
    final config = _draft();
    await widget.onSave(
      AppSettings(
        proxy: config.proxy,
        diagnostics: widget.value.diagnostics,
        languageCode: widget.value.languageCode,
        themeCode: widget.value.themeCode,
      ),
      config,
    );
    return 'Impostazioni salvate. Le credenziali proxy restano solo in questa sessione.';
  });
  Future<void> _saveLog() => _run(() async {
    await widget.onSave(
      AppSettings(
        proxy: widget.value.proxy,
        diagnostics: level,
        languageCode: widget.value.languageCode,
        themeCode: widget.value.themeCode,
      ),
      widget.network,
    );
    return 'Impostazioni dei log salvate.';
  });
  Future<void> _probe() => _run(() async {
    final result = await widget.onProbe(_draft());
    if (result['ok'] != true) {
      failed = true;
      return 'Connessione non riuscita (trasporto: ${result['transportCode'] ?? 'non disponibile'}, HTTP: ${result['httpStatus'] ?? 0}). Controlla proxy, autenticazione e connessione. Non è stata tentata una connessione diretta alternativa.';
    }
    return 'Connessione al sito ufficiale CIE riuscita (HTTP ${result['httpStatus']}). Il test non usa lettore, carta o documenti.';
  });
  Future<void> _reset() => _run(() async {
    await widget.onSave(
      AppSettings(
        languageCode: widget.value.languageCode,
        themeCode: widget.value.themeCode,
      ),
      const SessionNetworkConfig(),
    );
    mode = ProxyMode.direct;
    level = AppDiagnosticLevel.off;
    for (final c in [host, port, username, password]) {
      c.clear();
    }
    return 'Rete e diagnostica ripristinate. Preferenze della firma conservate.';
  });
  Future<void> _export() => _run(() async {
    final report = const JsonEncoder.withIndent('  ').convert(
      widget.diagnostics.snapshot(
        network: widget.network,
        capabilities: widget.capabilities,
        webAccess: widget.webDiagnostics,
        enrollmentReadable: widget.enrollmentReadable,
      ),
    );
    final location = await getSaveLocation(
      suggestedName: 'cie-id-diagnostica.json',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Rapporto JSON', extensions: ['json']),
      ],
    );
    if (location == null) return 'Esportazione annullata.';
    final file = File(location.path);
    if (await file.exists()) {
      throw const FormatException(
        'Scegli un nuovo nome: il rapporto non sovrascrive file esistenti.',
      );
    }
    await file.writeAsString('$report\n', flush: true);
    return 'Rapporto diagnostico salvato. Puoi controllarlo prima di condividerlo.';
  });
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: locked,
          child: TabBar(
            onTap: (index) => setState(() {
              tab = _SettingsTab.values[index];
              message = null;
              failed = false;
            }),
            tabs: [
              Tab(text: tr(context, 'Generali')),
              Tab(text: tr(context, 'Proxy')),
              Tab(text: tr(context, 'Log')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!widget.configurationValid)
          Text(
            tr(
              context,
              "Le impostazioni salvate non sono leggibili. Salva o ripristina la configurazione per riattivare verifiche e nuove firme.",
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Offstage(
          offstage: tab != _SettingsTab.proxy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  context,
                  "La configurazione è usata dai controlli online di certificati e revoca, inclusi quelli storici. La guida e i siti esterni usano il browser e la sua configurazione.",
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ProxyMode>(
                key: ValueKey(mode),
                initialValue: mode,
                decoration: InputDecoration(
                  labelText: tr(context, "Connessione"),
                ),
                items: [
                  DropdownMenuItem(
                    value: ProxyMode.direct,
                    child: Text(tr(context, "Connessione diretta")),
                  ),
                  DropdownMenuItem(
                    value: ProxyMode.http,
                    child: Text(tr(context, "Proxy HTTP")),
                  ),
                  DropdownMenuItem(
                    value: ProxyMode.https,
                    child: Text(tr(context, "Proxy HTTPS")),
                  ),
                ],
                onChanged: locked
                    ? null
                    : (v) => setState(() {
                        mode = v!;
                        message = null;
                        failed = false;
                      }),
              ),
              if (mode != ProxyMode.direct) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: host,
                  onChanged: (_) => _edited(),
                  enabled: !locked,
                  decoration: InputDecoration(
                    labelText: tr(context, "Host del proxy"),
                    hintText: tr(
                      context,
                      "proxy.esempio.it oppure [2001:db8::1]",
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: port,
                  onChanged: (_) => _edited(),
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr(context, "Porta del proxy"),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  onChanged: (_) => _edited(),
                  enabled: !locked,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr(
                      context,
                      "Utente proxy (facoltativo, solo sessione)",
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  onChanged: (_) => _edited(),
                  enabled: !locked,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr(context, "Password proxy (solo sessione)"),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    "Autenticazione Basic. Utente e password non vengono salvati su disco e vanno reinseriti dopo il riavvio. HTTPS cifra anche il collegamento al proxy. Per le CRL storiche il proxy deve consentire CONNECT alle porte HTTP/HTTPS dei servizi pubblici.",
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
        Offstage(
          offstage: tab != _SettingsTab.log,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<AppDiagnosticLevel>(
                key: ValueKey(level),
                initialValue: level,
                decoration: InputDecoration(
                  labelText: tr(context, "Raccolta diagnostica"),
                ),
                items: [
                  DropdownMenuItem(
                    value: AppDiagnosticLevel.off,
                    child: Text(tr(context, "Disattivata")),
                  ),
                  DropdownMenuItem(
                    value: AppDiagnosticLevel.errors,
                    child: Text(tr(context, "Solo errori")),
                  ),
                  DropdownMenuItem(
                    value: AppDiagnosticLevel.operations,
                    child: Text(tr(context, "Operazioni e tempi")),
                  ),
                ],
                onChanged: locked
                    ? null
                    : (v) => setState(() {
                        level = v!;
                        message = null;
                        failed = false;
                      }),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  "Gli ultimi 200 eventi restano in memoria fino alla chiusura dell’app. Sono raccolti solo operazione, esito, durata e contatori. I log dettagliati delle librerie rimangono disattivati. Disattivare la raccolta cancella gli eventi già raccolti.",
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (tab != _SettingsTab.general)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: locked
                    ? null
                    : tab == _SettingsTab.proxy
                    ? _save
                    : _saveLog,
                child: Text(tr(context, "Salva impostazioni")),
              ),
              if (tab == _SettingsTab.proxy)
                OutlinedButton(
                  onPressed: locked ? null : _probe,
                  child: Text(tr(context, "Test connessione")),
                ),
              TextButton(
                onPressed: locked ? null : _reset,
                child: Text(tr(context, "Ripristina rete e diagnostica")),
              ),
            ],
          ),
        AppNotification(
          message: message,
          error: failed,
          enabled: !busy,
          title: failed ? 'Operazione non completata' : 'CIE ID',
          onDismissed: () {
            if (mounted) setState(() => message = null);
          },
        ),
        if (busy) const LinearProgressIndicator(),
        Offstage(
          offstage: tab != _SettingsTab.log,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                tr(context, "Rapporto diagnostico locale"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  "Il rapporto non contiene PIN, PUK, documenti, percorsi personali, nomi dei lettori, certificati, indirizzo o credenziali del proxy. Non viene inviato automaticamente.",
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: locked ? null : _export,
                    child: Text(tr(context, "Esporta rapporto JSON")),
                  ),
                  TextButton(
                    onPressed: locked
                        ? null
                        : () => setState(widget.diagnostics.clear),
                    child: Text(tr(context, "Cancella eventi diagnostici")),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text(
                  tr(context, "Anteprima rapporto · {p0} eventi", [
                    widget.diagnostics.events.length,
                  ]),
                ),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(
                      widget.diagnostics.snapshot(
                        network: widget.network,
                        capabilities: widget.capabilities,
                        webAccess: widget.webDiagnostics,
                        enrollmentReadable: widget.enrollmentReadable,
                      ),
                    ),
                    key: const PageStorageKey('diagnostic-report-body'),
                  ),
                ],
              ),
              if (widget.diagnosticDetails != null) widget.diagnosticDetails!,
              if (widget.advanced != null) widget.advanced!,
            ],
          ),
        ),
        Offstage(
          offstage: tab != _SettingsTab.general,
          child:
              widget.preferences ??
              Text(tr(context, "Preferenze non disponibili.")),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
      ],
    ),
  );
}
