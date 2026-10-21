// SPDX-License-Identifier: BSD-3-Clause
import 'package:cie_flutter_prototype/document_drop_zone.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/signature_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeService;

void main() {
  testWidgets('Document pages shrink and grow with the same window', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 600);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = FakeService();
    await t.pumpWidget(CiePrototype(service: service));
    await t.pumpAndSettle();
    final home = t.state(find.byType(PrototypeHome));
    await t.tap(find.byIcon(Icons.fact_check_outlined));
    await t.pumpAndSettle();
    for (final size in [
      const Size(800, 600),
      const Size(1600, 1000),
      const Size(640, 400),
      const Size(1280, 720),
      const Size(1920, 1200),
    ]) {
      t.view.physicalSize = size;
      await t.pumpAndSettle();
      final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, size.width > 930);
      final available =
          size.width - t.getSize(find.byType(NavigationRail)).width - 1 - 56;
      expect(
        t.getSize(find.byType(DocumentDropZone)).width,
        closeTo(available, .1),
      );
      expect(
        t.getRect(find.byType(DocumentDropZone)).right,
        closeTo(size.width - 28, .1),
      );
      expect(identical(home, t.state(find.byType(PrototypeHome))), isTrue);
      expect(t.takeException(), isNull);
    }
    expect(service.signCalls, 0);
  });

  testWidgets('Document loading area uses additional vertical space', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = FakeService();
    await t.pumpWidget(CiePrototype(service: service));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.fact_check_outlined));
    await t.pumpAndSettle();
    final before = t.getSize(find.byType(DocumentDropZone)).height;
    t.view.physicalSize = const Size(1280, 1100);
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(DocumentDropZone)).height,
      greaterThan(before + 150),
    );
    t.view.physicalSize = const Size(1280, 720);
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(DocumentDropZone)).height,
      closeTo(before, .1),
    );
    expect(t.takeException(), isNull);
    expect(service.signCalls, 0);
  });

  testWidgets('Preview grows with the window and keeps its footer visible', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 600);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureAppearanceDialog(
            content: const SizedBox(
              key: ValueKey('synthetic-preview'),
              width: double.infinity,
              height: 1600,
            ),
            actions: Wrap(
              children: [
                TextButton(onPressed: () {}, child: const Text('Annulla')),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Conferma anteprima'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final initialWidth = t
        .getSize(find.byKey(const ValueKey('synthetic-preview')))
        .width;
    t.view.physicalSize = const Size(1600, 1100);
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byKey(const ValueKey('synthetic-preview'))).width,
      greaterThan(initialWidth + 500),
    );
    final confirm = find.widgetWithText(FilledButton, 'Conferma anteprima');
    final initialFooter = t.getRect(confirm);
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -700));
    await t.pumpAndSettle();
    expect(t.getRect(confirm), initialFooter);
    for (final size in [const Size(640, 400), const Size(1280, 720)]) {
      t.view.physicalSize = size;
      await t.pumpAndSettle();
      expect(confirm.hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Annulla').hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    }
  });
}
