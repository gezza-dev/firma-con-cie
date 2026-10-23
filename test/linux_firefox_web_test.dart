// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/web_access.dart';

import 'home_enrollment_test.dart' show UnifiedFake;
import 'web_access_test.dart' show FakeWeb;

void main() {
  test('Linux Web certificate never implies that Firefox is configured', () {
    final record = EnrollmentRecord(
      {
        'card': 'TEST',
        'publicDataSaved': true,
        'readyForSigning': true,
        'webProvisioned': true,
      },
      {
        'available': true,
        'browserRegistrationRequired': true,
        'browserConfigurationVerified': false,
      },
    );
    expect(record.componentAvailable, isTrue);
    expect(record.webProvisioned, isTrue);
    expect(record.webStatus, EnrollmentRecord.firefoxSetupMessage);
    expect(record.webStatus, contains('otto cifre'));
    expect(record.webStatus, contains('resta una prova separata'));
  });

  test(
    'Linux publication completion preserves the separate Firefox step',
    () async {
      final service = _LinuxEnrollment();
      final controller = EnrollmentController(
        service,
        publisher: (_, _) async {},
        systemStatus: () async => {},
      );
      await controller.refresh();
      expect((await controller.complete('TEST'))['ok'], isTrue);
      expect(controller.message, EnrollmentRecord.firefoxSetupMessage);
      expect(service.enrollCalls, 0);
    },
  );

  testWidgets('Firefox information does not start a proof or ask for a PIN', (
    t,
  ) async {
    final service = FakeWeb();
    var proofs = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebAccessCard(
              service: service,
              reader: 'test-reader',
              card: 'TEST001',
              enabled: true,
              linuxFirefox: true,
              onBusy: (_) {},
              tester: (_) async {
                proofs++;
                return {'ok': true};
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('Prova componente di sistema'), findsNothing);
    await t.tap(find.text('Informazioni browser'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(linuxFirefoxInformationMessage), findsOneWidget);
    expect(
      linuxFirefoxInformationMessage,
      contains('PIN completo di otto cifre'),
    );
    expect(linuxFirefoxInformationMessage, contains('Firefox Snap'));
    expect(linuxFirefoxInformationMessage, contains('Chrome'));
    expect(linuxFirefoxInformationMessage, contains('NSS'));
    expect(
      linuxFirefoxInformationMessage,
      contains('solo il profilo scelto dopo conferma'),
    );
    expect(find.byType(TextField), findsNothing);
    expect(proofs, 0);
    expect(service.enrollments, 0);
    expect(service.removals, 0);
    await t.tap(find.text('Chiudi'));
    await t.pumpAndSettle();
  });
}

class _LinuxEnrollment extends UnifiedFake {
  _LinuxEnrollment() {
    records['TEST'] = {
      'card': 'TEST',
      'version': 2,
      'publicDataSaved': true,
      'readyForSigning': true,
      'webProvisioned': true,
      'certificateHex': '300100',
    };
  }
  @override
  Future<Map<String, dynamic>> webStatus() async => {
    'available': true,
    'browserRegistrationRequired': true,
    'browserConfigurationVerified': false,
  };
}
