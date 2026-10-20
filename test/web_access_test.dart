// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/web_access.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/app_settings.dart';

class FakeWeb implements WebAccessService {
  int enrollments = 0, removals = 0;
  @override
  Future<JsonResult> enrollWeb(
    String reader,
    String card,
    String fullPin,
  ) async {
    expect(reader, 'test-reader');
    expect(card, 'TEST001');
    expect(fullPin, '12345678');
    enrollments++;
    return {'ok': true, 'certificateHex': '300100'};
  }

  @override
  Future<JsonResult> forgetWeb(String card) async {
    expect(card, 'TEST001');
    removals++;
    return {'ok': true};
  }

  @override
  Future<JsonResult> testWeb(String card) async => {'ok': true};
}

Widget view(FakeWeb service, WebPublisher publisher) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: WebAccessCard(
        service: service,
        reader: 'test-reader',
        card: 'TEST001',
        enabled: true,
        onBusy: (_) {},
        publisher: publisher,
      ),
    ),
  ),
);
void main() {
  test('web diagnostics never export enrollment certificate or identity', () {
    final recorder = DiagnosticRecorder()
      ..level = AppDiagnosticLevel.operations;
    recorder.record('web_enroll', {
      'ok': true,
      'card': 'PERSONALIDENTITY',
      'certificateHex': 'CERTIFICATE_PRIVATE_REPORT_MARKER',
      'pin': '12345678',
    }, 12);
    final text = recorder.events.toString();
    expect(text, contains('web_enroll'));
    for (final secret in [
      'PERSONALIDENTITY',
      'CERTIFICATE_PRIVATE_REPORT_MARKER',
      '12345678',
    ]) {
      expect(text, isNot(contains(secret)));
    }
  });
  testWidgets('cancel enrollment never sends a PIN', (tester) async {
    final service = FakeWeb();
    await tester.pumpWidget(view(service, (_, _) async {}));
    await tester.tap(find.text('Configura accesso ai siti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(service.enrollments, 0);
  });
  testWidgets('OS configuration retry does not repeat card authentication', (
    tester,
  ) async {
    final service = FakeWeb();
    var attempts = 0;
    await tester.pumpWidget(
      view(service, (card, hex) async {
        expect(card, 'TEST001');
        expect(hex, '300100');
        attempts++;
        if (attempts == 1) {
          throw PlatformException(
            code: 'not_registered',
            message: 'Attivare il componente di sistema.',
          );
        }
      }),
    );
    await tester.tap(find.text('Configura accesso ai siti'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('Leggi certificato e configura'));
    await tester.pumpAndSettle();
    expect(service.enrollments, 1);
    expect(attempts, 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completa configurazione senza PIN'));
    await tester.pumpAndSettle();
    expect(service.enrollments, 1);
    expect(attempts, 2);
    expect(
      find.textContaining('Certificato pubblico configurato'),
      findsOneWidget,
    );
  });
  testWidgets('removal asks confirmation and requires no PIN', (tester) async {
    final service = FakeWeb();
    var removed = 0;
    await tester.pumpWidget(
      view(service, (_, hex) async {
        expect(hex, isNull);
        removed++;
      }),
    );
    await tester.tap(find.text('Rimuovi configurazione Web'));
    await tester.pumpAndSettle();
    expect(service.removals, 0);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();
    expect(service.removals, 1);
    expect(removed, 1);
    expect(service.enrollments, 0);
  });
  testWidgets('local system proof requires confirmation and invokes once', (
    tester,
  ) async {
    final service = FakeWeb();
    var proofs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebAccessCard(
              service: service,
              reader: 'test-reader',
              card: 'TEST001',
              enabled: true,
              onBusy: (_) {},
              publisher: (_, _) async {},
              tester: (card) async {
                expect(card, 'TEST001');
                proofs++;
                return {'ok': true};
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Prova componente di sistema'));
    await tester.pumpAndSettle();
    expect(proofs, 0);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Avvia prova'));
    await tester.pumpAndSettle();
    expect(proofs, 1);
    expect(service.enrollments, 0);
  });
}
