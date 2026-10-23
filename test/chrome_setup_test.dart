// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/chrome_setup.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/main.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

class FakeChromeSetup implements ChromeSetupService {
  int reads = 0, plans = 0, writes = 0;
  String state = 'needs_setup';
  String? fingerprint;
  JsonResult? applyResult;
  Completer<JsonResult>? pending;
  @override
  Future<JsonResult> inspect() async {
    reads++;
    return {'ok': true, 'detected': state != 'not_installed', 'state': state};
  }

  @override
  Future<JsonResult> plan() async {
    plans++;
    return {
      'ok': true,
      'fingerprint': 'reviewed-$plans',
      'alreadyConfigured': state == 'configured',
    };
  }

  @override
  Future<JsonResult> apply(String value) async {
    writes++;
    fingerprint = value;
    final result = pending == null
        ? (applyResult ?? {'ok': true})
        : await pending!.future;
    if (result['ok'] == true) state = 'configured';
    return result;
  }
}

Widget screen(
  FakeChromeSetup service, {
  bool home = false,
  bool busy = false,
  String language = 'it',
  double scale = 1,
  ValueChanged<bool>? onBusy,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: CieLocalizations.supportedLocales,
  localizationsDelegates: [
    CieLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: home
          ? ChromeSetupHomeCard(
              service: service,
              busy: busy,
              onBusy: onBusy ?? (_) {},
            )
          : ChromeSetupCard(
              service: service,
              busy: busy,
              onBusy: onBusy ?? (_) {},
            ),
    ),
  ),
);

Future<void> open(
  WidgetTester tester, {
  String label = 'Configura Chrome',
}) async {
  await tester.tap(find.widgetWithText(OutlinedButton, label));
  await tester.pumpAndSettle();
}

Future<void> prepare(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continua'));
  await tester.tap(find.text('Continua'));
  await tester.pumpAndSettle();
}

