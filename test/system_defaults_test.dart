// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/signature_appearance.dart';

import 'widget_test.dart' show FakeService;

void main() {
  test(
    'unsupported or unavailable primary OS language defaults to English',
    () {
      expect(systemLanguageCode(null), 'en');
      expect(systemLanguageCode(const Locale('und')), 'en');
      expect(systemLanguageCode(const Locale('fr', 'FR')), 'en');
      expect(systemLanguageCode(const Locale('de', 'DE')), 'en');
      expect(systemLanguageCode(const Locale('en', 'GB')), 'en');
      expect(systemLanguageCode(const Locale('it', 'CH')), 'it');
      expect(const AppSettings().languageCode, 'system');
      expect(const AppSettings().themeCode, 'system');
      expect(
        () => AppSettings.fromJson({
          ...const AppSettings().toJson(),
          'theme': 'invalid',
        }),
        throwsFormatException,
      );
      expect(
        AppSettings.fromJson(const AppSettings().toJson()).languageCode,
        'system',
      );
    },
  );

  for (final locale in [
    const Locale('it', 'IT'),
    const Locale('en', 'US'),
    const Locale('fr', 'FR'),
    const Locale('und'),
  ]) {
    testWidgets(
      'startup follows primary OS language $locale with English fallback',
      (t) async {
        t.platformDispatcher.localeTestValue = locale;
        final service = FakeService();
        await t.pumpWidget(CiePrototype(service: service));
        await t.pumpAndSettle();
        expect(
          find.text(
            locale.languageCode == 'it'
                ? 'La tua Carta di Identità Elettronica'
                : 'Your Electronic Identity Card',
          ),
          findsOneWidget,
        );
        expect(service.signCalls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('explicit language choice overrides OS at restart', (t) async {
    t.platformDispatcher.localeTestValue = const Locale('it');
    final settings = MemorySettingsStore()
      ..value = const AppSettings(languageCode: 'en');
    await t.pumpWidget(
      CiePrototype(service: FakeService(), settings: settings),
    );
    await t.pumpAndSettle();
    expect(find.text('Your Electronic Identity Card'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual theme overrides OS, persists, and can follow system again',
    (t) async {
      t.view.physicalSize = const Size(1400, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final settings = MemorySettingsStore()
        ..value = const AppSettings(languageCode: 'it');
      final service = FakeService();
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await t.pumpWidget(CiePrototype(service: service, settings: settings));
      await t.pumpAndSettle();
      Brightness brightness() =>
          Theme.of(t.element(find.byKey(const ValueKey('page-title'))))
              .brightness;
      expect(brightness(), Brightness.dark);
      await t.tap(find.text('Impostazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Generali'));
      await t.pumpAndSettle();
      Future<void> choose(String current, String label) async {
        final field = find.byKey(ValueKey('theme-$current'));
        await t.ensureVisible(field);
        await t.tap(field);
        await t.pumpAndSettle();
        await t.tap(find.text(label).last);
        await t.pumpAndSettle();
      }

      await choose('system', 'Chiaro');
      expect(brightness(), Brightness.light);
      expect(settings.value.themeCode, 'light');
      expect(settings.value.languageCode, 'it');
      await choose('light', 'Scuro');
      expect(settings.value.themeCode, 'dark');
      t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await t.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await t.tap(find.widgetWithText(Tab, 'Log'));
      await t.pumpAndSettle();
      await t.tap(find.text('Salva impostazioni'));
      await t.pumpAndSettle();
      expect(settings.value.themeCode, 'dark');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(CiePrototype(service: service, settings: settings));
      await t.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await t.tap(find.text('Impostazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Generali'));
      await t.pumpAndSettle();
      await choose('dark', 'Segui il sistema');
      expect(settings.value.themeCode, 'system');
      expect(brightness(), Brightness.light);
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await t.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
      t.platformDispatcher.clearPlatformBrightnessTestValue();
    },
  );

  test('bottom-right default remains inset in portrait and landscape PDFs', () {
    for (final page in [const Size(595, 842), const Size(842, 595)]) {
      const rectangle = Size(.32, .08);
      final origin = defaultSignaturePosition(page, rectangle);
      expect((1 - origin.dx - rectangle.width) * page.width, closeTo(36, .001));
      expect(
        (1 - origin.dy - rectangle.height) * page.height,
        closeTo(36, .001),
      );
      expect(origin.dx, greaterThan(.5));
      expect(origin.dy, greaterThan(.8));
      expect(
        PdfAppearance(
          imagePath: 'synthetic.png',
          page: 0,
          left: origin.dx,
          top: origin.dy,
          width: rectangle.width,
          height: rectangle.height,
        ).valid,
        isTrue,
      );
    }
    // Small pages still retain a margin without pushing the sign outside them.
    final small = defaultSignaturePosition(
      const Size(100, 100),
      const Size(.35, .2),
    );
    expect(small.dx, closeTo(.55, .0001));
    expect(small.dy, closeTo(.7, .0001));
  });
}
