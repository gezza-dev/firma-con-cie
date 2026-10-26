// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'widget_test.dart' show FakeService;
import 'signing_helpers.dart';

class DocumentsService extends FakeService {
  @override
  Future<JsonResult> extract(String input, String output) async {
    await File(output).writeAsString('Synthetic extracted content');
    return {'ok': true, 'output': output};
  }

  @override
  Future<JsonResult> load() async => {
    'ok': true,
    'canSign': true,
    'canSignPdfAppearance': true,
    'canExtract': true,
    'canCosign': true,
  };
}

void main() {
  test(
    'P7M name removes only outer container and retains document extension',
    () {
      expect(extractedFileName('/tmp/documento.pdf.p7m'), 'documento.pdf');
      expect(
        extractedFileName(r'C:\cartella\documento.pdf.P7M'),
        'documento.pdf',
      );
      expect(extractedFileName('/tmp/documento.p7m.p7m'), 'documento.p7m');
    },
  );
  test('appearance refuses nonfinite and out-of-page rectangles', () {
    PdfAppearance appearance({
      double left = .1,
      double top = .2,
      double width = .3,
      double height = .1,
      int page = 0,
    }) => PdfAppearance(
      imagePath: 'image.png',
      page: page,
      left: left,
      top: top,
      width: width,
      height: height,
    );
    expect(appearance().valid, isTrue);
    expect(appearance(left: .9).valid, isFalse);
    expect(appearance(top: .95).valid, isFalse);
    expect(appearance(width: double.nan).valid, isFalse);
    expect(appearance(height: double.infinity).valid, isFalse);
    expect(appearance(width: 0).valid, isFalse);
    expect(appearance(page: -1).valid, isFalse);
  });
  Future<void> drop(WidgetTester tester, List<String> paths) async {
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    await tester.runAsync(
      () async => target.onDragDone!(
        DropDoneDetails(
          files: paths.map(DropItemFile.new).toList(),
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final page in ['Firma Elettronica', 'Verifica Firma']) {
    testWidgets('$page accepts duplicate references to one dropped file', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync(
        'cie-duplicate-drop-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/documento.pdf.p7m')
        ..writeAsBytesSync([1, 2, 3]);
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = DocumentsService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      // Exercise the real Linux channel parser, as used by a GTK URI-list
      // drop, including CRLF and repeated references to the same file.
      final position = tester.getCenter(find.byType(DropTarget));
      await tester.runAsync(() async {
        final completed = Completer<void>();
        const codec = StandardMethodCodec();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'desktop_drop',
          codec.encodeMethodCall(
            MethodCall('performOperation_linux', [
              '${file.uri}\r\n${file.uri}\r\n',
              [position.dx, position.dy],
            ]),
          ),
          (_) => completed.complete(),
        );
        await completed.future;
        // The plugin's event callback is void; let document filesystem I/O
        // complete in the real async zone before settling Flutter frames.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text(file.path), findsOneWidget);
      expect(
        find.text('Trascinare un solo documento alla volta.'),
        findsNothing,
      );
      expect(service.signCalls, 0);
      expect(service.detectCalls, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      '$page reports an unavailable drop separately from many files',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = DocumentsService();
        await tester.pumpWidget(CiePrototype(service: service));
        await tester.pumpAndSettle();
        await tester.tap(find.text(page).first);
        await tester.pumpAndSettle();
        await drop(tester, []);
        expect(
          find.text(
            'Il documento trascinato non è disponibile. Usa «Seleziona un documento».',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Trascinare un solo documento alla volta.'),
          findsNothing,
        );
        expect(service.signCalls, 0);
        expect(service.detectCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('multiple files and directories are rejected without signing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = DocumentsService();
    await tester.pumpWidget(CiePrototype(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firma Elettronica').first);
    await tester.pumpAndSettle();
    await drop(tester, ['/tmp/a.pdf', '/tmp/b.pdf']);
    expect(
      find.text('Trascinare un solo documento alla volta.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    await drop(tester, [Directory.systemTemp.path]);
    expect(
      find.text('Selezionare un file leggibile, non una cartella.'),
      findsOneWidget,
    );
    expect(service.signCalls, 0);
    expect(service.detectCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'dropped P7M exposes extraction separately from verification and PIN',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('cie-drop-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/documento.pdf.p7m')
        ..writeAsBytesSync([1, 2, 3]);
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = DocumentsService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifica Firma').first);
      await tester.pumpAndSettle();
      await drop(tester, [file.path]);
      expect(find.text(file.path), findsOneWidget);
      expect(find.text('Estrai documento'), findsOneWidget);
      expect(
        find.text(
          'L’estrazione del contenuto non sostituisce la verifica della firma.',
        ),
        findsOneWidget,
      );
      expect(service.signCalls, 0);
      expect(service.detectCalls, 0);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dropped PDF is selected without signing or reading the card', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('cie-drop-busy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/documento.pdf')..writeAsBytesSync([1]);
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = DocumentsService();
    await tester.pumpWidget(CiePrototype(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firma Elettronica').first);
    await tester.pumpAndSettle();
    await drop(tester, [file.path]);
    expect(find.text(file.path), findsOneWidget);
    expect(find.text('Firma PAdES · PDF'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(service.signCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('drop is disabled during signing and never triggers a retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = DocumentsService()..signing = Completer<JsonResult>();
    await tester.pumpWidget(
      CiePrototype(
        service: service,
        signedFilePicker: (_) async =>
            '${Directory.systemTemp.path}/cie-drop-${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rileva carta'));
    await tester.pumpAndSettle();
    await signingDocument(tester);
    await tester.enterText(find.byType(TextField), '12345678');
    await pressSign(tester);
    expect(find.byType(DropTarget), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(service.signCalls, 1);
    await tester.runAsync(() async {
      service.signing!.complete({'ok': false, 'message': 'Errore sintetico'});
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
    expect(service.signCalls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'P7M input selects explicit co-sign mode without authentication',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('cie-cosign-ui-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/original.p7m')
        ..writeAsStringSync('synthetic');
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = DocumentsService();
      await tester.pumpWidget(CiePrototype(service: service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Firma Elettronica').first);
      await tester.pumpAndSettle();
      await drop(tester, [file.path]);
      expect(find.text('Aggiungi una firma'), findsNWidgets(2));
      expect(
        find.textContaining('conservando le firme esistenti'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(service.signCalls, 0);
      expect(service.detectCalls, 0);
    },
  );
}
