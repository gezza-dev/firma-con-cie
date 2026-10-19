// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'signing_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/verification_view.dart';

class FakeService implements CieService, SigningInfoService {
  @override
  Future<JsonResult> signingInfo(String path) async => {
    'ok': true,
    'pdfSupported': path.endsWith('.pdf'),
    'cosignSupported': path.endsWith('.p7m'),
    'signatureCount': path.endsWith('.p7m') ? 2 : 0,
  };
  @override
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  }) async => {'ok': false};
  Completer<JsonResult>? detection;
  Completer<JsonResult>? signing;
  int signCalls = 0;
  int detectCalls = 0;
  @override
  Future<JsonResult> load() async => {'ok': true, 'canSign': true};
  @override
  Future<JsonResult> detect() async {
    detectCalls++;
    return detection == null
        ? {
            'ok': true,
            'readers': [
              {
                'name': 'Lettore di prova',
                'present': true,
                'isCie': true,
                'cardId': 'TEST-CARD',
              },
            ],
          }
        : detection!.future;
  }

  @override
  Future<JsonResult> verify(String path) async => {
    'ok': true,
    'signatureCount': 0,
    'signers': [],
  };
  @override
  Future<JsonResult> pdfInfo(String path, int page) async => {
    'ok': true,
    'pageCount': 1,
    'rotation': 0,
    'width': 600,
    'height': 800,
  };
  @override
  Future<JsonResult> extract(String input, String output) async => {
    'ok': false,
  };
  @override
  Future<JsonResult> sign({
    required String reader,
    required String card,
    required String input,
    required String output,
    required String format,
    required String pin,
    PdfAppearance? appearance,
    bool replaceExisting = false,
  }) async {
    signCalls++;
    return signing == null ? {'ok': false} : signing!.future;
  }
}

Future<void> showVerificationDetails(WidgetTester t) async {
  final labels = t
      .widgetList<Text>(find.textContaining('Dettagli del firmatario'))
      .map((w) => w.data!)
      .toList();
  for (final label in labels) {
    await t.ensureVisible(find.text(label));
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }
}

