// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';
import 'package:cie_flutter_prototype/firefox_setup.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/main.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

class FakeFirefoxSetup implements FirefoxSetupService {
  int reads = 0, plans = 0, writes = 0, permissions = 0;
  String? appliedProfile, appliedFingerprint;
  JsonResult applyResult = {
    'ok': true,
    'configured': true,
    'snapPermission': 'disconnected',
    'browserLoginTested': false,
  };
  Completer<JsonResult>? pending;
  JsonResult? inspectResult;
  JsonResult? afterApplyInspection;
  @override
  Future<JsonResult> inspect() async {
    reads++;
    return inspectResult ??
        {
          'ok': true,
          'profiles': [
            {
              'id': 'desktop',
              'label': 'Work',
              'target': 'firefox',
              'state': 'needs_setup',
            },
            {
              'id': 'snap',
              'label': 'Personal',
              'target': 'snap',
              'state': 'needs_setup',
            },
          ],
          'snapPermission': 'disconnected',
        };
  }

  @override
  Future<JsonResult> plan(String profile) async {
    plans++;
    return {
      'ok': true,
      'id': profile,
      'fingerprint': 'reviewed-$profile',
      'label': profile == 'snap' ? 'Personal' : 'Work',
      'target': profile == 'snap' ? 'snap' : 'firefox',
    };
  }

  @override
  Future<JsonResult> apply(String profile, String fingerprint) async {
    writes++;
    appliedProfile = profile;
    appliedFingerprint = fingerprint;
    if (afterApplyInspection != null) inspectResult = afterApplyInspection;
    return pending == null ? applyResult : await pending!.future;
  }

  @override
  Future<JsonResult> connectPcsc() async {
    permissions++;
    return {'ok': true, 'snapPermission': 'connected'};
  }
}

Widget screen(
  FakeFirefoxSetup service, {
  ValueChanged<bool>? busy,
  String language = 'it',
  double scale = 1,
  bool home = false,
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
          ? FirefoxSetupHomeCard(service: service, onBusy: busy ?? (_) {})
          : FirefoxSetupCard(service: service, onBusy: busy ?? (_) {}),
    ),
  ),
);

