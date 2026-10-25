// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'native_bridge.dart';

abstract interface class FirefoxSetupService {
  Future<JsonResult> inspect();
  Future<JsonResult> plan(String profile);
  Future<JsonResult> apply(String profile, String fingerprint);
  Future<JsonResult> connectPcsc();
}

class LinuxFirefoxSetupService implements FirefoxSetupService {
  LinuxFirefoxSetupService({
    this.helperName = 'firefox_setup.py',
    this.pythonExecutable = '/usr/bin/python3',
  });
  final String helperName, pythonExecutable;
  Future<JsonResult> _run(List<String> arguments) async {
    if (!Platform.isLinux) return {'ok': false, 'code': 'unsupported'};
    final helper = File.fromUri(
      File(Platform.resolvedExecutable).parent.uri
          .resolve('cie_native/browser_setup/$helperName'),
    );
    if (!await helper.exists()) {
      return {'ok': false, 'code': 'runtime_invalid'};
    }
    Process? process;
    try {
      process = await Process.start(pythonExecutable, [
        helper.path,
        ...arguments,
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      await Future.wait([process.exitCode, errors])
          .timeout(const Duration(seconds: 65));
      final text = await output;
      if (text.length > 256 * 1024) throw const FormatException();
      final result = jsonDecode(text);
      if (result is! Map<String, dynamic>) throw const FormatException();
      return result;
    } catch (_) {
      process?.kill();
      return {'ok': false, 'code': 'configuration_unavailable'};
    }
  }

  @override
  Future<JsonResult> inspect() => _run(['--action', 'inspect']);
  @override
  Future<JsonResult> plan(String profile) =>
      _run(['--action', 'plan', '--profile', profile]);
  @override
  Future<JsonResult> apply(String profile, String fingerprint) => _run([
    '--action',
    'apply',
    '--profile',
    profile,
    '--fingerprint',
    fingerprint,
  ]);
  @override
  Future<JsonResult> connectPcsc() => _run(['--action', 'connect-pcsc']);
}

String firefoxSetupError(String? code) => switch (code) {
  'profile_uninitialized' =>
    'Apri e chiudi Firefox con questo profilo, poi riprova.',
  'browser_running' || 'browser_status_unknown' => 'Chiudi Firefox e riprova.',
  'plan_changed' =>
    'La configurazione è cambiata. Seleziona di nuovo il profilo.',
  'module_conflict' || 'snap_copy_conflict' =>
    'Controlla i dispositivi di sicurezza nelle impostazioni di Firefox.',
  'tools_missing' ||
  'runtime_invalid' => 'Aggiorna o reinstalla Firma con CIE, poi riprova.',
  'registration_failed_restored' =>
    'Configurazione non riuscita. Le impostazioni precedenti sono conservate.',
  'permission_not_verified' => 'Il lettore non è ancora autorizzato. Premi «Autorizza lettore» per riprovare.',
  'profile_missing' ||
  'profile_invalid' ||
  'profiles_invalid' ||
  'unsafe_path' =>
    'Questo profilo non è disponibile. Apri e chiudi Firefox, poi riprova.',
  _ => 'Configurazione non riuscita. Riprova più tardi.',
};

bool firefoxSetupNeeded(JsonResult status) {
  if (status['ok'] != true) return true;
  final profiles = (status['profiles'] as List? ?? [])
      .whereType<Map>()
      .where((p) => p['state'] != 'profile_uninitialized')
      .toList();
  return profiles.any((p) => p['state'] != 'configured') ||
      (profiles.any((p) => p['target'] == 'snap') &&
          status['snapPermission'] != 'connected');
}

/// Home checks only profile metadata. Registration stays behind the wizard's
/// explicit confirmation. This is the app's entry point when setup is needed.
class FirefoxSetupHomeCard extends StatefulWidget {
  const FirefoxSetupHomeCard({
    super.key,
    required this.service,
    required this.onBusy,
    this.busy = false,
    this.onStatus,
  });
  final FirefoxSetupService service;
  final FutureOr<void> Function(bool) onBusy;
  final bool busy;
  final ValueChanged<JsonResult>? onStatus;

  @override
  State<FirefoxSetupHomeCard> createState() => _FirefoxSetupHomeCardState();
}

class _FirefoxSetupHomeCardState extends State<FirefoxSetupHomeCard>
    with WidgetsBindingObserver {
  bool visible = false,
      checking = false,
      refreshAgain = false,
      dialogOpen = false;

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
  void didUpdateWidget(covariant FirefoxSetupHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        (oldWidget.busy && !widget.busy)) {
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || dialogOpen || widget.busy) return;
    if (checking) {
      refreshAgain = true;
      return;
    }
    checking = true;
    final service = widget.service;
    try {
      final status = await service.inspect();
      if (mounted && !dialogOpen && !widget.busy && service == widget.service) {
        setState(() => visible = firefoxSetupNeeded(status));
        widget.onStatus?.call(status);
      }
    } catch (_) {
      // Keep the troubleshooting entry available if status cannot be checked.
      if (mounted && !dialogOpen && !widget.busy && service == widget.service) {
        setState(() => visible = true);
        widget.onStatus?.call({'ok': false});
      }
    } finally {
      checking = false;
      if (refreshAgain) {
        refreshAgain = false;
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
          child: FirefoxSetupCard(
            service: widget.service,
            busy: widget.busy,
            onBusy: _onBusy,
          ),
        )
      : const SizedBox.shrink();
}

class FirefoxSetupCard extends StatelessWidget {
  const FirefoxSetupCard({
    super.key,
    required this.onBusy,
    this.busy = false,
    this.service,
  });
  final bool busy;
  final FirefoxSetupService? service;
  final FutureOr<void> Function(bool) onBusy;

  Future<void> _open(BuildContext context) async {
    try {
      await onBusy(true);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _FirefoxSetupDialog(service: service ?? LinuxFirefoxSetupService()),
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
            tr(context, 'Firefox e Firefox Snap'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Prepara Firefox per usare la CIE. Non serve il PIN.'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _open(context),
            icon: const Icon(Icons.settings_outlined),
            label: Text(tr(context, 'Configura Firefox')),
          ),
        ],
      ),
    ),
  );
}

class _FirefoxSetupDialog extends StatefulWidget {
  const _FirefoxSetupDialog({required this.service});
  final FirefoxSetupService service;
  @override
  State<_FirefoxSetupDialog> createState() => _FirefoxSetupDialogState();
}

class _FirefoxSetupDialogState extends State<_FirefoxSetupDialog> {
  bool working = false, confirming = false, configured = false;
  bool hadProfiles = false, snapReady = false;
  List<JsonResult> profiles = [];
  String? selected, message;
  String permission = 'unknown';

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
      if (mounted) message = firefoxSetupError(null);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    profiles = [];
    selected = null;
    configured = false;
    hadProfiles = false;
    snapReady = false;
    permission = 'unknown';
    final result = await widget.service.inspect();
    if (!mounted) return;
    if (result['ok'] != true) {
      message = firefoxSetupError(result['code'] as String?);
      return;
    }
    final initialized = (result['profiles'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .where((p) => p['state'] != 'profile_uninitialized')
        .toList();
    hadProfiles = initialized.isNotEmpty;
    snapReady = initialized.any(
      (p) => p['target'] == 'snap' && p['state'] == 'configured',
    );
    profiles = initialized.where((p) => p['state'] != 'configured').toList();
    permission = result['snapPermission'] as String? ?? 'unknown';
    selected = null;
    configured = false;
  });

