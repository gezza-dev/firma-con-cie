// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/linux_browser_status.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'chrome_setup_test.dart' show FakeChromeSetup;
import 'firefox_setup_test.dart' show FakeFirefoxSetup;
import 'home_enrollment_test.dart' show UnifiedFake;
import 'web_completion_feedback_test.dart' show size;

JsonResult firefox({
  List<JsonResult> profiles = const [],
  String permission = 'connected',
}) => {'ok': true, 'profiles': profiles, 'snapPermission': permission};
JsonResult profile(String target, [String state = 'configured']) => {
  'id': target,
  'label': 'Synthetic profile',
  'target': target,
  'state': state,
};
JsonResult chrome([String state = 'configured']) => {
  'ok': true,
  'detected': state != 'not_installed',
  'state': state,
};

class LinuxPairedService extends UnifiedFake {
  LinuxPairedService() {
    records['TEST'] = {
      'card': 'TEST',
      'version': 2,
      'readyForSigning': true,
      'publicDataSaved': true,
      'webProvisioned': true,
    };
  }
  @override
  Future<JsonResult> webStatus() async => {
    'ok': true,
    'available': true,
    'browserRegistrationRequired': true,
  };
}

class PendingChrome extends FakeChromeSetup {
  Completer<JsonResult>? inspection;
  @override
  Future<JsonResult> inspect() => inspection?.future ?? super.inspect();
}

class UnreadableFirefox extends FakeFirefoxSetup {
  @override
  Future<JsonResult> inspect() async =>
      throw StateError('synthetic inspection failure');
}

const pairedStatus = ValueKey('paired-web-status-TEST');
const configuredPrefix =
    'Accesso ai siti con CIE configurato. Apri il sito nei seguenti browser: ';
const unconfigured =
    'Accesso ai siti da configurare. Usa i riquadri in cima alla Home per configurare Firefox o Chrome.';

void noPrivateCalls(
  LinuxPairedService service,
  FakeFirefoxSetup f,
  FakeChromeSetup c,
) {
  expect(service.enrollCalls, 0);
  expect(service.completeCalls, 0);
  expect(service.signCalls, 0);
  expect(f.plans, 0);
  expect(f.writes, 0);
  expect(f.permissions, 0);
  expect(c.plans, 0);
  expect(c.writes, 0);
  expect(find.byType(TextField), findsNothing);
}

Widget app(
  LinuxPairedService service,
  FakeFirefoxSetup f,
  FakeChromeSetup c, {
  String language = 'it',
}) => CiePrototype(
  service: service,
  settings: MemorySettingsStore()..value = AppSettings(languageCode: language),
  webStatusReader: () async => {},
  webPublisher: (_, _) async => fail('No certificate publication expected'),
  firefoxSetupService: f,
  chromeSetupService: c,
);

