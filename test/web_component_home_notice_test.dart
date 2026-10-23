// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/web_component_setup.dart';
import 'package:cie_flutter_prototype/windows_web_setup.dart';

import 'home_enrollment_test.dart' show UnifiedFake;
import 'web_completion_feedback_test.dart' show size;

const noticeKey = ValueKey('web-component-setup-home');
const windowsMissing = <String, dynamic>{
  'available': false,
  'componentNeedsUpdate': true,
  'componentInstallerRequired': true,
  'componentStatusMessage': windowsComponentUpdateMessage,
};
const macDisabled = <String, dynamic>{
  'available': false,
  'canActivateComponent': true,
  'canOpenSystemSettings': true,
};

void main() {
  test(
    'only explicit platform intervention flags cause a component notice',
    () {
      for (final status in <JsonResult>[
        {},
        {'available': false},
        {'available': true},
        {'available': true, 'observedCards': []},
        {'available': false, 'browserRegistrationRequired': true},
        {
          'available': true,
          'componentNeedsUpdate': true,
          'canActivateComponent': true,
          'componentInstallerRequired': true,
        },
      ]) {
        expect(WebComponentSetupNotice.fromStatus(status), isNull);
      }
      expect(
        WebComponentSetupNotice.fromStatus(windowsMissing)!.action,
        WebComponentAction.installer,
      );
      expect(
        WebComponentSetupNotice.fromStatus(macDisabled)!.action,
        WebComponentAction.activate,
      );
      expect(
        WebComponentSetupNotice.fromStatus({
          ...macDisabled,
          'canActivateComponent': false,
        })!.action,
        WebComponentAction.systemSettings,
      );
      final newer = WebComponentSetupNotice.fromStatus({
        ...macDisabled,
        'componentNeedsUpdate': true,
        'componentHostOutdated': true,
      })!;
      expect(newer.action, WebComponentAction.appUpdate);
      expect(newer.update, isFalse);
      expect(newer.message, contains('versione più recente'));
    },
  );

  for (final status in [windowsMissing, macDisabled]) {
    for (final count in [0, 2]) {
      testWidgets(
        'one top notice for ${status.keys}, $count pairings; resume hides it',
        (t) async {
          size(t);
          final service = UnifiedFake();
          for (var i = 0; i < count; i++) {
            service.records['TEST$i'] = {
              'card': 'TEST$i',
              'readyForSigning': true,
              'publicDataSaved': true,
              'webProvisioned': true,
            };
          }
          var current = false, activations = 0, publications = 0, checks = 0;
          await t.pumpWidget(
            CiePrototype(
              service: service,
              settings: MemorySettingsStore(),
              webStatusReader: () async =>
                  current ? {'available': true} : status,
              webPublisher: (_, _) async {
                publications++;
              },
              webComponentActivator: () async {
                activations++;
                return {'ok': true};
              },
              windowsWebComponentChecker: (_) async {
                checks++;
                return {'ok': true};
              },
            ),
          );
          await t.pumpAndSettle();
          expect(find.byKey(noticeKey), findsOneWidget);
          final heading = find.text(
            count == 0 ? 'Abbina la tua CIE' : 'Le tue CIE',
          );
          expect(
            t.getTopLeft(find.byKey(noticeKey)).dy,
            lessThan(t.getTopLeft(heading).dy),
          );
          final label = status == windowsMissing
              ? 'Aggiorna accesso ai siti'
              : 'Attiva accesso ai siti';
          expect(find.text(label), findsOneWidget);
          expect(activations, 0);
          expect(checks, 0);
          expect(publications, 0);
          expect(service.enrollCalls, 0);
          expect(service.signCalls, 0);
          expect(service.completeCalls, 0);
          expect(find.byType(TextField), findsNothing);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          current = true;
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpAndSettle();
          expect(find.byKey(noticeKey), findsNothing);
          expect(find.text(label), findsNothing);
          expect(activations, 0);
          expect(publications, 0);
          expect(service.completeCalls, 0);
          expect(service.records.length, count);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('unreadable pairing storage does not hide a system problem', (
    t,
  ) async {
    size(t);
    final service = UnifiedFake()..locked = true;
    await t.pumpWidget(
      CiePrototype(
        service: service,
        webStatusReader: () async => windowsMissing,
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(noticeKey), findsOneWidget);
    expect(
      find.textContaining('Archivio protetto non leggibile.'),
      findsOneWidget,
    );
    expect(service.enrollCalls, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'activation without a pairing requires confirmation and verifies status',
    (t) async {
      size(t);
      final service = UnifiedFake();
      var current = false, activations = 0, publications = 0;
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webStatusReader: () async =>
              current ? {'available': true} : macDisabled,
          webPublisher: (_, _) async {
            publications++;
          },
          webComponentActivator: () async {
            activations++;
            current = true;
            return {'ok': true};
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Attiva accesso ai siti'));
      await t.pumpAndSettle();
      expect(activations, 0);
      await t.tap(find.text('Annulla'));
      await t.pumpAndSettle();
      expect(activations, 0);
      await t.tap(find.text('Attiva accesso ai siti'));
      await t.pumpAndSettle();
      await t.tap(find.text('Attiva'));
      await t.pumpAndSettle();
      expect(activations, 1);
      expect(find.byKey(noticeKey), findsNothing);
      expect(find.text('Componente Firma con CIE attivato.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      expect(service.signCalls, 0);
      expect(publications, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'successful activation reply alone cannot hide the notice or trigger retries',
    (t) async {
      size(t);
      var activations = 0;
      final service = UnifiedFake();
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webStatusReader: () async => macDisabled,
          webComponentActivator: () async {
            activations++;
            return {'ok': true};
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Attiva accesso ai siti'));
      await t.pumpAndSettle();
      await t.tap(find.text('Attiva'));
      await t.pumpAndSettle();
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(
        find.textContaining('Attivazione non completata.'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 10));
      expect(activations, 1);
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'newer component offers information without downgrade or activation',
    (t) async {
      size(t);
      var activations = 0;
      await t.pumpWidget(
        CiePrototype(
          service: UnifiedFake(),
          webStatusReader: () async => {
            ...macDisabled,
            'componentHostOutdated': true,
            'componentNeedsUpdate': true,
          },
          webComponentActivator: () async {
            activations++;
            return {'ok': true};
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Attiva accesso ai siti'), findsNothing);
      expect(find.text('Aggiorna accesso ai siti'), findsNothing);
      await t.tap(find.text('Informazioni accesso ai siti'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(activations, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('notice actions are localized and reachable with large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      CiePrototype(
        service: UnifiedFake(),
        settings: MemorySettingsStore()
          ..value = const AppSettings(languageCode: 'en'),
        webStatusReader: () async => windowsMissing,
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(noticeKey), findsOneWidget);
    final button = find.text('Update website access');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
