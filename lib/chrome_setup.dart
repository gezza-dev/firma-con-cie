// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'firefox_setup.dart';
import 'native_bridge.dart';

abstract interface class ChromeSetupService {
  Future<JsonResult> inspect();
  Future<JsonResult> plan();
  Future<JsonResult> apply(String fingerprint);
}

class LinuxChromeSetupService implements ChromeSetupService {
  final _helper = LinuxFirefoxSetupService(helperName: 'chrome_setup.py');
  @override
  Future<JsonResult> inspect() => _helper.inspect();
  @override
  Future<JsonResult> plan() => _helper.plan('chrome-desktop');
  @override
  Future<JsonResult> apply(String fingerprint) =>
      _helper.apply('chrome-desktop', fingerprint);
}

String chromeSetupError(String? code) => switch (code) {
  'not_installed' => 'Installa Google Chrome desktop, poi riprova.',
  'database_uninitialized' ||
  'profile_missing' ||
  'profile_uninitialized' => 'Apri e chiudi Chrome, poi premi «Rileggi».',
  'browser_running' || 'browser_status_unknown' =>
    'Chiudi Chrome, anche in background, poi riprova.',
  'plan_changed' => 'La configurazione è cambiata. Premi «Rileggi» e riprova.',
  'module_conflict' => 'È presente una configurazione diversa. Controlla il modulo CIE prima di riprovare.',
  'runtime_invalid' ||
  'tools_missing' => 'Aggiorna o reinstalla Firma con CIE, poi riprova.',
  'registration_failed_restored' =>
    'Configurazione non riuscita. Le impostazioni precedenti sono conservate.',
  'database_unsupported' => 'Questa procedura supporta Google Chrome desktop.',
  'unsafe_path' || 'profile_invalid' => 'La configurazione di Chrome non è accessibile. Controlla i permessi e riprova.',
  'configuration_busy' => 'Configurazione già in corso. Attendi e riprova.',
  _ => 'Configurazione non riuscita. Riprova più tardi.',
};

bool chromeSetupNeeded(JsonResult status) =>
    status['ok'] != true ||
    (status['detected'] == true && status['state'] != 'configured');

class ChromeSetupHomeCard extends StatefulWidget {
  const ChromeSetupHomeCard({
    super.key,
    required this.service,
    required this.onBusy,
    this.busy = false,
    this.onStatus,
  });
  final ChromeSetupService service;
  final FutureOr<void> Function(bool) onBusy;
  final bool busy;
  final ValueChanged<JsonResult>? onStatus;
  @override
  State<ChromeSetupHomeCard> createState() => _ChromeSetupHomeCardState();
}

class _ChromeSetupHomeCardState extends State<ChromeSetupHomeCard>
    with WidgetsBindingObserver {
  bool visible = false, checking = false, again = false, dialogOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant ChromeSetupHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        (oldWidget.busy && !widget.busy)) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || widget.busy || dialogOpen) return;
    if (checking) {
      again = true;
      return;
    }
    checking = true;
    final service = widget.service;
    try {
      final result = await service.inspect();
      if (mounted && !dialogOpen && !widget.busy && service == widget.service) {
        setState(() => visible = chromeSetupNeeded(result));
        widget.onStatus?.call(result);
      }
    } catch (_) {
      if (mounted && !dialogOpen && !widget.busy && service == widget.service) {
        setState(() => visible = true);
        widget.onStatus?.call({'ok': false});
      }
    } finally {
      checking = false;
      if (again) {
        again = false;
        unawaited(_refresh());
      }
    }
  }

  Future<void> _onBusy(bool value) async {
    dialogOpen = value;
    try {
      await widget.onBusy(value);
    } finally {
      if (!value) unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) => visible
      ? Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: ChromeSetupCard(
            service: widget.service,
            busy: widget.busy,
            onBusy: _onBusy,
          ),
        )
      : const SizedBox.shrink();
}

class ChromeSetupCard extends StatelessWidget {
  const ChromeSetupCard({
    super.key,
    required this.onBusy,
    this.busy = false,
    this.service,
  });
  final bool busy;
  final ChromeSetupService? service;
  final FutureOr<void> Function(bool) onBusy;
  Future<void> _open(BuildContext context) async {
    try {
      await onBusy(true);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ChromeSetupDialog(service: service ?? LinuxChromeSetupService()),
      );
    } finally {
      await onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Google Chrome'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Prepara Chrome per usare la CIE. Non serve il PIN.'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _open(context),
            icon: const Icon(Icons.settings_outlined),
            label: Text(tr(context, 'Configura Chrome')),
          ),
        ],
      ),
    ),
  );
}

class _ChromeSetupDialog extends StatefulWidget {
  const _ChromeSetupDialog({required this.service});
  final ChromeSetupService service;
  @override
  State<_ChromeSetupDialog> createState() => _ChromeSetupDialogState();
}

class _ChromeSetupDialogState extends State<_ChromeSetupDialog> {
  bool working = false, confirming = false;
  String? state, message;
  JsonResult? plan;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        plan = null;
        message = chromeSetupError(null);
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    plan = null;
    state = null;
    final result = await widget.service.inspect();
    if (!mounted) return;
    state = result['ok'] == true ? result['state'] as String? : null;
    if (state != 'configured' && state != 'needs_setup') {
      message = chromeSetupError((state ?? result['code']) as String?);
    }
  });
  Future<void> _prepare() => _run(() async {
    final result = await widget.service.plan();
    if (!mounted) return;
    if (result['ok'] != true) {
      message = chromeSetupError(result['code'] as String?);
      return;
    }
    if (result['alreadyConfigured'] == true) {
      state = 'configured';
      return;
    }
    plan = result;
  });
  Future<void> _apply() async {
    if (working || confirming || plan == null) return;
    final prepared = plan!;
    setState(() => confirming = true);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Conferma configurazione')),
        content: SingleChildScrollView(
          child: Text(
            tr(
              context,
              'Vuoi configurare Chrome per usare la CIE? Firefox resterà invariato.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Configura')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (approved != true) return;
    await _run(() async {
      final result = await widget.service.apply(
        prepared['fingerprint'] as String,
      );
      if (!mounted) return;
      plan = null;
      if (result['ok'] != true) {
        message = chromeSetupError(result['code'] as String?);
        return;
      }
      state = 'configured';
      message =
          'Chrome è configurato. Riaprilo e usa il PIN completo di otto cifre.';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working && !confirming,
    child: AlertDialog(
      title: Text(tr(context, 'Configura Chrome')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state == 'needs_setup')
                Text(
                  tr(
                    context,
                    'Chiudi Chrome, anche in background. Non serve il PIN.',
                  ),
                ),
              if (state == 'configured' && message == null)
                Text(tr(context, 'Chrome è già configurato.')),
              if (state == 'needs_setup' && plan == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: working || confirming ? null : _prepare,
                    child: Text(tr(context, 'Continua')),
                  ),
                ),
              if (plan != null) ...[
                const SizedBox(height: 12),
                Text(tr(context, 'Verrà configurato Chrome per usare la CIE.')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: working || confirming ? null : _apply,
                  child: Text(tr(context, 'Configura Chrome')),
                ),
              ],
              if (plan == null &&
                  state != 'configured' &&
                  (state != 'needs_setup' || message != null))
                TextButton(
                  onPressed: working || confirming ? null : _refresh,
                  child: Text(tr(context, 'Rileggi')),
                ),
              if (working)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(tr(context, message!)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: working || confirming
              ? null
              : () => Navigator.pop(context),
          child: Text(tr(context, 'Chiudi')),
        ),
      ],
    ),
  );
}
