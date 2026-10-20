// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:cie_flutter_prototype/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeService;

void main() {
  const channel = MethodChannel('cie.id/linux_text_scaling');
  for (final viewport in [
    (const Size(1024, 576), 1.0, 1.0),
    (const Size(960, 540), 1.25, 1.0),
    (const Size(800, 480), 1.5, 1.0),
    (const Size(640, 400), 1.0, 1.0),
    (const Size(1920, 1080), 1.5, 2.0),
    (const Size(800, 600), 2.0, 1.0),
  ]) {
    testWidgets(
      'Desktop layout fits logical workarea $viewport',
      (t) async {
        t.view.physicalSize = viewport.$1;
        t.view.devicePixelRatio = viewport.$3;
        t.platformDispatcher.textScaleFactorTestValue =
            defaultTargetPlatform == TargetPlatform.linux ? 1.0 : viewport.$2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => viewport.$2,
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final service = FakeService();
        await t.pumpWidget(CiePrototype(service: service));
        await t.pumpAndSettle();
        final context = t.element(find.byKey(const ValueKey('page-title')));
        expect(MediaQuery.textScalerOf(context).scale(16), 16 * viewport.$2);
        expect(MediaQuery.sizeOf(context), viewport.$1 / viewport.$3);
        expect(t.takeException(), isNull);
        for (final icon in [
          Icons.draw_outlined,
          Icons.fact_check_outlined,
          Icons.password_outlined,
          Icons.lock_open_outlined,
          Icons.menu_book_outlined,
          Icons.support_agent_outlined,
          Icons.info_outline,
          Icons.settings_outlined,
        ]) {
          await t.ensureVisible(find.byIcon(icon));
          await t.tap(find.byIcon(icon));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'Page $icon at $viewport');
        }
        final dialogContext = t.element(
          find.byKey(const ValueKey('page-title')),
        );
        unawaited(
          showDialog<void>(
            context: dialogContext,
            builder: (_) => AlertDialog(
              scrollable: true,
              title: const Text('Messaggio di prova software'),
              content: const Text(
                'Contenuto lungo per verificare lo scorrimento '
                'e la disponibilità dei pulsanti nelle finestre piccole. '
                'Nessuna operazione sulla carta.',
              ),
              actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.widgetWithText(TextButton, 'OK').hitTestable(),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        expect(service.signCalls, 0);
        await t.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  }
}
