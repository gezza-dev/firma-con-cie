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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> start(
    WidgetTester t,
    UnifiedFake service,
    PublicSystem system,
    WindowsWebInstaller installer,
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
        windowsWebInstaller: installer,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'installation finishes before PIN and pairing publishes automatically',
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
      'UAC refusal sends no PIN; explicit signing fallback=$signingOnly',
      (t) async {
        final service = UnifiedFake()..insert();
        final system = PublicSystem()..available = false;
        var calls = 0;
        await start(t, service, system, (_) async {
          calls++;
          return {
            'ok': false,
            'code': 'web_setup_cancelled',
            'message': 'Installazione annullata.',
          };
        });
        await t.tap(find.text('Abbina CIE'));
        await t.pumpAndSettle();
        expect(find.text('Installazione annullata.'), findsWidgets);
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

  testWidgets('already paired CIE activates and republishes without PIN', (
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
    await t.tap(find.text('Attiva accesso ai siti'));
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
      await t.tap(find.text('Attiva accesso ai siti'));
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
    'installer is inactive off Windows and polls cancellation once on Windows',
    () async {
      const channel = MethodChannel('cie.id/windows-web-setup');
      var installs = 0, statuses = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'install') {
              installs++;
              expect(call.arguments, {'reader': 'Reader'});
              return true;
            }
            statuses++;
            return statuses == 1
                ? {'pending': true}
                : {'pending': false, 'nativeCode': 1223};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await installWindowsWebComponent('Reader');
      if (Platform.isWindows) {
        expect(result['code'], 'web_setup_cancelled');
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
