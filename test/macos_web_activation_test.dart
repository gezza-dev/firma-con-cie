// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/web_access.dart';

import 'home_enrollment_test.dart' show PublicSystem;
import 'web_completion_feedback_test.dart' show pairedService, size;

class ActivationSystem extends PublicSystem {
  bool needsSettings = true;
  @override
  Future<Map<String, dynamic>> status() async => {
    ...await super.status(),
    'canOpenSystemSettings': needsSettings && !available,
    'activationState': available ? 'enabled' : 'disabled',
  };
}

void main() {
  testWidgets('settings bridge invokes only the fixed native opening method', (
    t,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('cie.prototype/web');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    expect(await openWebSystemSettings(), isTrue);
    expect(calls.single.method, 'openSystemSettings');
    expect(calls.single.arguments, isNull);
  });

  for (final published in [false, true]) {
    testWidgets(
      'disabled component opens Settings without PIN, published=$published',
      (t) async {
        size(t);
        final service = pairedService();
        final system = ActivationSystem()..available = false;
        if (published) system.cards.add('TEST');
        var opens = 0;
        await t.pumpWidget(
          CiePrototype(
            service: service,
            settings: MemorySettingsStore(),
            webPublisher: system.publish,
            webStatusReader: system.status,
            webSettingsOpener: () async {
              opens++;
              return true;
            },
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Apri Impostazioni di Sistema'), findsOneWidget);
        await t.tap(find.text('Apri Impostazioni di Sistema'));
        await t.pumpAndSettle();
        expect(opens, 1);
        expect(service.enrollCalls, 0);
        expect(service.completeCalls, 0);
        expect(system.publications, 0);
        expect(find.byType(TextField), findsNothing);
        expect(service.records['TEST']!['readyForSigning'], isTrue);
        expect(find.byType(AlertDialog), findsOneWidget);
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        system.available = true;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(find.text('Apri Impostazioni di Sistema'), findsNothing);
        expect(
          find.text('Accesso ai siti configurato: apri il sito nel browser.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('In Impostazioni di Sistema apri'),
          findsNothing,
        );
        expect(service.completeCalls, published ? 0 : 1);
        expect(system.publications, published ? 0 : 1);
        expect(service.enrollCalls, 0);
        expect(service.signCalls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('opening failure keeps pairing and explains manual recovery', (
    t,
  ) async {
    size(t);
    final service = pairedService();
    final system = ActivationSystem()..available = false;
    await t.pumpWidget(
      CiePrototype(
        service: service,
        webPublisher: system.publish,
        webStatusReader: system.status,
        webSettingsOpener: () async => false,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Apri Impostazioni di Sistema'));
    await t.pumpAndSettle();
    expect(find.textContaining('Non è stato possibile aprire'), findsOneWidget);
    expect(service.records, contains('TEST'));
    expect(service.enrollCalls, 0);
    expect(service.completeCalls, 0);
    await t.pumpWidget(const SizedBox());
  });

  test('public completion after activation is attempted once; errors never repeat authentication', () async {
    final service = pairedService();
    final system = ActivationSystem()..available = false;
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.refresh();
    system.available = true;
    system.failPublish = true;
    await controller.refreshSystem();
    await controller.refreshSystem();
    expect(service.completeCalls, 1);
    expect(system.publications, 1);
    expect(service.enrollCalls, 0);
    expect(controller.records['TEST']!.readyForSigning, isTrue);
  });

  testWidgets(
    'enabled component without an observed card never shows Settings',
    (t) async {
      size(t);
      final service = pairedService();
      final system = ActivationSystem()..cards.add('TEST');
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Apri Impostazioni di Sistema'), findsNothing);
      expect(
        find.text('Accesso ai siti configurato: apri il sito nel browser.'),
        findsOneWidget,
      );
      expect(service.enrollCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final outcome in ['cancel', 'success', 'failure']) {
    testWidgets('guided activation $outcome preserves pairing without PIN', (
      t,
    ) async {
      size(t);
      final service = pairedService();
      final system = ActivationSystem()..available = false;
      var activations = 0;
      Future<Map<String, dynamic>> status() async => {
        ...await system.status(),
        'canActivateComponent': !system.available,
      };
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webPublisher: system.publish,
          webStatusReader: status,
          webComponentActivator: () async {
            activations++;
            if (outcome == 'success') system.available = true;
            return {'ok': outcome == 'success'};
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Apri Impostazioni di Sistema'), findsNothing);
      await t.tap(find.text('Attiva accesso ai siti'));
      await t.pumpAndSettle();
      expect(activations, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text(outcome == 'cancel' ? 'Annulla' : 'Attiva'));
      await t.pumpAndSettle();
      expect(activations, outcome == 'cancel' ? 0 : 1);
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      expect(service.records['TEST']!['readyForSigning'], isTrue);
      if (outcome == 'success') {
        expect(find.text('Attiva accesso ai siti'), findsNothing);
        expect(
          find.text('Accesso ai siti configurato: apri il sito nel browser.'),
          findsOneWidget,
        );
        expect(service.completeCalls, 1);
        expect(system.publications, 1);
      } else {
        expect(find.text('Attiva accesso ai siti'), findsOneWidget);
        expect(service.completeCalls, 0);
        if (outcome == 'failure') {
          expect(
            find.textContaining('Attivazione non completata.'),
            findsOneWidget,
          );
        }
      }
      await t.pump(const Duration(seconds: 10));
      expect(activations, outcome == 'cancel' ? 0 : 1);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'activation bridge takes no card, PIN or caller-selected command',
    (t) async {
      const channel = MethodChannel('cie.prototype/web');
      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return {'ok': true};
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect((await activateWebComponent())['ok'], isTrue);
      expect(calls.single.method, 'activateComponent');
      expect(calls.single.arguments, isNull);
    },
  );

  test('a removal-pending record cannot publish on activation', () async {
    final service = pairedService()..removeFailed = true;
    final system = ActivationSystem()..available = false;
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.refresh();
    await controller.remove('TEST');
    system.available = true;
    await controller.refreshSystem();
    expect(service.completeCalls, 0);
    expect(service.enrollCalls, 0);
    expect(controller.records['TEST']!.removalPending, isTrue);
  });
}
