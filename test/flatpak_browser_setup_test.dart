// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/flatpak_browser_setup.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'linux_browser_status_test.dart' show LinuxPairedService, pairedStatus;
import 'web_completion_feedback_test.dart' show size;

class Host {
  bool present = true, configured = false;
  final calls = <JsonResult>[];
  Future<String> request(String raw) async {
    final value = jsonDecode(raw) as JsonResult;
    calls.add(value);
    final op = value['op'];
    return jsonEncode(switch (op) {
      'status' =>
        present
            ? {'ok': true, 'protocol': 1, 'fullPinRequired': true}
            : {'ok': false, 'code': 'helper_missing'},
      'firefox.inspect' => {
        'ok': true,
        'profiles': [
          {
            'id': '1' * 64,
            'label': 'Synthetic Firefox',
            'target': 'firefox',
            'state': configured ? 'configured' : 'needs_setup',
          },
        ],
        'snapPermission': 'unknown',
      },
      'chrome.inspect' => {
        'ok': true,
        'detected': true,
        'state': configured ? 'configured' : 'needs_setup',
      },
      'chrome.plan' => {
        'ok': true,
        'target': 'chrome',
        'fingerprint': '2' * 64,
        'alreadyConfigured': false,
      },
      'chrome.apply' => {
        'ok': true,
        'configured': configured = true,
        'browserLoginTested': false,
      },
      _ => {'ok': false, 'code': 'unexpected'},
    });
  }
}

void main() {
  test('shared transport serializes Firefox and Chrome requests and snapshots public data', () async {
    final first = Completer<String>();
    final calls = <JsonResult>[];
    final transport = FlatpakBrowserTransport(
      call: (raw) {
        calls.add(jsonDecode(raw) as JsonResult);
        return calls.length == 1 ? first.future : Future.value('{"ok":true}');
      },
    );
    final certificates = {'SYNTHETIC': '0102'};
    final a = transport.request('firefox.inspect');
    final b = transport.request('chrome.inspect', certificates: certificates);
    certificates.clear();
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(1));
    first.complete('{"ok":true}');
    await Future.wait([a, b]);
    expect(calls.map((c) => c['op']), ['firefox.inspect', 'chrome.inspect']);
    expect(calls.last['certificates'], {'SYNTHETIC': '0102'});
  });
  test(
    'transport exposes only fixed operations, public DER and opaque plans',
    () async {
      final host = Host(),
          transport = FlatpakBrowserTransport(
            call: (raw) async => Host().request(raw),
          );
      final firefox = FlatpakFirefoxSetupService(
        FlatpakBrowserTransport(call: host.request),
      );
      firefox.certificates = {'SYNTHETIC': '010203'};
      await firefox.inspect();
      await firefox.plan('1' * 64);
      await firefox.apply('1' * 64, '2' * 64);
      expect(host.calls.map((v) => v['op']), [
        'firefox.inspect',
        'firefox.plan',
        'firefox.apply',
      ]);
      for (final call in host.calls) {
        expect(call['certificates'], {'SYNTHETIC': '010203'});
        expect(
          call.keys,
          everyElement(
            isIn(['protocol', 'op', 'profile', 'fingerprint', 'certificates']),
          ),
        );
      }
      expect((await transport.request('status'))['fullPinRequired'], true);
    },
  );
  test('missing and malformed transport replies remain recoverable', () async {
    for (final raw in ['[]', 'not json', 'null']) {
      expect(
        (await FlatpakBrowserTransport(call: (_) async => raw)
            .request('status'))['code'],
        'helper_unavailable',
      );
    }
    expect(
      (await FlatpakBrowserTransport(
        call: (_) async => throw MissingPluginException(),
      ).request('status'))['code'],
      'helper_missing',
    );
  });
  for (final configured in [false, true]) {
    testWidgets(
      'Flatpak Home uses external inspection only, configured=$configured',
      (t) async {
        size(t);
        final host = Host()..configured = configured;
        final transport = FlatpakBrowserTransport(call: host.request),
            service = LinuxPairedService();
        await t.pumpWidget(
          CiePrototype(
            flatpak: true,
            service: service,
            settings: MemorySettingsStore()
              ..value = AppSettings(languageCode: 'it'),
            firefoxSetupService: FlatpakFirefoxSetupService(transport),
            chromeSetupService: FlatpakChromeSetupService(transport),
            webStatusReader: () async => {},
            webPublisher: (_, _) async => fail('No direct host publication'),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('flatpak-web-notice')), findsNothing);
        expect(
          find.text('Configura Firefox'),
          configured ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Configura Chrome'),
          configured ? findsNothing : findsOneWidget,
        );
        if (configured) {
          expect(
            t.widget<Text>(find.byKey(pairedStatus)).data,
            contains('Firefox, Google Chrome'),
          );
        }
        expect(
          host.calls.every(
            (v) => [
              'status',
              'firefox.inspect',
              'chrome.inspect',
            ].contains(v['op']),
          ),
          true,
        );
        expect(
          service.signCalls + service.completeCalls + service.enrollCalls,
          0,
        );
        expect(find.byType(TextField), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'missing companion shows one notice, refresh discovers it without writes',
    (t) async {
      size(t);
      final host = Host()..present = false;
      final transport = FlatpakBrowserTransport(call: host.request);
      await t.pumpWidget(
        CiePrototype(
          flatpak: true,
          service: LinuxPairedService(),
          settings: MemorySettingsStore()
            ..value = AppSettings(languageCode: 'it'),
          firefoxSetupService: FlatpakFirefoxSetupService(transport),
          chromeSetupService: FlatpakChromeSetupService(transport),
          webStatusReader: () async => {},
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('flatpak-web-notice')), findsOneWidget);
      expect(host.calls.every((v) => v['op'] == 'status'), true);
      host.present = true;
      await t.tap(find.text('Rileggi'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('flatpak-web-notice')), findsNothing);
      expect(find.text('Configura Firefox'), findsOneWidget);
      expect(
        host.calls.any((v) => v['op'].toString().endsWith('apply')),
        false,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'external Chrome setup writes only after confirmation, public DER only',
    (t) async {
      size(t);
      final host = Host(), service = LinuxPairedService();
      service.records['TEST']!['certificateHex'] = '010203';
      final transport = FlatpakBrowserTransport(call: host.request);
      await t.pumpWidget(
        CiePrototype(
          flatpak: true,
          service: service,
          settings: MemorySettingsStore()
            ..value = AppSettings(languageCode: 'it'),
          firefoxSetupService: FlatpakFirefoxSetupService(transport),
          chromeSetupService: FlatpakChromeSetupService(transport),
          webStatusReader: () async => {},
        ),
      );
      await t.pumpAndSettle();
      expect(
        host.calls
            .where((v) => v['op'] == 'chrome.inspect')
            .last['certificates'],
        {'TEST': '010203'},
      );
      await t.tap(find.widgetWithText(OutlinedButton, 'Configura Chrome'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Continua'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(FilledButton, 'Configura Chrome'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Conferma configurazione'), findsOneWidget);
      expect(host.calls.any((v) => v['op'] == 'chrome.apply'), false);
      await t.tap(find.widgetWithText(FilledButton, 'Configura'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final applies = host.calls
          .where((v) => v['op'] == 'chrome.apply')
          .toList();
      expect(applies, hasLength(1));
      expect(applies.single['certificates'], {'TEST': '010203'});
      expect(applies.single['fingerprint'], '2' * 64);
      expect(
        find.text(
          'Chrome è configurato. Riaprilo e usa il PIN completo di otto cifre.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        service.signCalls + service.completeCalls + service.enrollCalls,
        0,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
