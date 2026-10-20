// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/signing_document.dart';

import 'widget_test.dart' show FakeService;
import 'pairing_test.dart' show PairedFake;
import 'signing_helpers.dart';

class SigningFake extends FakeService {
  bool supportedPdf = true, validCms = false, success = true;
  String? bytes, receivedPin, signedFormat, source;
  bool receivedReplacement = false;
  @override
  Future<JsonResult> load() async => {
    'ok': true,
    'canSign': true,
    'canCosign': true,
    'canSignPdfAppearance': true,
  };
  @override
  Future<JsonResult> signingInfo(String path) async => {
    'ok': true,
    'pdfSupported': supportedPdf,
    'cosignSupported': validCms,
    'signatureCount': validCms ? 2 : 0,
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
    receivedPin = pin;
    receivedReplacement = replaceExisting;
    signedFormat = format;
    source = input;
    bytes = await File(input).readAsString();
    return {
      'ok': success,
      'output': output,
      'message': 'Errore sintetico',
      'verification': {
        'ok': true,
        'signatureCount': 1,
        'signers': [
          {'signatureValid': true, 'revocationStatus': 'indeterminate'},
        ],
      },
    };
  }
}

void main() {
  Future<void> start(
    WidgetTester t,
    CieService service, {
    SignedFilePicker? picker,
    bool detect = true,
  }) async {
    t.view.physicalSize = const Size(1280, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      CiePrototype(service: service, signedFilePicker: picker),
    );
    await t.pumpAndSettle();
    if (detect) {
      await t.tap(find.text('Rileva carta'));
      await t.pumpAndSettle();
    }
  }

  String output() =>
      '${Directory.systemTemp.path}/cie-ux3-output-${DateTime.now().microsecondsSinceEpoch}.pdf';

  test('input is a bounded owned snapshot, preserved source and deterministic cleanup', () async {
    final folder = await Directory.systemTemp.createTemp('cie-snapshot-test-');
    addTearDown(() => folder.delete(recursive: true));
    final original = File('${folder.path}/input.pdf');
    await original.writeAsString('selected bytes');
    final snapshot = await SigningDocument.capture(original.path);
    await original.writeAsString('new bytes');
    expect(await File(snapshot.path).readAsString(), 'selected bytes');
    await snapshot.dispose();
    expect(await snapshot.directory.exists(), isFalse);
    expect(await original.readAsString(), 'new bytes');
    await original.writeAsString('');
    await expectLater(
      SigningDocument.capture(original.path),
      throwsFormatException,
    );
  });
  test(
    'saved artifact with unknown revocation is not reported as fully validated',
    () {
      expect(
        signedResultSummary({
          'ok': true,
          'signers': [
            {'signatureValid': true, 'revocationStatus': 3},
          ],
        }),
        contains('Verifica non conclusa'),
      );
      expect(
        signedResultSummary({
          'ok': true,
          'signers': [
            {'signatureValid': true, 'revocationStatus': 1},
          ],
        }),
        contains('segnala problemi'),
      );
      expect(signedResultSummary({'ok': false}), contains('non completata'));
      expect(
        signedResultSummary({
          'ok': true,
          'signers': [
            {
              'signatureValid': true,
              'certificateWithinValidity': true,
              'trustChainValidated': true,
              'trustChainStatus': 'trusted',
              'revocationStatus': 0,
              'chainRevocationStatus': 0,
            },
          ],
        }),
        contains('controlli correnti'),
      );
    },
  );
  testWidgets(
    'document can be prepared before a card; PIN step requires a reader',
    (t) async {
      final service = SigningFake();
      await start(t, service, detect: false);
      await signingDocument(t);
      expect(
        find.widgetWithText(TextField, 'PIN completo · 8 cifre'),
        findsOneWidget,
      );
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Firma'))
            .onPressed,
        isNull,
      );
      expect(service.detectCalls, 0);
      expect(service.signCalls, 0);
    },
  );
  testWidgets(
    'save cancellation wipes PIN and sends no private operation',
    (t) async {
      final service = SigningFake();
      var dialogs = 0;
      await start(
        t,
        service,
        picker: (_) async {
          dialogs++;
          return null;
        },
      );
      await signingDocument(t);
      expect(dialogs, 0);
      await t.enterText(find.byType(TextField), '12345678');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(dialogs, 1);
      expect(service.signCalls, 0);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
  testWidgets(
    'confirmed save can replace the original using its immutable private snapshot',
    (t) async {
      final folder = Directory.systemTemp.createTempSync('cie-refuse-output-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final original = File('${folder.path}/original.pdf')
        ..writeAsStringSync('synthetic');
      final service = SigningFake();
      await start(t, service, picker: (_) async => original.path);
      await signingDocument(t, path: original.path);
      await t.enterText(find.byType(TextField), '12345678');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(service.receivedReplacement, isTrue);
      expect(service.source, isNot(original.path));
      expect(service.bytes, 'synthetic');
      expect(find.text('File firmato con successo'), findsOneWidget);
      expect(
        t.widget<Icon>(find.byIcon(Icons.check_circle_outline)).color,
        Colors.green,
      );
    },
  );
  testWidgets(
    'existing output remains intact on failed signing, with red outcome',
    (t) async {
      final folder = Directory.systemTemp.createTempSync('cie-keep-output-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final output = File('${folder.path}/firmato.pdf')
        ..writeAsStringSync('previous signed bytes');
      final service = SigningFake()..success = false;
      await start(t, service, picker: (_) async => output.path);
      await signingDocument(t);
      await t.enterText(find.byType(TextField), '12345678');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(service.receivedReplacement, isTrue);
      expect(output.readAsStringSync(), 'previous signed bytes');
      expect(
        t.widget<Icon>(find.byIcon(Icons.cancel_outlined)).color,
        Colors.red,
      );
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('a selected directory is rejected before any signing attempt', (
    t,
  ) async {
    final folder = Directory.systemTemp.createTempSync('cie-output-directory-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final service = SigningFake();
    await start(t, service, picker: (_) async => folder.path);
    await signingDocument(t);
    await t.enterText(find.byType(TextField), '12345678');
    await pressSign(t);
    await t.pumpAndSettle();
    expect(service.signCalls, 0);
    expect(find.textContaining('non una cartella'), findsOneWidget);
  });
  testWidgets(
    'save confirms one immutable operation and result has optional verification',
    (t) async {
      final folder = Directory.systemTemp.createTempSync(
        'cie-frozen-operation-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final original = File('${folder.path}/original.pdf')
        ..writeAsStringSync('selected bytes');
      final save = Completer<String?>();
      final service = SigningFake();
      SignedFileRequest? request;
      await start(
        t,
        service,
        picker: (r) {
          request = r;
          return save.future;
        },
      );
      await signingDocument(t, path: original.path);
      await t.enterText(find.byType(TextField), '12345678');
      final controller = t
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await pressSign(t);
      expect(controller.text, isEmpty);
      expect(service.signCalls, 0);
      expect(find.byType(TextField), findsNothing);
      final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.onDestinationSelected, isNull);
      expect(request!.extension, 'pdf');
      expect(request!.suggestedName, 'original-firmato');
      original.writeAsStringSync('modified after selection');
      await t.runAsync(() async {
        save.complete(output());
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await t.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(service.bytes, 'selected bytes');
      expect(service.receivedPin, '12345678');
      expect(find.text('File firmato con successo'), findsOneWidget);
      expect(find.textContaining('Verifica non conclusa'), findsOneWidget);
      expect(find.text('Dettagli della verifica'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.runAsync(() async {
        await t.tap(find.text('Concludi'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await t.pumpAndSettle();
      expect(find.text('Seleziona un documento'), findsOneWidget);
      expect(File(service.source!).existsSync(), isFalse);
      expect(original.readAsStringSync(), 'modified after selection');
    },
  );
  testWidgets('unsupported PDF disables PAdES and offers CAdES without a PIN', (
    t,
  ) async {
    final service = SigningFake()..supportedPdf = false;
    await start(t, service, detect: false);
    await signingDocument(t, toPin: false);
    final pades = t.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Firma PAdES · PDF'),
    );
    expect(pades.enabled, isFalse);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('Prosegui'));
    await t.pumpAndSettle();
    expect(find.text('Firma CAdES · P7M'), findsOneWidget);
    expect(service.signCalls, 0);
  });
  testWidgets('invalid P7M never exposes co-sign or PIN', (t) async {
    final folder = Directory.systemTemp.createTempSync('cie-invalid-cms-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final input = File('${folder.path}/broken.p7m')
      ..writeAsStringSync('bad CMS');
    final service = SigningFake()..supportedPdf = false;
    await start(t, service, detect: false);
    await signingDocument(t, path: input.path, toPin: false);
    expect(find.textContaining('non è idoneo'), findsOneWidget);
    expect(find.text('Aggiungi una firma'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(service.signCalls, 0);
  });
  testWidgets(
    'paired choice is independent of the physical card and cannot sign another CIE',
    (t) async {
      final service = PairedFake()..cards.add('ANOTHER-CARD');
      await start(t, service);
      await signingDocument(t, pairedCard: 'ANOTHER-CARD');
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, 4);
      expect(field.enabled, isFalse);
      expect(service.signCalls, 0);
    },
  );
  testWidgets(
    'failed partial PIN never retries; full PIN is a separate explicit action',
    (t) async {
      final service = PairedFake()..cards.add('TEST-CARD');
      await start(t, service, picker: (_) async => output());
      await signingDocument(t, pairedCard: 'TEST-CARD');
      await t.enterText(find.byType(TextField), '1234');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).maxLength, 4);
      await t.ensureVisible(find.text('Usa PIN completo'));
      await t.tap(find.text('Usa PIN completo'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).maxLength, 8);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(service.signCalls, 1);
      await t.enterText(find.byType(TextField), '12345678');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(service.signCalls, 2);
    },
  );
  testWidgets(
    'eligible P7M follows contextual co-sign path and correct save extension',
    (t) async {
      final folder = Directory.systemTemp.createTempSync('cie-cosign-flow-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final document = File('${folder.path}/document.pdf.p7m')
        ..writeAsStringSync('synthetic CMS');
      final service = SigningFake()
        ..validCms = true
        ..supportedPdf = false;
      SignedFileRequest? request;
      await start(
        t,
        service,
        picker: (r) async {
          request = r;
          return '${folder.path}/cofirmato.p7m';
        },
      );
      await signingDocument(t, path: document.path, toPin: false);
      expect(find.text('Firma CAdES · P7M'), findsNothing);
      await t.tap(find.widgetWithText(FilledButton, 'Aggiungi una firma'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '12345678');
      await pressSign(t);
      await t.pumpAndSettle();
      expect(service.signCalls, 1);
      expect(service.signedFormat, 'cosign');
      expect(request!.extension, 'p7m');
      expect(request!.suggestedName, 'document.pdf-cofirmato');
      expect(find.text('File firmato con successo'), findsOneWidget);
    },
  );
}
