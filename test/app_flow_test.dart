// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_flow.dart';
import 'package:cie_flutter_prototype/main.dart';

import 'widget_test.dart' show FakeService;
import 'signing_helpers.dart';

void main() {
  test('navigation history ignores duplicate selections and cannot leave an operation', () {
    final flow = AppFlowController();
    expect(flow.destination, AppDestination.home);
    expect(flow.navigate(AppDestination.sign), isTrue);
    expect(flow.navigate(AppDestination.sign), isFalse);
    expect(flow.navigate(AppDestination.information), isTrue);
    flow.busy = true;
    expect(flow.back(), isFalse);
    expect(flow.navigate(AppDestination.home), isFalse);
    flow.busy = false;
    expect(flow.back(), isTrue);
    expect(flow.destination, AppDestination.sign);
    expect(flow.back(), isTrue);
    expect(flow.destination, AppDestination.home);
    expect(flow.back(), isFalse);
    flow.dispose();
  });
  test(
    'new document and card discard results belonging to previous inputs',
    () {
      final sign = SignFlowState();
      sign.selectDocument('one.pdf', 'pdf', 'one-signed.pdf');
      sign.result = {'ok': true};
      sign.changeCard();
      expect(sign.result, isNull);
      expect(sign.input, 'one.pdf');
      sign.selectDocument('two.p7m', 'cosign', '');
      expect(sign.output, isEmpty);
      expect(sign.format, 'cosign');
      sign.conclude();
      expect(sign.input, isEmpty);
    },
  );
  testWidgets(
    'familiar navigation and back clear PIN without a private operation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      for (final label in [
        'Home',
        'Firma Elettronica',
        'Verifica Firma',
        'Informazioni',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Middleware caricato'), findsNothing);
      await tester.tap(find.text('Firma Elettronica').first);
      await tester.pumpAndSettle();
      await signingDocument(tester);
      await tester.enterText(find.byType(TextField), '12345678');
      await tester.tap(find.text('Informazioni').first);
      await tester.pumpAndSettle();
      expect(find.text('Licenze e riconoscimenti'), findsOneWidget);
      expect(find.text('Indietro'), findsNothing);
      await tester.tap(find.text('Firma Elettronica').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(service.signCalls, 0);
      expect(service.detectCalls, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
