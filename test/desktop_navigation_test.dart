// SPDX-License-Identifier: BSD-3-Clause
import 'dart:ui' as ui;

import 'package:cie_flutter_prototype/app_flow.dart';
import 'package:cie_flutter_prototype/app_theme.dart';
import 'package:cie_flutter_prototype/desktop_navigation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const platforms = TargetPlatformVariant({
  TargetPlatform.linux,
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

final destinations = [
  for (final destination in AppDestination.values)
    DesktopNavigationDestination(
      icon: Icons.circle_outlined,
      label: destination.label,
    ),
];

Future<List<int>> rowBackgrounds(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('menu-paint')),
  );
  final (bytes, width) = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    image.dispose();
    return (bytes, width);
  }))!;
  final colors = <int>[];
  for (final element in find.byType(ListTile).evaluate()) {
    final box = element.renderObject! as RenderBox;
    // Sample the empty space at the right of the row, beyond icon and label.
    final point = boundary.globalToLocal(
      box.localToGlobal(Offset(box.size.width - 10, box.size.height / 2)),
    );
    colors.add(
      bytes.getUint32((point.dy.floor() * width + point.dx.floor()) * 4),
    );
  }
  return colors;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final extended in [true, false]) {
      testWidgets(
        'Every $brightness menu row hovers independently, extended=$extended',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(400, 760);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final selections = <int>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: cieTheme(brightness),
              home: Scaffold(
                body: Row(
                  children: [
                    RepaintBoundary(
                      key: const ValueKey('menu-paint'),
                      child: DesktopNavigation(
                        extended: extended,
                        selectedIndex: 0,
                        onDestinationSelected: selections.add,
                        leading: const SizedBox(height: 32),
                        destinations: destinations,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final original = await rowBackgrounds(tester);
          expect(original[0], isNot(original[1]));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            pointer: 1,
          );
          await mouse.addPointer(location: const Offset(350, 750));
          addTearDown(mouse.removePointer);
          for (var index = 0; index < destinations.length; index++) {
            final rect = tester.getRect(find.byType(ListTile).at(index));
            await mouse.moveTo(Offset(rect.right - 10, rect.center.dy));
            await tester.pumpAndSettle();
            expect(
              RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
              SystemMouseCursors.click,
            );
            final hovered = await rowBackgrounds(tester);
            for (var other = 0; other < destinations.length; other++) {
              expect(
                hovered[other],
                other == index ? isNot(original[other]) : original[other],
                reason: 'hovering row $index must only highlight that row',
              );
            }
            expect(selections, isEmpty);
          }
          await mouse.moveTo(const Offset(350, 750));
          await tester.pumpAndSettle();
          expect(await rowBackgrounds(tester), original);
          expect(tester.takeException(), isNull);
        },
        variant: platforms,
      );
    }
  }

  testWidgets(
    'Menu supports keyboard selection and disables interaction while busy',
    (tester) async {
      final selections = <int>[];
      Future<void> showMenu({required bool enabled}) => tester.pumpWidget(
        MaterialApp(
          theme: cieTheme(Brightness.light),
          home: Scaffold(
            body: DesktopNavigation(
              extended: true,
              selectedIndex: 0,
              onDestinationSelected: enabled ? selections.add : null,
              leading: const SizedBox.shrink(),
              destinations: destinations,
            ),
          ),
        ),
      );
      await showMenu(enabled: true);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selections, [0]);
      await tester.tap(find.text('Guida'));
      await tester.pumpAndSettle();
      expect(selections, [0, AppDestination.guide.index]);
      await showMenu(enabled: false);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: tester.getCenter(find.text('Guida')));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await tester.tap(find.text('Guida'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selections, [0, AppDestination.guide.index]);
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );
}
