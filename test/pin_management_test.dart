// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/pin_management.dart';

class PinService implements CieService {
  int calls = 0;
  bool? usedPuk;
  String expectedNewPin = '86420975';
  Completer<JsonResult>? pending;
  JsonResult response = {'ok': true, 'message': 'PIN aggiornato.'};
  @override
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  }) async {
    calls++;
    usedPuk = unblock;
    expect(reader, 'TEST READER');
    expect(card, 'TEST');
    expect(authentication, '10293847');
    expect(newPin, expectedNewPin);
    return pending == null ? response : pending!.future;
  }

  @override
  Future<JsonResult> load() async => {'ok': true};
  @override
  Future<JsonResult> detect() async => {'ok': true};
  @override
  Future<JsonResult> verify(String path) async => {'ok': true};
  @override
  Future<JsonResult> pdfInfo(String path, int page) async => {'ok': false};
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
  }) async => {'ok': false};
}

Future<void> mount(
  WidgetTester tester,
  PinService service,
  bool unblock, {
  bool available = true,
  Future<void> Function()? onPairingsChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PinManagementPage(
            service: service,
            unblock: unblock,
            busy: false,
            available: available,
            selected: {'name': 'TEST READER', 'cardId': 'TEST'},
            onRun: (_, action) => action(),
            onDetect: () async {},
            onPairingsChanged: onPairingsChanged,
          ),
        ),
      ),
    ),
  );
}

Future<void> fill(
  WidgetTester tester, {
  String confirmation = '86420975',
}) async {
  await tester.enterText(find.byType(TextField).at(0), '10293847');
  await tester.enterText(find.byType(TextField).at(1), '86420975');
  await tester.enterText(find.byType(TextField).at(2), confirmation);
}

Future<void> submit(WidgetTester tester, bool puk) async {
  final button = find.text(
    puk ? 'Sblocca e imposta il PIN' : 'Modifica il PIN',
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test('PIN input requires eight digits and matching confirmation, without complexity rules', () {
    for (final unblock in [false, true]) {
      for (final pin in [
        '00000000',
        '11111111',
        '12345678',
        '87654321',
        '12121212',
        '10293847',
      ]) {
        expect(pinInputError('10293847', pin, pin, unblock), isNull);
      }
      for (final pin in [
        'short',
        'abcdefgh',
        '1234567',
        '123456789',
        '1234x678',
      ]) {
        expect(pinInputError('10293847', pin, pin, unblock), isNotNull);
      }
      expect(
        pinInputError('10293847', '86420975', '86420974', unblock),
        isNotNull,
      );
      expect(pinInputError('bad', '86420975', '86420975', unblock), isNotNull);
    }
  });
  for (final unblock in [false, true]) {
    for (final newPin in ['11111111', '12345678', '87654321']) {
      testWidgets(
        'PIN/PUK $unblock forwards $newPin once after explicit confirmation',
        (tester) async {
          tester.view.physicalSize = const Size(1100, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = PinService()..expectedNewPin = newPin;
          await mount(tester, service, unblock);
          expect(find.textContaining('Il nuovo PIN deve avere'), findsNothing);
          expect(
            find.textContaining('La modifica riguarda il PIN fisico'),
            findsNothing,
          );
          expect(
            find.textContaining('Un errore nella rimozione'),
            findsNothing,
          );
          expect(
            find.textContaining('Confermando l’operazione'),
            findsOneWidget,
          );
          await tester.enterText(find.byType(TextField).at(0), '10293847');
          await tester.enterText(find.byType(TextField).at(1), newPin);
          await tester.enterText(find.byType(TextField).at(2), newPin);
          await submit(tester, unblock);
          expect(service.calls, 0);
          expect(
            find.textContaining(
              'La rimozione dall’archivio protetto verrà tentata',
            ),
            findsNothing,
          );
          await tester.tap(find.text('Conferma operazione'));
          await tester.pumpAndSettle();
          expect(service.calls, 1);
          expect(service.usedPuk, unblock);
          expect(find.text('Operazione completata'), findsOneWidget);
        },
      );
    }
  }
  for (final puk in [false, true]) {
    testWidgets(
      '${puk ? 'PUK' : 'PIN'} requires confirmation and clears secrets before one request',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = PinService()..pending = Completer<JsonResult>();
        await mount(tester, service, puk);
        await fill(tester);
        await submit(tester, puk);
        expect(service.calls, 0);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Conferma operazione'));
        await tester.pump();
        expect(service.calls, 1);
        expect(service.usedPuk, puk);
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          expect(field.controller!.text, isEmpty);
          expect(field.obscureText, isTrue);
          expect(field.enabled, isFalse);
        }
        service.pending!.complete({
          'ok': false,
          'code': puk ? 'puk_locked' : 'pin_incorrect',
          'message': 'Nessun nuovo tentativo automatico.',
          'attemptsRemaining': puk ? 0 : 2,
        });
        await tester.pumpAndSettle();
        expect(service.calls, 1);
        expect(find.text('Tentativi residui: ${puk ? 0 : 2}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'mismatch and cancellation never invoke backend; cancellation clears fields',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PinService();
      await mount(tester, service, false);
      await fill(tester, confirmation: '86420974');
      await submit(tester, false);
      expect(service.calls, 0);
      expect(
        find.text('Il nuovo PIN e la conferma non corrispondono.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await fill(tester);
      await submit(tester, false);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
    },
  );
  testWidgets('uncertain mutation stays indeterminate with no retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = PinService()
      ..response = {
        'ok': false,
        'code': 'pin_operation_indeterminate',
        'message': 'Il PIN potrebbe essere già cambiato.',
      };
    await mount(tester, service, true);
    await fill(tester);
    await submit(tester, true);
    await tester.tap(find.text('Conferma operazione'));
    await tester.pumpAndSettle();
    expect(find.text('Esito non determinabile'), findsOneWidget);
    expect(service.calls, 1);
    expect(find.text('Operazione completata'), findsNothing);
  });
  testWidgets(
    'cleanup warning preserves card success and refreshes pairings once',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PinService()
        ..response = {
          'ok': true,
          'message': 'PIN modificato. Abbina nuovamente la CIE dalla Home.',
          'pairingInvalidated': true,
          'cleanupWarning': 'Rimozione dal Portachiavi non completata. Abbinamento disabilitato.',
        };
      var refreshes = 0;
      await mount(
        tester,
        service,
        false,
        onPairingsChanged: () async {
          refreshes++;
        },
      );
      expect(find.textContaining('Un errore nella rimozione'), findsNothing);
      await fill(tester);
      await submit(tester, false);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Confermando l’operazione, disabiliti'),
        ),
        findsOneWidget,
      );
      expect(service.calls, 0);
      await tester.tap(find.text('Conferma operazione'));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(refreshes, 1);
      expect(find.text('Operazione completata'), findsOneWidget);
      expect(
        find.textContaining('Rimozione dal Portachiavi non completata'),
        findsOneWidget,
      );
      expect(find.text('Operazione non completata'), findsNothing);
    },
  );
  testWidgets(
    'legacy raw Keychain error is understandable and is never retried',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PinService()
        ..response = {'ok': false, 'message': 'pairing_store_unavailable'};
      await mount(tester, service, false);
      await fill(tester);
      await submit(tester, false);
      await tester.tap(find.text('Conferma operazione'));
      await tester.pumpAndSettle();
      expect(find.text('pairing_store_unavailable'), findsNothing);
      expect(find.textContaining('prima di inviare il PIN'), findsOneWidget);
      expect(service.calls, 1);
    },
  );
}
