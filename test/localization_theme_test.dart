// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:async';

import 'package:cie_flutter_prototype/native_bridge.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/app_flow.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';
import 'package:cie_flutter_prototype/l10n/catalog.g.dart';
import 'package:cie_flutter_prototype/paired_card_identity.dart';

import 'package:cie_flutter_prototype/verification_view.dart';

import 'verification_flow_test.dart' show checked;

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;
import 'widget_test.dart' show FakeService;

void large(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 1500);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  test('catalogs preserve placeholders, default language and interpolated personal data', () {
    expect(cieMessages['it']!.keys.toSet(), cieMessages['en']!.keys.toSet());
    for (final source in cieMessages['it']!.keys) {
      final placeholders = RegExp(r'\{p\d+\}');
      expect(
        placeholders
            .allMatches(cieMessages['en']![source]!)
            .map((m) => m[0])
            .toSet(),
        placeholders.allMatches(source).map((m) => m[0]).toSet(),
      );
    }
    final en = CieLocalizations(const Locale('en'));
    expect(
      en.text('Numero carta: {p0}', ['Informazioni']),
      'Card number: Informazioni',
    );
    expect(en.text('Tentativi residui: 2'), 'Remaining attempts: 2');
    expect(en.text('Aggiorna'), 'Update');
    expect(en.text('Aggiorna accesso ai siti'), 'Update website access');
    expect(
      en.text('Percorso personale: /Users/Nome'),
      'Percorso personale: /Users/Nome',
    );
    expect(en.text('Campo mancante: owner'), 'Missing field: owner');
    expect(
      AppSettings.fromJson({
        'schema': 1,
        'proxy': const ProxySettings().toJson(),
        'diagnostics': 'off',
      }).languageCode,
      'system',
    );
    expect(
      () => AppSettings.fromJson({
        'schema': 1,
        'proxy': const ProxySettings().toJson(),
        'diagnostics': 'off',
        'language': 'xx',
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'English UI across every destination and system light/dark transitions without card calls',
    (t) async {
      large(t);
      final service = FakeService();
      final settings = MemorySettingsStore()
        ..value = const AppSettings(languageCode: 'en');
      await t.pumpWidget(CiePrototype(service: service, settings: settings));
      await t.pumpAndSettle();
      expect(find.text('Your Electronic Identity Card'), findsOneWidget);
      final en = CieLocalizations(const Locale('en'));
      for (final destination in AppDestination.values) {
        await t.tap(find.text(en.text(destination.label)).first);
        await t.pumpAndSettle();
        final untranslated = <String>{};
        for (final w in t.widgetList<Text>(find.byType(Text))) {
          final text = w.data;
          if (text != null && en.text(text) != text) untranslated.add(text);
        }
        expect(
          untranslated,
          isEmpty,
          reason: 'Untranslated ${destination.name}: $untranslated',
        );
      }
      await t.tap(find.text('Home').first);
      await t.pumpAndSettle();
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await t.pumpAndSettle();
      expect(
        Theme.of(t.element(find.byKey(const ValueKey('page-title'))))
            .brightness,
        Brightness.dark,
      );
      t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await t.pumpAndSettle();
      expect(
        Theme.of(t.element(find.byKey(const ValueKey('page-title'))))
            .brightness,
        Brightness.light,
      );
      t.platformDispatcher.clearPlatformBrightnessTestValue();
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'English verification details translate status values and UTC date without changing signer identity',
    (t) async {
      large(t);
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [CieLocalizations.delegate],
          supportedLocales: CieLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(result: checked(name: 'Informazioni')),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Informazioni'), findsOneWidget);
      expect(find.textContaining('Signature: Intact'), findsOneWidget);
      expect(find.textContaining(' at 09:00:00 UTC'), findsOneWidget);
      await t.tap(find.text('Signer details 1'));
      await t.pumpAndSettle();
      final en = CieLocalizations(const Locale('en'));
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        final value = w.data;
        if (value != null && value != 'Informazioni') {
          expect(en.text(value), value, reason: value);
        }
      }
      expect(find.textContaining('Stato di revoca'), findsNothing);
    },
  );
  testWidgets(
    'language selection persists and Home text and remove button align with visible card edge',
    (t) async {
      large(t);
      final service = UnifiedFake()..insert();
      final system = PublicSystem()..cards.add('TEST');
      service.records['TEST'] = {
        'card': 'TEST',
        'fullName': 'Nome Cognome',
        'cardNumber': 'CA00000AA',
        'readyForSigning': true,
        'publicDataSaved': true,
        'certificateHex': '300100',
      };
      final settings = MemorySettingsStore();
      await t.pumpWidget(
        CiePrototype(
          service: service,
          settings: settings,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      final art = find.byType(CieCardIllustration).last;
      final edge =
          t.getTopLeft(art).dx + 144 * CieCardIllustration.artworkLeftFraction;
      for (final text in [
        'CIE abbinata. Puoi firmare documenti.',
        'Accesso ai siti configurato: apri il sito nel browser.',
        'Rimuovi CIE',
      ]) {
        expect(t.getTopLeft(find.text(text)).dx, closeTo(edge, .1));
      }
      // Even a slow reader observation must not delay changing a UI language.
      final observation = Completer<JsonResult>();
      service.pending = observation;
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.text('Impostazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Generali'));
      await t.pumpAndSettle();
      await t.tap(find.text('Segui il sistema').first);
      await t.pumpAndSettle();
      await t.tap(find.text('English').last);
      await t.pumpAndSettle();
      expect(settings.value.languageCode, 'en');
      expect(find.text('Application language'), findsOneWidget);
      expect(observation.isCompleted, isFalse);
      observation.complete(service.presence);
      service.pending = null;
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Logs'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save settings'));
      await t.pumpAndSettle();
      expect(settings.value.languageCode, 'en');
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  test('file settings preserve chosen language across restart', () async {
    final tmp = await Directory.systemTemp.createTemp('cie-language-test-');
    addTearDown(() => tmp.delete(recursive: true));
    await FileSettingsStore(directory: tmp)
        .save(const AppSettings(languageCode: 'en', themeCode: 'dark'));
    final restored = await FileSettingsStore(directory: tmp).load();
    expect(restored.languageCode, 'en');
    expect(restored.themeCode, 'dark');
    expect(
      jsonDecode(
        await File('${tmp.path}/settings.json').readAsString(),
      )['language'],
      'en',
    );
  });
}
