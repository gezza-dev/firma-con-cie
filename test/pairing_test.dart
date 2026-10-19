// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/network_settings.dart';

import 'widget_test.dart' show FakeService;
import 'signing_helpers.dart';

class PairedFake extends FakeService implements PairingService {
  final cards = <String>[];
  int pairCalls = 0, removeCalls = 0;
  String? received;
  bool storeLocked = false;
  @override
  Future<JsonResult> load() async => {
    'ok': true,
    'canSign': true,
    'canPair': true,
  };
  @override
  Future<JsonResult> pairings() async => storeLocked
      ? {'ok': false, 'code': 'pairing_store_unavailable'}
      : {'ok': true, 'cards': List.of(cards)};
  @override
  Future<JsonResult> pair(String reader, String card, String fullPin) async {
    pairCalls++;
    received = fullPin;
    cards.add(card);
    return {'ok': true};
  }

  @override
  Future<JsonResult> unpair(String card) async {
    removeCalls++;
    if (card.isEmpty) {
      cards.clear();
    } else {
      cards.remove(card);
    }
    return {'ok': true};
  }
}

void main() {
  Future<void> start(WidgetTester t, PairedFake service) async {
    t.view.physicalSize = const Size(1400, 1300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(CiePrototype(service: service));
    await t.pumpAndSettle();
  }

  testWidgets(
    'pairing requires explicit complete PIN and one action; cancellation sends nothing',
    (t) async {
      final service = PairedFake();
      await start(t, service);
      expect(service.detectCalls, 0);
      expect(service.pairCalls, 0);
      await t.tap(find.text('Rileva carta'));
      await t.pumpAndSettle();
      await t.tap(find.text('Abbina CIE'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annulla'));
      await t.pumpAndSettle();
      expect(service.pairCalls, 0);
      await t.tap(find.text('Abbina CIE'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '1234');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(
        find.text('Inserisci tutte le otto cifre del PIN.'),
        findsOneWidget,
      );
      expect(service.pairCalls, 0);
      await t.enterText(find.byType(TextField), '12345678');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(service.pairCalls, 1);
      expect(service.received, '12345678');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Disabbina'), findsOneWidget);
      await t.tap(find.text('Disabbina'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annulla'));
      await t.pumpAndSettle();
      expect(service.removeCalls, 0);
      await t.tap(find.text('Disabbina'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rimuovi'));
      await t.pumpAndSettle();
      expect(service.removeCalls, 1);
      expect(service.cards, isEmpty);
    },
  );
  testWidgets(
    'paired choice automatically uses four digits and back clears the field',
    (t) async {
      final service = PairedFake()..cards.add('TEST-CARD');
      await start(t, service);
      await t.tap(find.text('Rileva carta'));
      await t.pumpAndSettle();
      await signingDocument(t, pairedCard: 'TEST-CARD');
      expect(find.byType(SwitchListTile), findsNothing);
      final partial = find.widgetWithText(TextField, 'Ultime 4 cifre del PIN');
      expect(partial, findsOneWidget);
      await t.enterText(partial, '5678');
      await t.tap(find.text('Indietro'));
      await t.pumpAndSettle();
      await t.tap(find.text('Prosegui'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(partial).controller!.text, isEmpty);
      expect(service.signCalls, 0);
    },
  );
  testWidgets(
    'locked archive offers no partial PIN and sends no authentication',
    (t) async {
      final service = PairedFake()..storeLocked = true;
      await start(t, service);
      expect(service.pairCalls, 0);
      expect(service.detectCalls, 0);
      expect(
        find.textContaining('Archivio protetto non leggibile'),
        findsOneWidget,
      );
      await t.tap(find.text('Rileva carta'));
      await t.pumpAndSettle();
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      expect(find.text('Usa le ultime quattro cifre del PIN'), findsNothing);
    },
  );
  test('pairing diagnostic events omit card identifiers and secrets', () {
    final r = DiagnosticRecorder()..level = AppDiagnosticLevel.operations;
    r.record('pair', {
      'ok': true,
      'card': 'TEST',
      'pin': '12345678',
      'prefix': '1234',
    }, 1);
    r.record('pairings', {
      'ok': true,
      'cards': ['TEST'],
    }, 1);
    expect(r.events.length, 2);
    expect(r.events.toString(), isNot(contains('TEST')));
    expect(r.events.toString(), isNot(contains('1234')));
  });
}