Future<void> ask(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Configura Chrome');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test('Home only requests setup when Chrome needs attention', () {
    expect(
      chromeSetupNeeded({
        'ok': true,
        'detected': false,
        'state': 'not_installed',
      }),
      false,
    );
    expect(
      chromeSetupNeeded({'ok': true, 'detected': true, 'state': 'configured'}),
      false,
    );
    expect(
      chromeSetupNeeded({'ok': true, 'detected': true, 'state': 'needs_setup'}),
      true,
    );
    expect(
      chromeSetupNeeded({
        'ok': true,
        'detected': true,
        'state': 'database_uninitialized',
      }),
      true,
    );
    expect(chromeSetupNeeded({'ok': false}), true);
  });

  testWidgets('opening and planning never apply configuration', (tester) async {
    final service = FakeChromeSetup();
    final busy = <bool>[];
    await tester.pumpWidget(screen(service, onBusy: busy.add));
    await open(tester);
    expect(service.reads, 1);
    expect(service.plans, 0);
    expect(service.writes, 0);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Rileggi'), findsNothing);
    await prepare(tester);
    expect(service.plans, 1);
    expect(service.writes, 0);
    expect(find.text('Rileggi'), findsNothing);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(busy, [true, false]);
    expect(service.writes, 0);
  });

  testWidgets('cancelling confirmation writes nothing', (tester) async {
    final service = FakeChromeSetup();
    await tester.pumpWidget(screen(service));
    await open(tester);
    await prepare(tester);
    await ask(tester);
    expect(
      find.text(
        'Vuoi configurare Chrome per usare la CIE? Firefox resterà invariato.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(service.writes, 0);
  });

  testWidgets(
    'one confirmed write uses reviewed fingerprint and full PIN guidance',
    (tester) async {
      final service = FakeChromeSetup();
      await tester.pumpWidget(screen(service));
      await open(tester);
      await prepare(tester);
      await ask(tester);
      await tester.tap(find.text('Configura'));
      await tester.pumpAndSettle();
      expect(service.writes, 1);
      expect(service.fingerprint, 'reviewed-1');
      expect(
        find.text(
          'Chrome è configurato. Riaprilo e usa il PIN completo di otto cifre.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('pending write blocks duplicate submissions and closing', (
    tester,
  ) async {
    final service = FakeChromeSetup()..pending = Completer<JsonResult>();
    await tester.pumpWidget(screen(service));
    await open(tester);
    await prepare(tester);
    await ask(tester);
    await tester.tap(find.text('Configura'));
    await tester.pump();
    final close = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Chiudi'),
    );
    expect(close.onPressed, isNull);
    expect(service.writes, 1);
    service.pending!.complete({'ok': true});
    await tester.pumpAndSettle();
    expect(service.writes, 1);
  });

  testWidgets('changed plan does not trigger retries or preserve stale plan', (
    tester,
  ) async {
    final service = FakeChromeSetup()
      ..applyResult = {'ok': false, 'code': 'plan_changed'};
    await tester.pumpWidget(screen(service));
    await open(tester);
    await prepare(tester);
    await ask(tester);
    await tester.tap(find.text('Configura'));
    await tester.pumpAndSettle();
    expect(find.text(chromeSetupError('plan_changed')), findsOneWidget);
    expect(find.text('Rileggi'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Configura Chrome'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(service.writes, 1);
    await prepare(tester);
    expect(service.plans, 2);
    expect(service.writes, 1);
  });

  testWidgets(
    'missing database requests first Chrome launch without creating it',
    (tester) async {
      final service = FakeChromeSetup()..state = 'database_uninitialized';
      await tester.pumpWidget(screen(service));
      await open(tester);
      expect(
        find.text('Apri e chiudi Chrome, poi premi «Rileggi».'),
        findsOneWidget,
      );
      expect(find.text('Continua'), findsNothing);
      expect(find.text('Rileggi'), findsOneWidget);
      expect(service.plans, 0);
      expect(service.writes, 0);
    },
  );

  testWidgets('already configured Chrome offers no write action', (
    tester,
  ) async {
    final service = FakeChromeSetup()..state = 'configured';
    await tester.pumpWidget(screen(service));
    await open(tester);
    expect(find.text('Chrome è già configurato.'), findsOneWidget);
    expect(find.text('Continua'), findsNothing);
    expect(service.writes, 0);
  });

  testWidgets('Home refreshes read-only when application resumes', (
    tester,
  ) async {
    final service = FakeChromeSetup()..state = 'configured';
    await tester.pumpWidget(screen(service, home: true));
    await tester.pumpAndSettle();
    expect(find.text('Configura Chrome'), findsNothing);
    service.state = 'needs_setup';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Configura Chrome'), findsOneWidget);
    expect(service.writes, 0);
  });

  testWidgets('busy Home does not inspect or start setup', (tester) async {
    final service = FakeChromeSetup();
    await tester.pumpWidget(screen(service, home: true, busy: true));
    await tester.pumpAndSettle();
    expect(service.reads, 0);
    expect(service.writes, 0);
  });

  testWidgets('English text is localized', (tester) async {
    final service = FakeChromeSetup();
    await tester.pumpWidget(screen(service, language: 'en'));
    await open(tester, label: 'Configure Chrome');
    expect(
      find.text(
        'Close Chrome, including background processes. No PIN is needed.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(service.writes, 0);
  });

  testWidgets('small window and 200 percent text retain reachable actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeChromeSetup();
    await tester.pumpWidget(screen(service, scale: 2));
    await open(tester);
    await prepare(tester);
    await ask(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.writes, 0);
  });

  testWidgets('Home places Chrome setup first and Settings keeps the entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeChromeSetup();
    final system = PublicSystem();
    await tester.pumpWidget(
      CiePrototype(
        service: UnifiedFake(),
        webPublisher: system.publish,
        webStatusReader: system.status,
        chromeSetupService: service,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Google Chrome')).dy,
      lessThan(tester.getTopLeft(find.text('Abbina la tua CIE')).dy),
    );
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Chrome'), findsOneWidget);
    service.state = 'configured';
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Chrome'), findsNothing);
    expect(service.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
