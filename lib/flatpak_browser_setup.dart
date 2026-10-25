// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_localizations.dart';
import 'chrome_setup.dart';
import 'firefox_setup.dart';
import 'native_bridge.dart';

typedef FlatpakBrowserCall = Future<String?> Function(String request);

class FlatpakBrowserTransport {
  FlatpakBrowserTransport({FlatpakBrowserCall? call})
    : _call =
          call ??
          ((request) =>
              const MethodChannel('cie.id/flatpak_browser_setup')
                  .invokeMethod<String>('request', request));
  final FlatpakBrowserCall _call;
  Future<void> _queue = Future<void>.value();

  Future<JsonResult> request(
    String operation, {
    String? profile,
    String? fingerprint,
    Map<String, String> certificates = const {},
  }) async {
    final snapshot = Map<String, String>.of(certificates);
    final next = _queue.then(
      (_) => _request(
        operation,
        profile: profile,
        fingerprint: fingerprint,
        certificates: snapshot,
      ),
    );
    _queue = next.then<void>((_) {});
    return next;
  }

  Future<JsonResult> _request(
    String operation, {
    String? profile,
    String? fingerprint,
    required Map<String, String> certificates,
  }) async {
    try {
      final raw = await _call(
        jsonEncode({
          'protocol': 1,
          'op': operation,
          'profile': ?profile,
          'fingerprint': ?fingerprint,
          'certificates': certificates,
        }),
      ).timeout(const Duration(seconds: 70));
      if (raw == null || raw.length > 5 * 1024 * 1024) {
        throw const FormatException();
      }
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } on MissingPluginException {
      return {'ok': false, 'code': 'helper_missing'};
    } catch (_) {
      return {'ok': false, 'code': 'helper_unavailable'};
    }
  }
}

class FlatpakFirefoxSetupService implements FirefoxSetupService {
  FlatpakFirefoxSetupService(this.transport);
  final FlatpakBrowserTransport transport;
  Map<String, String> certificates = {};
  @override
  Future<JsonResult> inspect() =>
      transport.request('firefox.inspect', certificates: certificates);
  @override
  Future<JsonResult> plan(String profile) => transport.request(
    'firefox.plan',
    profile: profile,
    certificates: certificates,
  );
  @override
  Future<JsonResult> apply(String profile, String fingerprint) =>
      transport.request(
        'firefox.apply',
        profile: profile,
        fingerprint: fingerprint,
        certificates: certificates,
      );
  @override
  Future<JsonResult> connectPcsc() => transport.request('firefox.connect-pcsc');
}

class FlatpakChromeSetupService implements ChromeSetupService {
  FlatpakChromeSetupService(this.transport);
  final FlatpakBrowserTransport transport;
  Map<String, String> certificates = {};
  @override
  Future<JsonResult> inspect() =>
      transport.request('chrome.inspect', certificates: certificates);
  @override
  Future<JsonResult> plan() =>
      transport.request('chrome.plan', certificates: certificates);
  @override
  Future<JsonResult> apply(String fingerprint) => transport.request(
    'chrome.apply',
    fingerprint: fingerprint,
    certificates: certificates,
  );
}

const flatpakHelperMessage =
    'Per configurare l’accesso ai siti, installa il componente «Accesso ai siti per Firma con CIE Flatpak», poi premi «Rileggi».';

class FlatpakBrowserSetupHome extends StatefulWidget {
  const FlatpakBrowserSetupHome({
    super.key,
    required this.firefox,
    required this.chrome,
    required this.onBusy,
    required this.onHealth,
    required this.onFirefoxStatus,
    required this.onChromeStatus,
    this.busy = false,
  });
  final FlatpakFirefoxSetupService firefox;
  final FlatpakChromeSetupService chrome;
  final FutureOr<void> Function(bool) onBusy;
  final ValueChanged<bool> onHealth;
  final ValueChanged<JsonResult> onFirefoxStatus, onChromeStatus;
  final bool busy;
  @override
  State<FlatpakBrowserSetupHome> createState() =>
      _FlatpakBrowserSetupHomeState();
}

class _FlatpakBrowserSetupHomeState extends State<FlatpakBrowserSetupHome>
    with WidgetsBindingObserver {
  bool ready = false, checking = false;
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
  void didUpdateWidget(covariant FlatpakBrowserSetupHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy && !widget.busy) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (checking || widget.busy) return;
    setState(() => checking = true);
    final result = await widget.firefox.transport.request('status');
    if (!mounted) return;
    final available =
        result['ok'] == true &&
        result['protocol'] == 1 &&
        result['fullPinRequired'] == true;
    setState(() {
      ready = available;
      checking = false;
    });
    widget.onHealth(available);
  }

  @override
  Widget build(BuildContext context) => ready
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FirefoxSetupHomeCard(
              service: widget.firefox,
              busy: widget.busy,
              onBusy: widget.onBusy,
              onStatus: widget.onFirefoxStatus,
            ),
            ChromeSetupHomeCard(
              service: widget.chrome,
              busy: widget.busy,
              onBusy: widget.onBusy,
              onStatus: widget.onChromeStatus,
            ),
          ],
        )
      : Card(
          key: const ValueKey('flatpak-web-notice'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'Accesso ai siti con CIE'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(tr(context, flatpakHelperMessage)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: checking || widget.busy ? null : _refresh,
                  child: Text(tr(context, 'Rileggi')),
                ),
              ],
            ),
          ),
        );
}