void main() {
  test(
    'lists configured browser families once, with fixed names and order',
    () {
      final config = LinuxBrowserConfiguration(
        firefox: firefox(
          profiles: [
            profile('firefox'),
            profile('firefox'),
            profile('snap'),
            profile('other'),
          ],
        ),
        chrome: chrome(),
      );
      expect(config.enabledBrowsers, [
        'Firefox',
        'Firefox Snap',
        'Google Chrome',
      ]);
      expect(
        config.message,
        '${configuredPrefix}Firefox, Firefox Snap, Google Chrome.',
      );
      expect(config.message, isNot(contains('Synthetic profile')));
    },
  );

  for (final permission in ['connected', 'disconnected', 'unknown']) {
    test(
      'Snap requires a configured profile and pcscd permission=$permission',
      () {
        final config = LinuxBrowserConfiguration(
          firefox: firefox(profiles: [profile('snap')], permission: permission),
          chrome: chrome('not_installed'),
        );
        expect(
          config.enabledBrowsers,
          permission == 'connected' ? ['Firefox Snap'] : isEmpty,
        );
        if (permission == 'disconnected') expect(config.message, unconfigured);
        if (permission == 'unknown') {
          expect(config.message, startsWith('Impossibile verificare'));
        }
      },
    );
  }

  for (final target in ['firefox', 'snap']) {
    test('ignores uninitialized and unconfigured $target profiles', () {
      final config = LinuxBrowserConfiguration(
        firefox: firefox(
          profiles: [
            profile(target, 'profile_uninitialized'),
            profile(target, 'needs_setup'),
          ],
        ),
        chrome: chrome('not_installed'),
      );
      expect(config.enabledBrowsers, isEmpty);
      expect(config.message, unconfigured);
    });
  }

  test(
    'no installed browsers offers setup without claiming a successful check',
    () {
      final config = LinuxBrowserConfiguration(
        firefox: firefox(),
        chrome: chrome('not_installed'),
      );
      expect(config.message, unconfigured);
    },
  );

  test('pending and failed inspections differ from a verified empty list', () {
    expect(
      const LinuxBrowserConfiguration().message,
      startsWith('Verifica della configurazione'),
    );
    for (final bad in <JsonResult>[
      {'ok': false},
      {'ok': true, 'profiles': 'invalid'},
      firefox(profiles: [profile('firefox', 'runtime_invalid')]),
    ]) {
      final config = LinuxBrowserConfiguration(
        firefox: bad,
        chrome: chrome('not_installed'),
      );
      expect(config.enabledBrowsers, isEmpty);
      expect(config.message, startsWith('Impossibile verificare'));
    }
  });

  test(
    'a verified Chrome remains usable when another browser cannot be checked',
    () {
      final config = LinuxBrowserConfiguration(
        firefox: {'ok': false},
        chrome: chrome(),
      );
      expect(config.message, '${configuredPrefix}Google Chrome.');
    },
  );

  test(
    'browser registration cannot hide card publication or system problems',
    () {
      final data = {
        'card': 'TEST',
        'readyForSigning': true,
        'publicDataSaved': true,
        'webProvisioned': true,
      };
      final system = {'available': true, 'browserRegistrationRequired': true};
      final config = LinuxBrowserConfiguration(
        firefox: firefox(),
        chrome: chrome(),
      );
      for (final record in [
        EnrollmentRecord({...data, 'readyForSigning': false}, system),
        EnrollmentRecord({...data, 'publicDataSaved': false}, system),
        EnrollmentRecord({...data, 'webProvisioned': false}, system),
        EnrollmentRecord(data, {...system, 'available': false}),
        EnrollmentRecord(data, {...system, 'componentHostOutdated': true}),
        EnrollmentRecord(data, {
          ...system,
          'componentStatusMessage': 'System problem',
        }),
        EnrollmentRecord(data, system, removalPending: true),
        EnrollmentRecord(data, {'available': true}),
      ]) {
        expect(linuxPairedWebStatus(record, config), record.webStatus);
      }
    },
  );

  testWidgets(
    'paired label reuses Home inspection results and refreshes on resume',
    (t) async {
      size(t);
      final service = LinuxPairedService();
      final f = FakeFirefoxSetup()
        ..inspectResult = firefox(
          profiles: [profile('firefox'), profile('snap')],
        );
      final c = FakeChromeSetup()..state = 'configured';
      await t.pumpWidget(app(service, f, c));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        '${configuredPrefix}Firefox, Firefox Snap, Google Chrome.',
      );
      expect(find.text('Configura Firefox'), findsNothing);
      expect(find.text('Configura Chrome'), findsNothing);
      expect(f.reads, 1);
      expect(c.reads, 1);
      noPrivateCalls(service, f, c);
      f.inspectResult = firefox(
        profiles: [profile('firefox'), profile('snap')],
        permission: 'disconnected',
      );
      c.state = 'not_installed';
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        '${configuredPrefix}Firefox.',
      );
      expect(find.text('Configura Firefox'), findsOneWidget);
      noPrivateCalls(service, f, c);
      f.inspectResult = firefox(profiles: [profile('firefox', 'needs_setup')]);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(pairedStatus)).data, unconfigured);
      noPrivateCalls(service, f, c);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending inspection never displays a configured or empty list prematurely',
    (t) async {
      size(t);
      final service = LinuxPairedService();
      final f = FakeFirefoxSetup()..inspectResult = firefox();
      final pending = Completer<JsonResult>();
      final c = PendingChrome()..inspection = pending;
      await t.pumpWidget(app(service, f, c));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        startsWith('Verifica della configurazione'),
      );
      pending.complete(chrome());
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        '${configuredPrefix}Google Chrome.',
      );
      noPrivateCalls(service, f, c);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed inspection replaces a previous configured label on resume',
    (t) async {
      size(t);
      final service = LinuxPairedService();
      final f = FakeFirefoxSetup()..inspectResult = firefox();
      final c = FakeChromeSetup()..state = 'configured';
      await t.pumpWidget(app(service, f, c));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        '${configuredPrefix}Google Chrome.',
      );
      c.state = 'configuration_unavailable';
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        startsWith('Impossibile verificare'),
      );
      noPrivateCalls(service, f, c);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('inspection exceptions reach the paired label without retries', (
    t,
  ) async {
    size(t);
    final service = LinuxPairedService();
    final f = UnreadableFirefox();
    final c = FakeChromeSetup()..state = 'not_installed';
    await t.pumpWidget(app(service, f, c));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(pairedStatus)).data,
      startsWith('Impossibile verificare'),
    );
    noPrivateCalls(service, f, c);
    await t.pump(const Duration(seconds: 10));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'confirmed Chrome wizard refreshes the paired label when the dialog closes',
    (t) async {
      size(t);
      final service = LinuxPairedService();
      final f = FakeFirefoxSetup()..inspectResult = firefox();
      final c = FakeChromeSetup();
      await t.pumpWidget(app(service, f, c));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(pairedStatus)).data, unconfigured);
      await t.tap(find.text('Configura Chrome'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Continua'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(FilledButton, 'Configura Chrome'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(c.writes, 0);
      await t.tap(find.text('Configura'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        '${configuredPrefix}Google Chrome.',
      );
      expect(find.text('Configura Chrome'), findsNothing);
      expect(c.writes, 1);
      expect(c.plans, 1);
      expect(f.writes, 0);
      expect(f.permissions, 0);
      expect(service.enrollCalls, 0);
      expect(service.completeCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('closing the app during inspection discards the late result', (
    t,
  ) async {
    size(t);
    final service = LinuxPairedService();
    final f = FakeFirefoxSetup()..inspectResult = firefox();
    final pending = Completer<JsonResult>();
    final c = PendingChrome()..inspection = pending;
    await t.pumpWidget(app(service, f, c));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    pending.complete(chrome());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    noPrivateCalls(service, f, c);
  });

  testWidgets(
    'English label with all browsers wraps in a small window at 200 percent',
    (t) async {
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final service = LinuxPairedService();
      final f = FakeFirefoxSetup()
        ..inspectResult = firefox(
          profiles: [profile('firefox'), profile('snap')],
        );
      final c = FakeChromeSetup()..state = 'configured';
      await t.pumpWidget(app(service, f, c, language: 'en'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(pairedStatus));
      expect(
        t.widget<Text>(find.byKey(pairedStatus)).data,
        'Website access with CIE configured. Open the website in the following browsers: Firefox, Firefox Snap, Google Chrome.',
      );
      expect(t.takeException(), isNull);
      noPrivateCalls(service, f, c);
      await t.pumpWidget(const SizedBox());
    },
  );
}
