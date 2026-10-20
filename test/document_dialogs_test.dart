// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/document_dialogs.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/app_flow.dart';
import 'package:cie_flutter_prototype/page_header.dart';

import 'pairing_test.dart' show PairedFake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final signed in [false, true]) {
    test(
      'Desktop-first ${signed ? 'verification' : 'signing'} dialog preserves filters and cancel',
      () async {
        const channel = MethodChannel('cie.id/file-dialogs');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'desktopDirectory');
              return '/Volumes/Archivio/Desktop';
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final result = await openDocumentDialog(
          signed: signed,
          picker: ({initialDirectory, required acceptedTypeGroups}) async {
            expect(
              initialDirectory,
              Platform.isMacOS ? '/Volumes/Archivio/Desktop' : isNotNull,
            );
            expect(
              acceptedTypeGroups.first.extensions,
              signed ? ['pdf', 'p7m', 'p7s'] : isNull,
            );
            return XFile('/test/document.pdf');
          },
        );
        expect(result, '/test/document.pdf');
        expect(
          await openDocumentDialog(
            signed: signed,
            picker: ({initialDirectory, required acceptedTypeGroups}) async =>
                null,
          ),
          isNull,
        );
      },
    );
  }
  testWidgets(
    'first wizard Back stays visible disabled, explanatory text has a line of space',
    (t) async {
      t.view.physicalSize = const Size(1280, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        CiePrototype(service: PairedFake()..cards.add('TEST')),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      final back = find.widgetWithText(OutlinedButton, 'Indietro');
      expect(t.widget<OutlinedButton>(back).onPressed, isNull);
      final sign = find.widgetWithText(
        OutlinedButton,
        'Firma con CIE non presente in elenco',
      );
      final caption = find.textContaining('Puoi preparare il documento prima');
      expect(
        t.getTopLeft(caption).dy - t.getBottomLeft(sign).dy,
        greaterThanOrEqualTo(24),
      );
      await t.tap(back);
      await t.pumpAndSettle();
      expect(
        t
            .widget<ApplicationPageHeader>(find.byType(ApplicationPageHeader))
            .destination,
        AppDestination.sign,
      );
      expect(find.text('Seleziona la CIE con cui firmare tra quelle in elenco'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