void main() {
  for (final reason in [
    'tsa_chain_not_trusted_at_timestamp',
    'timestamp_critical_extension_unsupported',
  ]) {
    testWidgets(
      'unverifiable timestamp explains $reason without invalid label',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VerificationView(
                  result: {
                    'ok': true,
                    'signatureCount': 1,
                    'signers': [
                      {
                        'signatureValid': true,
                        'timestampStatus': 'indeterminate',
                        'timestampReason': reason,
                        'historicalStatus': 'indeterminate',
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        );
        await showVerificationDetails(tester);
        expect(
          find.textContaining('Marca temporale non verificabile'),
          findsOneWidget,
        );
        expect(find.text(timestampDetail(reason)), findsOneWidget);
        expect(find.textContaining('Marca temporale non valida'), findsNothing);
        expect(
          find.textContaining('Impronta, firma e catena TSA verificate'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'verified timestamp without revocation is not historical validity',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': true,
                  'signatureCount': 1,
                  'signers': [
                    {
                      'commonName': 'Synthetic test',
                      'signatureValid': true,
                      'timestampStatus': 'verified',
                      'timestampTime': '2026-10-16T10:00:00Z',
                      'historicalStatus': 'indeterminate',
                      'historicalReason': 'tsa_historical_revocation_evidence_missing_or_adverse',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await showVerificationDetails(tester);
      expect(
        find.textContaining('Impronta, firma e catena TSA verificate'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Validità storica non determinabile con le prove disponibili',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Valida alla data della marca'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'historical validity is independent of current certificate expiry',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': true,
                  'signatureCount': 1,
                  'signers': [
                    {
                      'commonName': 'Synthetic test',
                      'signatureValid': true,
                      'certificateWithinValidity': false,
                      'timestampStatus': 'verified',
                      'timestampTime': '2026-10-16T10:00:00Z',
                      'historicalStatus': 'valid_at_timestamp',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await showVerificationDetails(tester);
      expect(
        find.text(
          'Certificato nel periodo di validità: fuori dal periodo attuale',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Valida alla data della marca secondo le prove verificate'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows detected card, disables actions during native operation and recovers',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      expect(service.detectCalls, 0);
      await tester.tap(find.text('Verifica Firma'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'La verifica dei documenti non richiede lettore, carta o PIN.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rileva carta'));
      await tester.pumpAndSettle();
      expect(find.text('CIE presente nel lettore'), findsOneWidget);
      service.detection = Completer<JsonResult>();
      await tester.tap(find.text('Rileva carta'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Rileva carta'),
      );
      expect(button.onPressed, isNull);
      service.detection!.complete({'ok': true, 'readers': []});
      await tester.pumpAndSettle();
      expect(find.text('Nessun lettore collegato.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'verification distinguishes integrity, validity dates and unknown revocation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': true,
                  'signatureCount': 1,
                  'signers': [
                    {
                      'commonName': 'Test signer',
                      'signatureValid': true,
                      'certificateWithinValidity': true,
                      'revocationStatus': 3,
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await showVerificationDetails(tester);
      expect(find.text('Integrità crittografica: valido'), findsOneWidget);
      expect(
        find.text('Revoca: Stato di revoca non determinato'),
        findsOneWidget,
      );
      expect(
        find.text('Catena di fiducia non verificata dal backend'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'valid integrity never promotes an untrusted chain or unknown CA revocation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': true,
                  'signatureCount': 2,
                  'signers': [
                    {
                      'commonName': 'Unknown authority',
                      'signatureValid': true,
                      'certificateWithinValidity': true,
                      'revocationStatus': 3,
                      'trustChainChecked': true,
                      'trustChainStatus': 'untrusted',
                      'trustChainValidated': false,
                      'chainRevocationStatus': 3,
                    },
                    {
                      'commonName': 'Trusted path, unavailable issuer CRL',
                      'signatureValid': true,
                      'certificateWithinValidity': true,
                      'revocationStatus': 0,
                      'trustChainChecked': true,
                      'trustChainStatus': 'trusted',
                      'trustSource': 'cie_ministry',
                      'trustChainValidated': true,
                      'chainRevocationStatus': 3,
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await showVerificationDetails(tester);
      expect(find.text('Integrità crittografica: valido'), findsNWidgets(2));
      expect(
        find.text('Catena non attendibile · autorità non riconosciuta'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Catena di fiducia verificata'),
        findsOneWidget,
      );
      expect(
        find.text('Revoca della catena: Stato di revoca non determinato'),
        findsNWidgets(2),
      );
      expect(
        find.text(
          'Revoca del firmatario: Non revocato secondo il servizio consultato',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long errors remain scrollable in a small window', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ErrorNotice(
              result: {
                'ok': false,
                'message': List.filled(
                  50,
                  'Messaggio lungo leggibile',
                ).join(' '),
                'code': 'test',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Messaggio lungo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'signing clears the PIN immediately and never retries after an error',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService()..signing = Completer<JsonResult>();
      await tester.pumpWidget(
        CiePrototype(
          service: service,
          signedFilePicker: (_) async =>
              '${Directory.systemTemp.path}/cie-test-${DateTime.now().microsecondsSinceEpoch}.pdf',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rileva carta'));
      await tester.pumpAndSettle();
      await signingDocument(tester);
      // Synthetic test data: the injected service never talks to a smart card.
      await tester.enterText(find.byType(TextField), '12345678');
      final pinController = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await pressSign(tester);
      expect(pinController.text, isEmpty);
      expect(service.signCalls, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.runAsync(() async {
        service.signing!.complete({
          'ok': false,
          'code': 'pin_incorrect',
          'message': 'PIN errato',
        });
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(find.text('PIN errato'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