Future<void> open(WidgetTester tester, {String language = 'it'}) async {
  await tester.tap(
    find.text(language == 'it' ? 'Configura Firefox' : 'Configure Firefox'),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> prepare(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continua'));
  await tester.tap(find.text('Continua'));
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Configura profilo'));
  await tester.tap(find.text('Configura profilo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Configura').last);
  await tester.pumpAndSettle();
}

void main() {
  JsonResult ready() => {
    'ok': true,
    'profiles': [
      {
        'id': 'desktop',
        'label': 'Work',
        'target': 'firefox',
        'state': 'configured',
      },
      {
        'id': 'snap',
        'label': 'Personal',
        'target': 'snap',
        'state': 'configured',
      },
    ],
    'snapPermission': 'connected',
  };

  test(
    'Home visibility distinguishes configuration needs from unused profiles',
    () {
      expect(firefoxSetupNeeded(ready()), isFalse);
      expect(firefoxSetupNeeded({'ok': true, 'profiles': []}), isFalse);
      expect(
        firefoxSetupNeeded({
          'ok': true,
          'profiles': [
            {'target': 'snap', 'state': 'profile_uninitialized'},
          ],
          'snapPermission': 'disconnected',
        }),
        isFalse,
      );
      for (final permission in ['disconnected', 'unknown']) {
        expect(
          firefoxSetupNeeded({...ready(), 'snapPermission': permission}),
          isTrue,
        );
      }
      for (final state in [
        'needs_setup',
        'module_conflict',
        'profile_invalid',
        'runtime_invalid',
      ]) {
        expect(
          firefoxSetupNeeded({
            'ok': true,
            'profiles': [
              {'target': 'firefox', 'state': state},
            ],
          }),
          isTrue,
        );
      }
      expect(
        firefoxSetupNeeded({'ok': false, 'code': 'configuration_unavailable'}),
        isTrue,
      );
    },
  );

  testWidgets('Home hides ready setup without opening the wizard', (
    tester,
  ) async {
    final service = FakeFirefoxSetup()..inspectResult = ready();
    await tester.pumpWidget(screen(service, home: true));
    await tester.pumpAndSettle();
    expect(service.reads, 1);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Configura Firefox'), findsNothing);
    expect(service.writes, 0);
    expect(service.plans, 0);
    expect(service.permissions, 0);
  });

  testWidgets('Home rechecks on resume and after closing the wizard', (
    tester,
  ) async {
    final service = FakeFirefoxSetup()..inspectResult = ready();
    await tester.pumpWidget(screen(service, home: true));
    await tester.pumpAndSettle();
    service.inspectResult = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Configura Firefox'), findsOneWidget);
    service.afterApplyInspection = ready();
    await open(tester);
    await choose(tester, 'Firefox · Work');
    await prepare(tester);
    await confirm(tester);
    expect(find.text('Chiudi'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Firefox'), findsNothing);
    expect(service.writes, 1);
    expect(service.permissions, 0);
  });

  testWidgets('Firefox setup is conditional in Home and absent from Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firefox = FakeFirefoxSetup();
    final system = PublicSystem();
    await tester.pumpWidget(
      CiePrototype(
        service: UnifiedFake(),
        webPublisher: system.publish,
        webStatusReader: system.status,
        firefoxSetupService: firefox,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Firefox e Firefox Snap')).dy,
      lessThan(tester.getTopLeft(find.text('Abbina la tua CIE')).dy),
    );
    expect(firefox.writes, 0);
    expect(firefox.permissions, 0);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Firefox'), findsNothing);
    expect(find.text('Firefox e Firefox Snap'), findsNothing);
    firefox.inspectResult = ready();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Firefox'), findsNothing);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Configura Firefox'), findsNothing);
    expect(firefox.plans, 0);
    expect(firefox.writes, 0);
    expect(firefox.permissions, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discovery failure is not presented as an empty profile list', (
    tester,
  ) async {
    final service = FakeFirefoxSetup()
      ..inspectResult = {'ok': false, 'code': 'unsafe_path'};
    await tester.pumpWidget(screen(service));
    await open(tester);
    expect(find.text(firefoxSetupError('unsafe_path')), findsOneWidget);
    expect(
      find.textContaining('Apri e chiudi Firefox, poi premi'),
      findsNothing,
    );
    expect(service.writes, 0);
    service.inspectResult = {
      'ok': true,
      'profiles': [],
      'snapPermission': 'unknown',
    };
    await tester.tap(find.text('Rileggi profili'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Apri e chiudi Firefox, poi premi'),
      findsOneWidget,
    );
    expect(find.text(firefoxSetupError('unsafe_path')), findsNothing);
  });

  testWidgets(
    'reload is hidden after selecting a profile and reviewing setup',
    (tester) async {
      final service = FakeFirefoxSetup();
      await tester.pumpWidget(screen(service));
      await open(tester);
      expect(find.text('Rileggi profili'), findsOneWidget);
      await choose(tester, 'Firefox · Work');
      expect(find.text('Rileggi profili'), findsNothing);
      await prepare(tester);
      expect(find.text('Rileggi profili'), findsNothing);
      expect(service.reads, 1);
      expect(service.writes, 0);
    },
  );

  testWidgets(
    'profile list contains only profiles still requiring configuration',
    (tester) async {
      final service = FakeFirefoxSetup()
        ..inspectResult = {
          'ok': true,
          'profiles': [
            {
              'id': 'ready',
              'label': 'Already ready',
              'target': 'firefox',
              'state': 'configured',
            },
            {
              'id': 'snap',
              'label': 'Personal',
              'target': 'snap',
              'state': 'needs_setup',
            },
            {
              'id': 'unused',
              'label': 'Unused',
              'target': 'firefox',
              'state': 'profile_uninitialized',
            },
          ],
          'snapPermission': 'connected',
        };
      await tester.pumpWidget(screen(service));
      await open(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.textContaining('Already ready'), findsNothing);
      expect(find.textContaining('Unused'), findsNothing);
      await tester.tap(find.text('Firefox Snap · Personal').last);
      await tester.pumpAndSettle();
      await prepare(tester);
      await confirm(tester);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(service.writes, 1);
    },
  );

  testWidgets(
    'ready profiles are hidden but Snap reader permission remains actionable',
    (tester) async {
      final service = FakeFirefoxSetup()
        ..inspectResult = {...ready(), 'snapPermission': 'disconnected'};
      await tester.pumpWidget(screen(service));
      await open(tester);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Non ci sono profili da configurare.'), findsOneWidget);
      await tester.tap(find.text('Autorizza lettore'));
      await tester.pumpAndSettle();
      expect(service.permissions, 0);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(service.permissions, 0);
      await tester.tap(find.text('Autorizza lettore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autorizza'));
      await tester.pumpAndSettle();
      expect(service.permissions, 1);
      expect(service.plans, 0);
      expect(service.writes, 0);
      expect(find.text('Firefox Snap può usare il lettore.'), findsOneWidget);
    },
  );

  testWidgets(
    'fully configured browsers show a short ready message and no selector',
    (tester) async {
      final service = FakeFirefoxSetup()..inspectResult = ready();
      await tester.pumpWidget(screen(service));
      await open(tester);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Non ci sono profili da configurare.'), findsOneWidget);
      expect(find.text('Autorizza lettore'), findsNothing);
      expect(find.text('Continua'), findsNothing);
      expect(service.writes, 0);
    },
  );

  testWidgets('pending registration disables repeated actions and close', (
    tester,
  ) async {
    final service = FakeFirefoxSetup()..pending = Completer<JsonResult>();
    await tester.pumpWidget(screen(service));
    await open(tester);
    await choose(tester, 'Firefox · Work');
    await prepare(tester);
    await tester.ensureVisible(find.text('Configura profilo'));
    await tester.tap(find.text('Configura profilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configura'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.writes, 1);
    final close = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Chiudi'),
    );
    expect(close.onPressed, isNull);
    service.pending!.complete(service.applyResult);
    await tester.pumpAndSettle();
    expect(service.writes, 1);
  });
  testWidgets(
    'opening and closing only reads; no profile is implicitly selected',
    (tester) async {
      final service = FakeFirefoxSetup();
      final busy = <bool>[];
      await tester.pumpWidget(screen(service, busy: busy.add));
      expect(service.reads, 0);
      await open(tester);
      expect(service.reads, 1);
      expect(service.plans, 0);
      expect(find.text('Continua'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      expect(busy, [true, false]);
      expect(service.writes, 0);
      expect(service.permissions, 0);
    },
  );

  testWidgets('cancel at the final confirmation never writes', (tester) async {
    final service = FakeFirefoxSetup();
    await tester.pumpWidget(screen(service));
    await open(tester);
    await choose(tester, 'Firefox · Work');
    await prepare(tester);
    expect(service.writes, 0);
    await tester.ensureVisible(find.text('Configura profilo'));
    await tester.tap(find.text('Configura profilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(service.writes, 0);
    expect(service.permissions, 0);
  });

  testWidgets(
    'confirmation applies exactly the reviewed profile and fingerprint',
    (tester) async {
      final service = FakeFirefoxSetup();
      await tester.pumpWidget(screen(service));
      await open(tester);
      await choose(tester, 'Firefox · Work');
      await prepare(tester);
      await confirm(tester);
      expect(service.writes, 1);
      expect(service.appliedProfile, 'desktop');
      expect(service.appliedFingerprint, 'reviewed-desktop');
      expect(service.permissions, 0);
      expect(find.textContaining('usa il PIN completo'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('Snap permission requires its own separate confirmation', (
    tester,
  ) async {
    final service = FakeFirefoxSetup();
    await tester.pumpWidget(screen(service));
    await open(tester);
    await choose(tester, 'Firefox Snap · Personal');
    expect(find.text('Autorizza lettore'), findsNothing);
    await prepare(tester);
    await confirm(tester);
    expect(service.writes, 1);
    expect(service.permissions, 0);
    final permission = find.text('Autorizza lettore');
    await tester.ensureVisible(permission);
    await tester.tap(permission);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(service.permissions, 0);
    await tester.ensureVisible(permission);
    await tester.tap(permission);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autorizza'));
    await tester.pumpAndSettle();
    expect(service.permissions, 1);
    expect(service.writes, 1);
    expect(find.text('Firefox Snap può usare il lettore.'), findsOneWidget);
  });

  testWidgets('failed registration is not retried automatically', (
    tester,
  ) async {
    final service = FakeFirefoxSetup()
      ..applyResult = {'ok': false, 'code': 'plan_changed'};
    await tester.pumpWidget(screen(service));
    await open(tester);
    await choose(tester, 'Firefox · Work');
    await prepare(tester);
    await confirm(tester);
    expect(service.writes, 1);
    expect(find.text(firefoxSetupError('plan_changed')), findsOneWidget);
    expect(find.text('Configura profilo'), findsNothing);
    expect(service.permissions, 0);
  });

  testWidgets('small window and large text retain visible dialog actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeFirefoxSetup();
    await tester.pumpWidget(screen(service, scale: 1.5));
    await open(tester);
    await choose(tester, 'Firefox Snap · Personal');
    await prepare(tester);
    await confirm(tester);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(service.writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wizard English texts are localized and profile names stay unchanged',
    (tester) async {
      final service = FakeFirefoxSetup();
      await tester.pumpWidget(screen(service, language: 'en'));
      await open(tester, language: 'en');
      expect(find.text('Firefox profile'), findsOneWidget);
      expect(find.text('Profilo Firefox'), findsNothing);
      await choose(tester, 'Firefox · Work');
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Firefox · Work'), findsOneWidget);
    },
  );
}
