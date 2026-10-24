// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';

import 'package:cie_flutter_prototype/desktop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/assistance_view.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/guide_view.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/preferences.dart';
import 'package:cie_flutter_prototype/settings_view.dart';

import 'widget_test.dart' show FakeService;

void main() {
  test(
    'Keychain cleanup diagnostic retains only known code and numeric OS status',
    () {
      final recorder = DiagnosticRecorder()..level = AppDiagnosticLevel.errors;
      recorder.record('change_pin', {
        'ok': true,
        'cleanupCode': 'pairing_store_cleanup_failed',
        'cleanupNativeCode': -25308,
        'cleanupWarning': 'Sensitive arbitrary text',
        'pin': '10293847',
        'card': 'PRIVATE_CARD',
      }, 12);
      expect(recorder.events, hasLength(1));
      expect(recorder.events.single['ok'], isTrue);
      expect(recorder.events.single['cleanupNativeCode'], -25308);
      expect(
        recorder.events.single['cleanupCode'],
        'pairing_store_cleanup_failed',
      );
      expect(recorder.events.single.containsKey('cleanupWarning'), isFalse);
      expect(recorder.events.single.containsKey('pin'), isFalse);
      expect(recorder.events.single.containsKey('card'), isFalse);
      recorder.record('change_pin', {
        'ok': true,
        'cleanupCode': 'arbitrary',
        'cleanupNativeCode': 'secret',
      }, 1);
      expect(recorder.events, hasLength(1));
    },
  );

  test('proxy validation rejects credentials in URLs, invalid hosts and ports, control injection', () {
    for (final host in [
      'http://proxy.test',
      'user@proxy.test',
      'proxy.test/path',
      'a..b',
      'bad host',
      '-host',
      '[:::]',
      '[fe80::1%en0]',
    ]) {
      expect(
        () => ProxySettings(
          mode: ProxyMode.http,
          host: host,
          port: 8080,
        ).validate(),
        throwsFormatException,
        reason: host,
      );
    }
    for (final port in [0, -1, 65536]) {
      expect(
        () => ProxySettings(
          mode: ProxyMode.http,
          host: 'proxy.test',
          port: port,
        ).validate(),
        throwsFormatException,
      );
    }
    for (final host in ['proxy.test', '127.0.0.1', '[::1]', '[2001:db8::1]']) {
      ProxySettings(mode: ProxyMode.https, host: host, port: 443).validate();
    }
    expect(
      () => const SessionNetworkConfig(
        proxy: ProxySettings(
          mode: ProxyMode.http,
          host: 'proxy.test',
          port: 80,
        ),
        username: 'u',
        password: 'x\ny',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const SessionNetworkConfig(username: 'u').validate(),
      throwsFormatException,
    );
    expect(
      () => const SessionNetworkConfig(
        proxy: ProxySettings(
          mode: ProxyMode.http,
          host: 'proxy.test',
          port: 80,
        ),
        username: 'u:v',
      ).validate(),
      throwsFormatException,
    );
  });
  test('network settings persist only whitelisted nonsecret values and reject corrupt or extra fields', () async {
    final root = Directory.systemTemp.createTempSync('cie impostazioni à ');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = FileSettingsStore(directory: root);
    await store.save(
      const AppSettings(
        proxy: ProxySettings(
          mode: ProxyMode.https,
          host: 'proxy.test',
          port: 8443,
        ),
        diagnostics: AppDiagnosticLevel.operations,
      ),
    );
    final loaded = await FileSettingsStore(directory: root).load();
    expect(loaded.proxy.host, 'proxy.test');
    expect(loaded.proxy.mode, ProxyMode.https);
    expect(loaded.diagnostics, AppDiagnosticLevel.operations);
    final file = File.fromUri(root.uri.resolve('settings.json'));
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data.keys.toSet(), {
      'schema',
      'proxy',
      'diagnostics',
      'language',
      'theme',
    });
    expect((data['proxy'] as Map).keys.toSet(), {'mode', 'host', 'port'});
    data['password'] = 'not-accepted';
    file.writeAsStringSync(jsonEncode(data));
    await expectLater(store.load(), throwsFormatException);
    file.writeAsStringSync('{bad');
    await expectLater(store.load(), throwsA(anything));
    await store.save(const AppSettings());
    expect((await store.load()).proxy.mode, ProxyMode.direct);
  });
  test('settings refuse symlinked storage without changing target', () async {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('cie-settings-link-');
    addTearDown(() => root.deleteSync(recursive: true));
    final target = Directory('${root.path}/target')..createSync();
    final link = Link('${root.path}/link')..createSync(target.path);
    await expectLater(
      FileSettingsStore(directory: Directory(link.path))
          .save(const AppSettings()),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.listSync(), isEmpty);
  });
  test('signature preferences also refuse a symlinked directory', () async {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('cie-preferences-link-');
    addTearDown(() => root.deleteSync(recursive: true));
    final target = Directory('${root.path}/target')..createSync();
    final link = Link('${root.path}/link')..createSync(target.path);
    await expectLater(
      FilePreferencesStore(directory: Directory(link.path)).saveFormat('p7m'),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.listSync(), isEmpty);
  });
  test('diagnostics projects fields and never serializes input, result strings or identities', () async {
    final recorder = DiagnosticRecorder()
      ..level = AppDiagnosticLevel.operations;
    const secret = 'PRIVATE-PIN-12345678-password';
    recorder.record('verify', {
      'ok': false,
      'code': secret,
      'message': secret,
      'input': '/private/$secret.pdf',
      'signers': [
        {'name': secret},
      ],
      'nativeCode': secret,
      'signatureCount': 3,
    }, 12);
    final report = jsonEncode(
      recorder.snapshot(
        network: const SessionNetworkConfig(
          proxy: ProxySettings(
            mode: ProxyMode.http,
            host: 'private.proxy.test',
            port: 123,
          ),
          username: secret,
          password: secret,
        ),
        capabilities: {'ok': true, 'middleware': '/Users/$secret/lib.dylib'},
      ),
    );
    expect(report, isNot(contains(secret)));
    expect(report, isNot(contains('private.proxy.test')));
    expect(report, contains('unclassified_error'));
    expect(report, contains('signatureCount'));
    for (var i = 0; i < 220; i++) {
      recorder.record('detect', {'ok': true, 'cardId': secret}, i);
    }
    expect(recorder.events.length, 200);
    recorder.level = AppDiagnosticLevel.errors;
    recorder.clear();
    recorder.record('load', {'ok': true}, 2);
    expect(recorder.events, isEmpty);
    recorder.record('load', {'ok': false, 'code': 'backend_missing'}, 2);
    expect(recorder.events.single['code'], 'backend_missing');
    recorder.level = AppDiagnosticLevel.off;
    recorder.clear();
    recorder.record('verify', {'ok': false}, 1);
    expect(recorder.events, isEmpty);
  });
  testWidgets(
    'assistance contains supplied contacts and FAQ opens exact URL, failure remains readable',
    (tester) async {
      final urls = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistanceView(
                opener: (uri) async {
                  urls.add(uri);
                  return false;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('cie.cittadini@interno.it'), findsOneWidget);
      expect(find.text('06 4298 5699'), findsOneWidget);
      expect(find.text('800 098 558'), findsOneWidget);
      await tester.tap(find.text('Domande frequenti'));
      await tester.pumpAndSettle();
      expect(urls.single.toString(), assistanceFaq);
      expect(
        find.textContaining('Impossibile aprire il browser.'),
        findsOneWidget,
      );
      expect(find.textContaining('9:00 alle ore 16:00'), findsOneWidget);
      expect(find.textContaining('8:00 alle ore 18:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Assistenza follows Guida and settings work without detecting the card',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      final rail = tester.widget<DesktopNavigation>(
        find.byType(DesktopNavigation),
      );
      expect(rail.destinations[5].label, 'Guida');
      expect(rail.destinations[6].label, 'Assistenza');
      expect(rail.destinations[7].label, 'Informazioni');
      expect(rail.destinations[8].label, 'Impostazioni');
      expect(
        find.descendant(
          of: find.byType(DesktopNavigation),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Assistenza'));
      await tester.pumpAndSettle();
      expect(find.text('cie.cittadini@interno.it'), findsOneWidget);
      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();
      expect(tester.widgetList<Tab>(find.byType(Tab)).map((tab) => tab.text), [
        'Generali',
        'Proxy',
        'Log',
      ]);
      expect(find.text('Lingua dell’applicazione'), findsOneWidget);
      expect(find.text('Test connessione'), findsNothing);
      expect(service.detectCalls, 0);
      expect(service.signCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'invalid draft does not invoke proxy test, valid draft remains separate from saved values',
    (tester) async {
      var probes = 0, saves = 0;
      SessionNetworkConfig? tested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsView(
                value: const AppSettings(),
                network: const SessionNetworkConfig(),
                onSave: (a, n) async {
                  saves++;
                },
                onProbe: (n) async {
                  probes++;
                  tested = n;
                  return {'ok': false, 'transportCode': 5, 'httpStatus': 0};
                },
                diagnostics: DiagnosticRecorder(),
                capabilities: null,
                onBusy: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Proxy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connessione diretta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proxy HTTP').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test connessione'));
      await tester.tap(find.text('Test connessione'));
      await tester.pumpAndSettle();
      expect(probes, 0);
      expect(saves, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Host del proxy'),
        'proxy.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Porta del proxy'),
        '8080',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test connessione'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test connessione'));
      await tester.pumpAndSettle();
      expect(probes, 1);
      expect(saves, 0);
      expect(tested!.proxy.host, 'proxy.test');
      expect(find.textContaining('Connessione non riuscita'), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Host del proxy'),
        'changed.proxy.test',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Connessione non riuscita'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
