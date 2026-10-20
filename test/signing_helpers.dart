// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> signingDocument(
  WidgetTester t, {
  String? pairedCard,
  bool toPin = true,
  String? path,
}) async {
  await t.tap(find.text('Firma Elettronica').first);
  await t.pumpAndSettle();
  if (find.text('Seleziona la CIE con cui firmare tra quelle in elenco').evaluate().isNotEmpty) {
    await t.tap(
      pairedCard == null
          ? find.text('Firma con CIE non presente in elenco')
          : find.byKey(ValueKey('signing-card-$pairedCard')),
    );
    await t.pumpAndSettle();
  }
  Directory? directory;
  if (path == null) {
    directory = Directory.systemTemp.createTempSync('cie-ui-sign-test-');
    path = File('${directory.path}/document.pdf').path;
    File(path).writeAsStringSync('Synthetic test input');
    addTearDown(() {
      if (directory!.existsSync()) directory.deleteSync(recursive: true);
    });
  }
  final target = t.widget<DropTarget>(find.byType(DropTarget));
  await t.runAsync(
    () async => target.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(path!)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    ),
  );
  await t.pumpAndSettle();
  if (toPin) {
    final graphics = find.widgetWithText(
      CheckboxListTile,
      'Aggiungi firma grafica',
    );
    if (graphics.evaluate().isNotEmpty &&
        t.widget<CheckboxListTile>(graphics).value == true) {
      await t.ensureVisible(graphics);
      await t.tap(graphics);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Prosegui'));
    await t.pumpAndSettle();
  }
}

Future<void> pressSign(WidgetTester t) async {
  await t.ensureVisible(find.widgetWithText(FilledButton, 'Firma'));
  await t.runAsync(() async {
    await t.tap(find.widgetWithText(FilledButton, 'Firma'));
    // Allow the asynchronous no-overwrite filesystem check to complete.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  });
  await t.pump();
}