  Future<void> _prepare() async {
    if (working || confirming || selected == null) return;
    final identity = selected!;
    JsonResult? prepared;
    await _run(() async {
      final result = await widget.service.plan(identity);
      if (!mounted) return;
      if (result['ok'] != true) {
        message = firefoxSetupError(result['code'] as String?);
        return;
      }
      if (result['alreadyConfigured'] == true) {
        profiles.removeWhere((p) => p['id'] == identity);
        snapReady = snapReady || result['target'] == 'snap';
        selected = null;
        message = 'Questo profilo è già configurato.';
        return;
      }
      prepared = result;
    });
    if (mounted && prepared != null) await _apply(identity, prepared!);
  }

  Future<bool> _confirm({
    required bool permission,
    JsonResult? prepared,
  }) async {
    setState(() => confirming = true);
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                tr(
                  context,
                  permission ? 'Autorizza lettore' : 'Conferma configurazione',
                ),
              ),
              content: SingleChildScrollView(
                child: Text(
                  tr(
                    context,
                    permission
                        ? 'Vuoi consentire a Firefox Snap di usare il lettore? Il sistema potrebbe chiedere la password del computer.'
                        : 'Configurare il profilo «{p0}»? Le altre impostazioni resteranno invariate.',
                    permission ? [] : [prepared!['label'] as String],
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
                  child: Text(
                    tr(context, permission ? 'Autorizza' : 'Configura'),
                  ),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<void> _apply(String identity, JsonResult prepared) async {
    if (working || confirming) return;
    if (!await _confirm(permission: false, prepared: prepared) || !mounted) {
      return;
    }
    await _run(() async {
      final result = await widget.service.apply(
        identity,
        prepared['fingerprint'] as String,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        message = firefoxSetupError(result['code'] as String?);
        return;
      }
      configured = true;
      permission = result['snapPermission'] as String? ?? permission;
      snapReady = snapReady || prepared['target'] == 'snap';
      profiles.removeWhere((p) => p['id'] == identity);
      selected = null;
      message = 'Firefox è configurato. Riaprilo e usa il PIN completo per accedere ai siti.';
    });
  }

  Future<void> _permission() async {
    if (working || confirming) return;
    if (!await _confirm(permission: true) || !mounted) return;
    await _run(() async {
      final result = await widget.service.connectPcsc();
      if (!mounted) return;
      if (result['ok'] != true) {
        message = firefoxSetupError(result['code'] as String?);
        return;
      }
      permission = 'connected';
      message = 'Firefox Snap può usare il lettore.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !working && !confirming,
      child: AlertDialog(
        title: Text(tr(context, 'Configura Firefox')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (profiles.isNotEmpty)
                  Text(
                    tr(
                      context,
                      'Scegli un profilo e chiudi Firefox. Non serve il PIN.',
                    ),
                  ),
                const SizedBox(height: 16),
                if (profiles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(profiles.map((p) => p['id']).join(',')),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Profilo Firefox'),
                    ),
                    items: [
                      for (final p in profiles)
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            '${p['target'] == 'snap' ? 'Firefox Snap' : 'Firefox'} · ${p['label']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: working || confirming
                        ? null
                        : (value) => setState(() {
                            selected = value;
                            configured = false;
                            message = null;
                          }),
                  )
                else if (!working && message == null)
                  Text(
                    tr(
                      context,
                      hadProfiles ? 'Non ci sono profili da configurare.' : 'Apri e chiudi Firefox, poi premi «Rileggi profili».',
                    ),
                  ),
                const SizedBox(height: 12),
                if (snapReady && permission != 'connected') ...[
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      context,
                      'Firefox Snap deve essere autorizzato a usare il lettore.',
                    ),
                  ),
                ],
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
          if (selected == null && !configured)
            TextButton(
              onPressed: working || confirming ? null : _refresh,
              child: Text(tr(context, 'Rileggi profili')),
            ),
          if (snapReady && permission != 'connected')
            OutlinedButton(
              onPressed: working || confirming ? null : _permission,
              child: Text(tr(context, 'Autorizza lettore')),
            ),
          TextButton(
            onPressed: working || confirming
                ? null
                : () => Navigator.pop(context),
            child: Text(tr(context, 'Chiudi')),
          ),
          if (selected != null && !configured)
            FilledButton(
              onPressed: working || confirming ? null : _prepare,
              child: Text(tr(context, 'Continua')),
            ),
        ],
      ),
    );
  }
}
