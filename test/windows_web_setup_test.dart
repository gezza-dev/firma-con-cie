// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/windows_web_setup.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;
import 'web_completion_feedback_test.dart' show pairedService;

// Windows publishes inside enroll(), before returning to Dart. The platform
// publisher is a no-op there and must not be needed to make Home ready.
class FirstWindowsPairing extends UnifiedFake {
  int nativePublications = 0;
  @override
  Future<JsonResult> webStatus() async => {'ok': true, 'available': true};
  @override
  Future<JsonResult> enroll(String reader, String card, String pin) async {
    final result = await super.enroll(reader, card, pin);
    if (result['ok'] == true) {
      nativePublications++;
      records[card]!.addAll({
        'webProvisioned': true,
        'systemComponentAvailable': true,
      });
      return {'ok': true, ...records[card]!};
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh Windows profile publishes on first pairing without completion or platform setup',
    (t) async {
      final service = FirstWindowsPairing()..storage = 'file-cache-v3';
      service.insert();
      var checks = 0, publications = 0;
      t.view.physicalSize = const Size(1400, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> open() async {
        await t.pumpWidget(
          CiePrototype(
            service: service,
            settings: MemorySettingsStore(),
            webStatusReader: () async =>
                {}, // No macOS-style publishedCards override.
            webPublisher: (_, _) async {
              publications++;
            }, // Windows platform publication does nothing.
            windowsWebComponentChecker: (_) async {
              checks++;
              return {'ok': true};
            },
          ),
        );
        await t.pumpAndSettle();
      }

      await open();
      expect(service.records, isEmpty);
      expect(service.nativePublications, 0);
      expect(find.text('Completa accesso ai siti'), findsNothing);
      await t.tap(find.text('Abbina CIE'));
      await t.pumpAndSettle();
      expect(checks, 1);
      await t.enterText(find.byType(TextField), '12345678');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(service.enrollCalls, 1);
      expect(service.nativePublications, 1);
      expect(service.completeCalls, 0);
      expect(
        publications,
        1,
      ); // The callback is invoked, but supplies no readiness flags.
      expect(service.records['TEST']!['webProvisioned'], isTrue);
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsOneWidget,
      );
      expect(find.text('Completa accesso ai siti'), findsNothing);
      expect(find.text('Attiva accesso ai siti'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await open(); // Restored pairing stays ready after restarting the UI.
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsOneWidget,
      );
      expect(find.text('Completa accesso ai siti'), findsNothing);
      expect(service.enrollCalls, 1);
      expect(service.completeCalls, 0);
      expect(service.nativePublications, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  Future<void> start(
    WidgetTester t,
    UnifiedFake service,
    PublicSystem system,
    WindowsWebComponentChecker installer,
  ) async {
    t.view.physicalSize = const Size(1400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      CiePrototype(
        service: service,
        settings: MemorySettingsStore(),
        webPublisher: system.publish,
        webStatusReader: system.status,
        windowsWebComponentChecker: installer,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'read-only component check finishes before PIN and pairing publishes automatically',
    (t) async {
      final service = UnifiedFake()..insert();
      final system = PublicSystem()..available = false;
      final pending = Completer<JsonResult>();
      var calls = 0;
      await start(t, service, system, (reader) {
        expect(reader, 'Reader');
        calls++;
        return pending.future;
      });
      await t.tap(find.text('Abbina CIE'));
      await t.pump();
      expect(calls, 1);
      expect(find.byType(TextField), findsNothing);
      expect(service.enrollCalls, 0);
      final scans = service.observations;
      await t.pump(const Duration(seconds: 3));
      expect(service.observations, scans);
      system.available = true;
      pending.complete({'ok': true});
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField), '12345678');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(service.enrollCalls, 1);
      expect(system.publications, 1);
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final signingOnly in [false, true]) {
    testWidgets(
      'missing component sends no PIN; explicit signing fallback=$signingOnly',
      (t) async {
        final service = UnifiedFake()..insert();
        final system = PublicSystem()..available = false;
        var calls = 0;
        await start(t, service, system, (_) async {
          calls++;
          return {
            'ok': false,
            'code': 'web_component_missing',
            'message': 'Esegui il pacchetto di installazione.',
          };
        });
        await t.tap(find.text('Abbina CIE'));
        await t.pumpAndSettle();
        expect(
          find.text('Esegui il pacchetto di installazione.'),
          findsWidgets,
        );
        expect(find.byType(TextField), findsNothing);
        expect(service.enrollCalls, 0);
        expect(system.publications, 0);
        await t.tap(
          find.text(signingOnly ? 'Continua solo per firmare' : 'Annulla'),
        );
        await t.pumpAndSettle();
        expect(
          find.byType(TextField),
          signingOnly ? findsOneWidget : findsNothing,
        );
        expect(service.enrollCalls, 0);
        expect(calls, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('already paired CIE checks and republishes without PIN', (
    t,
  ) async {
    final service = pairedService()..insert();
    final system = PublicSystem()..available = false;
    system.cards.add('TEST');
    var calls = 0;
    await start(t, service, system, (reader) async {
      expect(reader, 'Reader');
      calls++;
      system.available = true;
      return {'ok': true};
    });
    await t.tap(find.text('Completa accesso ai siti'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(service.completeCalls, 1);
    expect(service.enrollCalls, 0);
    expect(system.publications, 1);
    expect(find.byType(TextField), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'activation for existing pairing requires its card and preserves pairing',
    (t) async {
      final service = pairedService();
      final system = PublicSystem()..available = false;
      system.cards.add('TEST');
      var calls = 0;
      await start(t, service, system, (_) async {
        calls++;
        return {'ok': true};
      });
      await t.tap(find.text('Completa accesso ai siti'));
      await t.pumpAndSettle();
      expect(calls, 0);
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      expect(service.records, contains('TEST'));
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'component check is inactive off Windows and never invokes installation',
    () async {
      const channel = MethodChannel('cie.id/windows-web-setup');
      var installs = 0, statuses = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'check') {
              installs++;
              expect(call.arguments, {'reader': 'Reader'});
              return true;
            }
            statuses++;
            return statuses == 1
                ? {'pending': true}
                : {'pending': false, 'nativeCode': 10};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await checkWindowsWebComponent('Reader');
      if (Platform.isWindows) {
        expect(result['code'], 'web_component_missing');
        expect(installs, 1);
        expect(statuses, 2);
      } else {
        expect(result['ok'], isTrue);
        expect(installs, 0);
        expect(statuses, 0);
      }
    },
  );
}
