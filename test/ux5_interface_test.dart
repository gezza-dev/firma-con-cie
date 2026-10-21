// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/app_flow.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/signature_image.dart';
import 'package:cie_flutter_prototype/page_header.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;
import 'widget_test.dart' show FakeService;

void large(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'another card can be enrolled without replacing or authenticating the first card',
    (t) async {
      large(t);
      final service = UnifiedFake(), system = PublicSystem();
      service.records['OLD'] = {
        'card': 'OLD',
        'version': 2,
        'fullName': 'Prima Carta',
        'readyForSigning': true,
        'publicDataSaved': true,
        'certificateHex': '300100',
      };
      service.insert('OLD');
      await t.pumpWidget(
        CiePrototype(
          service: service,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Prima Carta'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('add-another-card')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Le altre carte rimangono memorizzate'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(service.enrollCalls, 0);
      service.insert('NEW');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('Abbina CIE'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '12345678');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(service.records.keys.toSet(), {'OLD', 'NEW'});
      expect(service.records['OLD']!['fullName'], 'Prima Carta');
      expect(service.enrollCalls, 1);
      expect(find.text('Prima Carta'), findsOneWidget);
      expect(find.text('Nome Cognome'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-another-card')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'section headings are centered, Home branding is unique and GUI has no development names',
    (t) async {
      large(t);
      await t.pumpWidget(CiePrototype(service: FakeService()));
      await t.pumpAndSettle();
      for (final destination in AppDestination.values) {
        await t.tap(find.text(destination.label).first);
        await t.pumpAndSettle();
        final heading = find.byKey(const ValueKey('page-title'));
        expect(
          t.widget<Text>(heading).data,
          destination == AppDestination.home ? 'CIE ID' : destination.label,
        );
        final header = find
            .ancestor(of: heading, matching: find.byType(ApplicationPageHeader))
            .first;
        expect(t.getCenter(heading).dx, closeTo(t.getCenter(header).dx, .1));
        expect(
          find.text('La tua Carta di Identità Elettronica'),
          destination == AppDestination.home ? findsOneWidget : findsNothing,
        );
        final text = t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
            .join('\n')
            .toLowerCase();
        expect(text, isNot(contains('prototip')));
        expect(text, isNot(contains('flutter')));
      }
      await t.tap(find.text('Informazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Licenze e riconoscimenti'));
      await t.pumpAndSettle();
      expect(find.text('Apri cartella delle licenze'), findsOneWidget);
      expect(find.textContaining('Flutter'), findsNothing);
      expect(t.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'settings tabs preserve the proxy draft and log saves do not apply an unsaved proxy',
    (t) async {
      large(t);
      final store = MemorySettingsStore();
      await t.pumpWidget(CiePrototype(service: FakeService(), settings: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Impostazioni').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Proxy'));
      await t.pumpAndSettle();
      await t.tap(find.text('Connessione diretta'));
      await t.pumpAndSettle();
      await t.tap(find.text('Proxy HTTP').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Host del proxy'),
        'bozza.example',
      );
      await t.tap(find.widgetWithText(Tab, 'Log'));
      await t.pumpAndSettle();
      expect(find.text('Host del proxy'), findsNothing);
      expect(find.text('Raccolta diagnostica'), findsOneWidget);
      await t.tap(find.text('Salva impostazioni'));
      await t.pumpAndSettle();
      expect((await store.load()).proxy.mode, ProxyMode.direct);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Generali'));
      await t.pumpAndSettle();
      expect(find.text('Preferenze firma'), findsOneWidget);
      expect(find.text('Test connessione'), findsNothing);
      await t.tap(find.widgetWithText(Tab, 'Proxy'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Host del proxy'))
            .controller!
            .text,
        'bozza.example',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'default signature PNG keeps all lines without a large transparent right margin',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('cie-text-crop-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await t.runAsync(() async {
        final file = File('${dir.path}/signature.png');
        await writeDefaultSignatureImage(
          file,
          fullName: 'Léa Maria D’Amico',
          signingDate: DateTime.utc(2026, 10, 18, 12),
        );
        final image = await decodeSignatureImage(file);
        try {
          expect(image.width, lessThan(880));
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          var right = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (rgba!.getUint8((y * image.width + x) * 4 + 3) > 0 &&
                  x > right) {
                right = x;
              }
            }
          }
          expect(image.width - right, lessThanOrEqualTo(22));
        } finally {
          image.dispose();
        }
      });
    },
  );
}
