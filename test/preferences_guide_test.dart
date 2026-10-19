// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/preferences.dart';
import 'package:cie_flutter_prototype/guide_view.dart';
import 'package:cie_flutter_prototype/main.dart';

import 'widget_test.dart' show FakeService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'preferences survive reload, store only allowed values and reset',
    () async {
      final folder = await Directory.systemTemp.createTemp('cie-preferences-');
      addTearDown(() => folder.delete(recursive: true));
      final store = FilePreferencesStore(directory: folder);
      expect((await store.load()).format, 'pdf');
      await store.saveFormat('p7m');
      final next = FilePreferencesStore(directory: folder);
      expect((await next.load()).format, 'p7m');
      final f = File('${folder.path}/preferences.json');
      final data = jsonDecode(await f.readAsString()) as Map;
      expect(data.keys.toSet(), {'schema', 'format', 'image'});
      data['pin'] = 'NOT_A_REAL_PIN';
      await f.writeAsString(jsonEncode(data));
      await next.load();
      await next.saveFormat('pdf');
      expect(await f.readAsString(), isNot(contains('NOT_A_REAL_PIN')));
      await next.reset();
      expect(
        (await FilePreferencesStore(directory: folder).load()).imagePath,
        isNull,
      );
      expect(folder.listSync().where((f) => f.path.contains('.tmp-')), isEmpty);
    },
  );
  test(
    'malformed or foreign image paths are refused without touching originals',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'cie-preferences-boundary-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final outside = File('${folder.path}/original.png')
        ..writeAsStringSync('not an app image');
      final owned = Directory('${folder.path}/prefs');
      await owned.create();
      final f = File('${owned.path}/preferences.json');
      final store = FilePreferencesStore(directory: owned);
      for (final content in [
        'broken json',
        jsonEncode({'schema': 1, 'format': 'cosign'}),
        jsonEncode({'schema': 1, 'format': 'pdf', 'image': '../original.png'}),
      ]) {
        await f.writeAsString(content);
        await expectLater(store.load(), throwsFormatException);
      }
      await store.reset();
      expect(await outside.readAsString(), 'not an app image');
    },
  );
  testWidgets(
    'per-card images are isolated, persistent and independent of global reset',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await Directory.systemTemp.createTemp(
          'cie-card-images-',
        );
        try {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(12, 8);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          final source = File('${folder.path}/source.png');
          await source.writeAsBytes(bytes!.buffer.asUint8List());
          final private = Directory('${folder.path}/prefs');
          final store = FilePreferencesStore(directory: private);
          await store.load();
          final global = await store.importImage(source.path);
          await store.saveCardImage('CIE-ONE', global.imagePath!);
          await store.saveCardImage('CIE-TWO', source.path);
          final first = await store.cardImage('CIE-ONE'),
              second = await store.cardImage('CIE-TWO');
          expect(first, isNot(second));
          expect(first, isNot(global.imagePath));
          final reloaded = FilePreferencesStore(directory: private);
          expect(await reloaded.cardImage('CIE-ONE'), first);
          await store.reset();
          expect(await reloaded.cardImage('CIE-ONE'), first);
          expect(File(first!).existsSync(), isTrue);
          await File('${File(first).parent.path}/preferences.json')
              .writeAsString('corrupted local metadata');
          await reloaded.removeCardImage('CIE-ONE');
          expect(await reloaded.cardImage('CIE-ONE'), isNull);
          expect(File(second!).existsSync(), isTrue);
          expect(source.existsSync(), isTrue);
          await expectLater(store.cardImage(''), throwsFormatException);
          // A path-looking identifier cannot escape the owned cards directory.
          await store.saveCardImage('../outside', source.path);
          final safePath = await store.cardImage('../outside');
          expect(
            File(safePath!).parent.parent.resolveSymbolicLinksSync(),
            Directory('${private.path}/cards').resolveSymbolicLinksSync(),
          );
        } finally {
          await folder.delete(recursive: true);
        }
      });
    },
  );
  testWidgets(
    'image is normalized and copied, reloadable, removal keeps source',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await Directory.systemTemp.createTemp(
          'cie-image-preferences-',
        );
        try {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(Colors.blue, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(12, 8);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          final source = File('${folder.path}/original.png');
          await source.writeAsBytes(bytes!.buffer.asUint8List());
          final original = await source.readAsBytes();
          final private = Directory('${folder.path}/preferenze ü spazio');
          final store = FilePreferencesStore(directory: private);
          await store.load();
          final saved = await store.importImage(source.path);
          expect(saved.imagePath, isNot(source.path));
          expect(await File(saved.imagePath!).exists(), isTrue);
          expect(
            (await FilePreferencesStore(directory: private).load()).imagePath,
            saved.imagePath,
          );
          final invalid = File('${folder.path}/bad.png');
          await invalid.writeAsString('invalid');
          await expectLater(store.importImage(invalid.path), throwsA(anything));
          expect((await store.load()).imagePath, saved.imagePath);
          await store.removeImage();
          expect(await File(saved.imagePath!).exists(), isFalse);
          expect(await source.readAsBytes(), original);
        } finally {
          await folder.delete(recursive: true);
        }
      });
    },
  );
  test(
    'external opener refuses unsupported schemes and destinations',
    () async {
      expect(await openGuideLink(Uri.parse('file:///tmp/example')), isFalse);
      expect(
        await openGuideLink(Uri.parse('https://example.invalid/')),
        isFalse,
      );
    },
  );
  testWidgets('offline guide expands without card or external navigation', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GuideView(
              opener: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('4. Cofirmare un P7M'));
    await tester.pumpAndSettle();
    expect(find.textContaining('senza creare un P7M annidato'), findsOneWidget);
    expect(opened, isEmpty);
    final official = find.text('Software CIE ufficiale');
    await tester.ensureVisible(official);
    await tester.tap(official);
    await tester.pumpAndSettle();
    expect(opened.single.toString(), guideLinks['Software CIE ufficiale']);
  });
  testWidgets(
    'browser failure remains readable with the correct fallback URL',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuideView(opener: (uri) async => false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final official = find.text('Software CIE ufficiale');
      await tester.ensureVisible(official);
      await tester.tap(official);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Impossibile aprire il browser.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('guide and preferences are available without card detection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeService();
    final store = MemoryPreferencesStore();
    await store.saveFormat('p7m');
    await tester.pumpWidget(CiePrototype(service: service, preferences: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guida'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-title')), findsOneWidget);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Generali'));
    await tester.pumpAndSettle();
    expect(find.text('Preferenze firma'), findsOneWidget);
    expect(service.detectCalls, 0);
    expect(service.signCalls, 0);
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(find.text('Ripristina preferenze iniziali'));
    await tester.tap(find.text('Ripristina preferenze iniziali'));
    await tester.pumpAndSettle();
    expect((await store.load()).format, 'pdf');
    expect(tester.takeException(), isNull);
  });
}
