// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/windows_web_setup.dart';

import 'web_completion_feedback_test.dart' show pairedService, size;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cie.id/windows-web-setup');
  for (final code in [0, 3, 6, 7, 9, 10, 11, 740, 1460]) {
    test(
      'package status $code only invokes reader-free read-only methods',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.arguments, isNull);
              calls.add(call.method);
              if (call.method == 'checkPackage') return true;
              expect(call.method, 'packageStatus');
              return {'pending': false, 'nativeCode': code};
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final result = await readWindowsWebComponentStatus();
        if (!Platform.isWindows) {
          expect(result, isEmpty);
          expect(calls, isEmpty);
        } else {
          expect(calls, ['checkPackage', 'packageStatus']);
          expect(result['available'], code == 0);
          expect(result['componentNeedsUpdate'], [6, 9, 10, 11].contains(code));
          expect(result['componentVersionMatches'], code == 0);
          expect(result['componentInstallerRequired'], code != 0);
          expect(result['componentStatusCode'], code);
          if ([740, 1460].contains(code)) {
            expect(
              result['componentStatusMessage'],
              contains('Non è stato possibile verificare'),
            );
          }
        }
      },
    );
  }
  test(
    'missing status bridge never claims the installed component is current',
    () async {
      final result = await readWindowsWebComponentStatus();
      if (Platform.isWindows) {
        expect(result['available'], isFalse);
        expect(result['componentNeedsUpdate'], isFalse);
        expect(
          result['componentStatusMessage'],
          contains('Non è stato possibile verificare'),
        );
      } else {
        expect(result, isEmpty);
      }
    },
  );
  testWidgets(
    'Home warns without a reader; installer advice preserves pairing and never publishes or asks PIN',
    (t) async {
      size(t);
      final service = pairedService();
      service.records['TEST']!['webProvisioned'] = true;
      final original = Map<String, dynamic>.from(service.records['TEST']!);
      var current = false, publications = 0, activations = 0, checks = 0;
      await t.pumpWidget(
        CiePrototype(
          service: service,
          settings: MemorySettingsStore(),
          webPublisher: (_, _) async {
            publications++;
          },
          webStatusReader: () async => <String, dynamic>{
            'available': current,
            'componentVersionMatches': current,
            'componentNeedsUpdate': !current,
            'componentInstallerRequired': !current,
            if (!current)
              'componentStatusMessage': windowsComponentUpdateMessage,
          },
          webComponentActivator: () async {
            activations++;
            return {'ok': true};
          },
          windowsWebComponentChecker: (_) async {
            checks++;
            return {'ok': true};
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(windowsComponentUpdateMessage), findsOneWidget);
      expect(find.text('Aggiorna accesso ai siti'), findsOneWidget);
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsNothing,
      );
      await t.tap(find.text('Aggiorna accesso ai siti'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(windowsComponentUpdateMessage), findsWidgets);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      current = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Aggiorna accesso ai siti'), findsNothing);
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsOneWidget,
      );
      expect(service.records['TEST'], original);
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      expect(service.signCalls, 0);
      expect(publications, 0);
      expect(activations, 0);
      expect(checks, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
}
