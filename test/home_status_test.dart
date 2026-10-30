// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/home_card_status.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/main.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

void main() {
  test('reinsertion advice requires a known reset/power failure, not a missing diagnostic confirmation', () {
    String status(List<Map<String, dynamic>> readers) =>
        homeCardStatus(readers: readers, checked: true);
    for (final code in [0x80100067, 0x80100068, -2146434969, -2146434968]) {
      expect(
        status([
          {'nativeCode': code},
        ]),
        contains('Rimuovi la CIE'),
      );
    }
    for (final reader in [
      {'isCie': true, 'present': true},
      {'present': false},
      {'present': true, 'identificationCode': -4},
      {'present': true, 'nativeCode': -5},
      {'present': true, 'occupied': true},
      {'present': true, 'identificationCode': -3},
    ]) {
      expect(status([reader]), isNot(contains('Rimuovi')));
    }
    expect(
      status([
        {'isCie': true, 'present': true},
        {'nativeCode': 0x80100068},
      ]),
      'CIE presente nel lettore.',
    );
  });
  test('system observation changes diagnostics, not configured Home status; export omits identity', () {
    final records = [
      for (final observed in [false, true])
        EnrollmentRecord(
          {
            'card': 'PERSONAL_ID',
            'fullName': 'PRIVATE NAME',
            'certificateHex': '300100',
            'publicDataSaved': true,
            'readyForSigning': true,
          },
          {
            'available': true,
            'publishedCards': ['PERSONAL_ID'],
            'observedCards': observed ? ['PERSONAL_ID'] : [],
          },
        ),
    ];
    expect(records[0].status, records[1].status);
    expect(records[0].webStatus, records[1].webStatus);
    expect(records[0].identityObserved, isFalse);
    expect(records[1].identityObserved, isTrue);
    final report = DiagnosticRecorder().snapshot(
      network: const SessionNetworkConfig(),
      webAccess: [
        records[0].diagnosticFlags,
        {...records[1].diagnosticFlags, 'PRIVATE_ID': true},
      ],
      enrollmentReadable: true,
    );
    final exported = jsonEncode(report);
    for (final secret in [
      'PERSONAL_ID',
      'PRIVATE_ID',
      'PRIVATE NAME',
      '300100',
    ]) {
      expect(exported, isNot(contains(secret)));
    }
    expect(
      (report['webAccess'] as Map)['browserLoginTestedByStatusCheck'],
      isFalse,
    );
    expect(
      ((report['webAccess'] as Map)['cards'] as List)[0]['webIdentityObserved'],
      isFalse,
    );
  });
  testWidgets(
    'Home stays simple while system details are available only in Log without authentication',
    (t) async {
      t.view.physicalSize = const Size(1400, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = UnifiedFake()..insert();
      service.records['TEST'] = {
        'card': 'TEST',
        'fullName': 'Nome Cognome',
        'cardNumber': 'CA00000AA',
        'publicDataSaved': true,
        'readyForSigning': true,
        'certificateHex': '300100',
      };
      final system = PublicSystem()..cards.add('TEST');
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('CIE presente nel lettore.'), findsOneWidget);
      expect(
        find.text('CIE abbinata. Puoi firmare documenti.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('riconoscimento da parte del sistema'),
        findsNothing,
      );
      expect(find.textContaining('riappoggiala'), findsNothing);
      expect(find.text('Diagnostica accesso ai siti'), findsNothing);
      await t.tap(find.text('Impostazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Log'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Diagnostica accesso ai siti'));
      await t.tap(find.text('Diagnostica accesso ai siti'));
      await t.pumpAndSettle();
      expect(
        find.text('Identità esposta al sistema: non osservata al momento'),
        findsOneWidget,
      );
      expect(
        find.textContaining('non dimostra un errore di accesso'),
        findsOneWidget,
      );
      system.observed.add('TEST');
      // CTK metadata is no longer queried on every PC/SC polling cycle.
      // Diagnostics have an explicit refresh independent of card observation.
      await t.ensureVisible(find.text('Aggiorna stato configurazione'));
      await t.tap(find.text('Aggiorna stato configurazione'));
      await t.pumpAndSettle();
      expect(
        find.text('Identità esposta al sistema: osservata'),
        findsOneWidget,
      );
      await t.tap(find.text('Home').first);
      await t.pumpAndSettle();
      expect(
        find.text(
          'Accesso ai siti con CIE configurato. Apri il sito nel browser.',
        ),
        findsOneWidget,
      );
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
