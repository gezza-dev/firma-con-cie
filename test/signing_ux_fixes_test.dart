// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/signature_image.dart';

import 'home_enrollment_test.dart' show UnifiedFake;
import 'signing_helpers.dart';

class _NamedService extends UnifiedFake implements CertificateNameService {
  int nameReads = 0;
  @override
  Future<JsonResult> load() async => {
    ...await super.load(),
    'canSignPdfAppearance': true,
  };
  @override
  Future<JsonResult> certificateName(String certificateHex) async {
    nameReads++;
    return {
      'ok': true,
      'fullName': 'Giulia Maria Rossi',
      'cardNumber': 'CA00000AA',
    };
  }
}

void main() {
  test('legacy name recovery uses only owned public certificate and changes no enrollment flags', () async {
    final service = _NamedService();
    service.records['CARD'] = {
      'card': 'CARD',
      'version': 1,
      'readyForSigning': true,
      'publicDataSaved': false,
    };
    final controller = EnrollmentController(
      service,
      systemStatus: () async => {
        'certificateHexByCard': {'CARD': '300100'},
      },
    );
    await controller.refresh();
    expect(controller.records['CARD']!.name, 'Giulia Maria Rossi');
    expect(controller.records['CARD']!.cardNumber, 'CA00000AA');
    expect(controller.records['CARD']!.hasPublicData, isFalse);
    expect(service.enrollCalls, 0);
    expect(service.signCalls, 0);
    expect(service.nameReads, 1);
    service.records['CARD']!['fullName'] = 'Nome già verificato';
    await controller.refresh();
    expect(controller.records['CARD']!.name, 'Nome già verificato');
    expect(controller.records['CARD']!.cardNumber, 'CA00000AA');
    expect(service.nameReads, 2);
  });

  test('signature preview shows local civil time and exact UTC offset', () {
    final local = DateTime(2026, 10, 18, 15, 4, 5);
    expect(
      signatureDateLabel(local),
      '18/10/2026 15:04:05 ${signatureUtcOffsetLabel(local.timeZoneOffset)}',
    );
    expect(signatureDateLabel(local.toUtc()), signatureDateLabel(local));
    for (final pair in [
      (0, 'UTC'),
      (60, 'UTC+1'),
      (120, 'UTC+2'),
      (-60, 'UTC-1'),
      (-120, 'UTC-2'),
      (330, 'UTC+5:30'),
      (345, 'UTC+5:45'),
      (-210, 'UTC-3:30'),
    ]) {
      expect(signatureUtcOffsetLabel(Duration(minutes: pair.$1)), pair.$2);
    }
  });

  test('appearance captions precede personal data and use smaller light-blue text', () {
    final span = signatureTextSpan(
      fullName: 'Giulia Rossi',
      signingDate: DateTime(2026, 10, 18),
    );
    expect(
      span.toPlainText(),
      'Firmato digitalmente da/Signed by:\nGiulia Rossi\nIn Data/On Date:\n18/10/2026 00:00:00 ${signatureUtcOffsetLabel(DateTime(2026, 10, 18).timeZoneOffset)}',
    );
    final children = span.children!.cast<TextSpan>();
    for (final index in [0, 2]) {
      expect(children[index].style!.color, signatureCaptionColor);
      expect(children[index].style!.fontSize!, lessThan(span.style!.fontSize!));
      expect(
        children[index].style!.fontSize!,
        lessThan(children[3].style!.fontSize!),
      );
    }
  });

  testWidgets(
    'name, centered triangles, conditional graphic step and wizard-only aligned back',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = _NamedService();
      service.records['123456789012'] = {
        'card': '123456789012',
        'version': 2,
        'fullName': 'Giulia Maria Rossi',
        'readyForSigning': true,
        'publicDataSaved': true,
        'certificateHex': '300100',
      };
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webStatusReader: () async => {},
          webPublisher: (_, _) async {},
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Giulia Maria Rossi'), findsOneWidget);
      expect(find.textContaining('123456789012'), findsNothing);
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Indietro'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Giulia Maria Rossi'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(5));
      expect(find.byIcon(Icons.play_arrow), findsNWidgets(4));
      final center = t.getCenter(find.byType(Chip).first).dy;
      for (var i = 0; i < 4; i++) {
        expect(
          t.getCenter(find.byIcon(Icons.play_arrow).at(i)).dy,
          closeTo(center, .1),
        );
      }
      await signingDocument(t, pairedCard: '123456789012', toPin: false);
      final graphic = find.widgetWithText(
        CheckboxListTile,
        'Aggiungi firma grafica',
      );
      expect(t.widget<CheckboxListTile>(graphic).value, isTrue);
      expect(find.text('Firma grafica'), findsOneWidget);
      await t.ensureVisible(graphic);
      await t.tap(graphic);
      await t.pumpAndSettle();
      expect(find.text('Firma grafica'), findsNothing);
      expect(find.byType(Chip), findsNWidgets(4));
      await t.tap(graphic);
      await t.pumpAndSettle();
      expect(find.text('Firma grafica'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(5));
      await t.ensureVisible(find.text('Indietro'));
      final back = find.widgetWithText(OutlinedButton, 'Indietro');
      final heading = find.byKey(const ValueKey('page-title'));
      expect(t.getTopRight(back).dx, lessThan(t.getTopLeft(heading).dx));
      final headerRow = find
          .ancestor(of: heading, matching: find.byType(Row))
          .first;
      expect(t.getCenter(heading).dx, closeTo(t.getCenter(headerRow).dx, .1));
      await t.tap(back);
      await t.pumpAndSettle();
      expect(find.text('Seleziona un documento'), findsOneWidget);
      await t.tap(find.text('Indietro'));
      await t.pumpAndSettle();
      expect(find.text('Scegli la CIE con cui firmare'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Indietro'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Informazioni').first);
      await t.pumpAndSettle();
      expect(find.text('Indietro'), findsNothing);
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      expect(t.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
