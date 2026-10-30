// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/browser_setup.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

class PinObservationService extends UnifiedFake {
  int pinCalls = 0;
  @override
  Future<JsonResult> load() async => {
    ...await super.load(),
    'canChangePin': true,
    'canUnblockPin': true,
  };
  @override
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  }) async {
    pinCalls++;
    expect(card, 'TEST');
    expect(authentication, '10293847');
    expect(newPin, '86420975');
    return {'ok': false, 'message': 'Synthetic test only'};
  }
}

void main() {
  for (final unblock in [false, true]) {
    Future<PinObservationService> start(
      WidgetTester t, {
      bool occupied = false,
      BrowserSetupCoordinator? browserSetup,
    }) async {
      t.view.physicalSize = const Size(1400, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = PinObservationService()..insert();
      (service.presence['readers'] as List).single['occupied'] = occupied;
      final system = PublicSystem();
      await t.pumpWidget(
        CiePrototype(
          service: service,
          browserSetup: browserSetup,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text(unblock ? 'Sblocca Carta' : 'Cambia PIN').first);
      await t.pumpAndSettle();
      return service;
    }

    testWidgets(
      'PIN/PUK $unblock retains input through idle refresh and occupied reader',
      (t) async {
        final service = await start(t);
        final fields = find.byType(TextField);
        final observations = service.observations;
        for (var i = 0; i < 3; i++) {
          await t.enterText(fields.at(i), i == 0 ? '10293847' : '86420975');
        }
        await t.tap(fields.first);
        for (var tick = 0; tick < 7; tick++) {
          await t.pump(const Duration(seconds: 1));
          await t.pumpAndSettle();
          expect(
            t.widget<TextField>(fields.first).controller!.text,
            '10293847',
          );
        }
        expect(service.observations, observations);
        final reader =
            (service.presence['readers'] as List).single as JsonResult;
        reader['occupied'] = true;
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        final widgets = t.widgetList<TextField>(fields).toList();
        expect(widgets[0].controller!.text, '10293847');
        expect(widgets[1].controller!.text, '86420975');
        expect(widgets[2].controller!.text, '86420975');
        expect(
          t
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(service.pinCalls, 0);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  unblock ? 'Sblocca e imposta il PIN' : 'Modifica il PIN',
                ),
              )
              .onPressed,
          isNotNull,
        );
        reader['occupied'] = false;
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(t.widget<TextField>(fields.first).controller!.text, '10293847');
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(
          t
              .widget<EditableText>(find.byType(EditableText).at(1))
              .focusNode
              .hasFocus,
          isTrue,
        );
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'PIN/PUK $unblock waits for an initially busy reader then protects entry',
      (t) async {
        final service = await start(t, occupied: true);
        final fields = find.byType(TextField);
        await t.enterText(fields.first, '10293847');
        final reads = service.observations;
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(service.observations, greaterThan(reads));
        (service.presence['readers'] as List).single['occupied'] = false;
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        final stopped = service.observations;
        await t.pump(const Duration(seconds: 4));
        await t.pumpAndSettle();
        expect(service.observations, stopped);
        expect(t.widget<TextField>(fields.first).controller!.text, '10293847');
        expect(t.widget<TextField>(fields.first).enabled, isTrue);
        expect(service.pinCalls, 0);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'PIN/PUK $unblock pauses browser inspection while typing and resumes on Home',
      (t) async {
        var inspections = 0;
        final coordinator = BrowserSetupCoordinator(
          platform: 'macos',
          inventory: () async {
            inspections++;
            return {'ok': true, 'installed': <String>[]};
          },
          systemReader: () async => {'available': true},
          log: (_, _, _) async {},
          interval: const Duration(seconds: 1),
        );
        final service = await start(t, browserSetup: coordinator);
        await t.enterText(find.byType(TextField).first, '10293847');
        final before = inspections;
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        expect(inspections, before);
        await t.tap(find.text('Home').first);
        await t.pumpAndSettle();
        expect(inspections, greaterThan(before));
        expect(service.pinCalls, 0);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'PIN/PUK $unblock TAB stays in the form and Shift TAB reverses',
      (t) async {
        final service = await start(t);
        final fields = find.byType(TextField);
        await t.tap(fields.first);
        await t.pump();
        for (var i = 1; i < 3; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(
            t
                .widget<EditableText>(find.byType(EditableText).at(i))
                .focusNode
                .hasFocus,
            isTrue,
          );
        }
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pump();
        expect(
          t
              .widget<EditableText>(find.byType(EditableText).at(1))
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(service.pinCalls, 0);
        await t.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );

    testWidgets(
      'PIN/PUK $unblock clears credentials on card removal and page change',
      (t) async {
        final service = await start(t);
        final fields = find.byType(TextField);
        service.presence = {'ok': true, 'readers': <JsonResult>[]};
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        for (final field in t.widgetList<TextField>(fields)) {
          expect(field.controller!.text, isEmpty);
          expect(field.enabled, isFalse);
        }
        service.insert('OTHER');
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        await t.enterText(fields.first, '10293847');
        await t.tap(find.text(unblock ? 'Cambia PIN' : 'Sblocca Carta').first);
        await t.pumpAndSettle();
        for (final field in t.widgetList<TextField>(fields)) {
          expect(field.controller!.text, isEmpty);
        }
        expect(service.pinCalls, 0);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'PIN/PUK $unblock pauses polling through confirmation and sends credentials only once',
      (t) async {
        final service = await start(t);
        final fields = find.byType(TextField);
        final observations = service.observations;
        for (var i = 0; i < 3; i++) {
          await t.enterText(fields.at(i), i == 0 ? '10293847' : '86420975');
        }
        final button = find.text(
          unblock ? 'Sblocca e imposta il PIN' : 'Modifica il PIN',
        );
        await t.ensureVisible(button);
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        service.presence = {'ok': true, 'readers': <JsonResult>[]};
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(service.observations, observations);
        expect(service.pinCalls, 0);
        service.insert();
        await t.tap(find.text('Conferma operazione'));
        await t.pumpAndSettle();
        expect(service.pinCalls, 1);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
