// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:cie_flutter_prototype/desktop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/verification_flow.dart';
import 'package:cie_flutter_prototype/verification_view.dart';
import 'package:cie_flutter_prototype/verification_date.dart';

import 'widget_test.dart' show FakeService;
import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

JsonResult checked({
  String name = 'Firmatario sintetico',
  bool? integrity = true,
  Object? revocation = 3,
}) => {
  'ok': true,
  'signatureCount': 1,
  'signers': [
    {
      'commonName': name,
      'signatureValid': integrity,
      'certificateWithinValidity': true,
      'trustChainChecked': true,
      'trustChainStatus': 'trusted',
      'trustChainValidated': true,
      'revocationStatus': revocation,
      'chainRevocationStatus': 3,
      'signingTime': '2026-10-18T09:00:00Z',
      'timestampStatus': 'absent',
    },
  ],
};

class VerifyFake extends FakeService {
  int checks = 0, exports = 0;
  bool structural = false, invalidPdf = false;
  JsonResult response = checked();
  final List<Completer<JsonResult>> pending = [];
  final List<Completer<String>> started = [];
  final paths = <String>[];
  @override
  Future<JsonResult> load() async => {
    'ok': true,
    'canSign': true,
    'canExtract': true,
  };
  @override
  Future<JsonResult> verify(String path) async {
    paths.add(path);
    final index = checks++;
    if (started.length > index) started[index].complete(path);
    return pending.length > index ? pending[index].future : response;
  }

  @override
  Future<JsonResult> pdfInfo(String path, int page) async => {
    'ok': !invalidPdf,
  };
  @override
  Future<JsonResult> extract(String input, String output) async {
    exports++;
    if (!structural) return {'ok': false};
    await File(output).writeAsString('contenuto sintetico');
    return {'ok': true, 'output': output};
  }
}

class MonitorVerifyFake extends UnifiedFake {
  int checks = 0;
  final verified = Completer<void>();
  @override
  Future<JsonResult> verify(String path) async {
    checks++;
    verified.complete();
    return checked();
  }
}

void main() {
  test('ASN.1 and ISO dates remain readable, explicit UTC and reject calendar rollover', () {
    expect(verificationDate('261018092843Z'), '18/10/2026 alle 09:28:43 UTC');
    expect(verificationDate('20261018092843Z'), '18/10/2026 alle 09:28:43 UTC');
    expect(
      verificationDate('2026-10-18T11:28:43+02:00'),
      '18/10/2026 alle 09:28:43 UTC',
    );
    expect(verificationDate('500101000000Z'), '01/01/1950 alle 00:00:00 UTC');
    expect(verificationDate('491231235959Z'), '31/12/2049 alle 23:59:59 UTC');
    expect(
      verificationDate('2026-02-31T10:00:00Z'),
      'Formato data non riconosciuto',
    );
    expect(
      verificationDate('20261018092843+2500'),
      'Formato data non riconosciuto',
    );
    expect(verificationDate('not a date'), 'Formato data non riconosciuto');
    expect(verificationDate(null), 'Non disponibile');
  });
  Future<Directory> folder() async {
    final directory = await Directory.systemTemp.createTemp('cie-ux4-test-');
    addTearDown(() => directory.delete(recursive: true));
    return directory;
  }

  Future<String> document(Directory dir, String name) async {
    final file = File('${dir.path}/$name');
    await file.writeAsString('documento sintetico $name');
    return file.path;
  }

  test(
    'superseded verification cannot publish late results or read a newer file',
    () async {
      final dir = await folder(), service = VerifyFake();
      service.pending.addAll([
        Completer<JsonResult>(),
        Completer<JsonResult>(),
      ]);
      service.started.addAll([Completer<String>(), Completer<String>()]);
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      addTearDown(controller.dispose);
      final first = await document(dir, 'first.pdf'),
          second = await document(dir, 'second.pdf');
      final one = controller.select(first);
      final snapshotOne = await service.started[0].future;
      final two = controller.select(second);
      expect(controller.path, second);
      expect(controller.result, isNull);
      expect(service.checks, 1);
      service.pending[0].complete(checked(name: 'risultato superato'));
      await service.started[1].future;
      expect(File(snapshotOne).existsSync(), isFalse);
      expect(controller.result, isNull);
      service.pending[1].complete(checked(name: 'secondo firmatario'));
      await Future.wait([one, two]);
      expect(
        (controller.result!['signers'] as List).single['commonName'],
        'secondo firmatario',
      );
      expect(service.checks, 2);
      expect(service.detectCalls, 0);
      expect(service.signCalls, 0);
      controller.cancel();
      await controller.settled;
      expect(File(service.paths.last).existsSync(), isFalse);
    },
  );
  test(
    'cancel discards in-flight results, cleans the snapshot and never retries',
    () async {
      final dir = await folder(), service = VerifyFake();
      service.pending.add(Completer<JsonResult>());
      service.started.add(Completer<String>());
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      addTearDown(controller.dispose);
      final job = controller.select(await document(dir, 'cancel.pdf'));
      final snapshot = await service.started.single.future;
      expect(controller.cancel(), isTrue);
      expect(controller.path, isEmpty);
      expect(controller.running, isTrue);
      service.pending.single.complete(checked());
      await job;
      await controller.settled;
      expect(controller.result, isNull);
      expect(controller.running, isFalse);
      expect(service.checks, 1);
      expect(File(snapshot).existsSync(), isFalse);
    },
  );
  test(
    'disposal while checking removes only its temporary files after completion',
    () async {
      final dir = await folder(), service = VerifyFake();
      final source = await document(dir, 'dispose.pdf');
      service.pending.add(Completer<JsonResult>());
      service.started.add(Completer<String>());
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      final job = controller.select(source);
      final snapshot = await service.started.single.future;
      controller.dispose();
      service.pending.single.complete(checked());
      await job;
      expect(File(snapshot).existsSync(), isFalse);
      expect(File(source).existsSync(), isTrue);
    },
  );
  test('original changed during verification invalidates the result and extraction', () async {
    final dir = await folder(), service = VerifyFake();
    service.pending.add(Completer<JsonResult>());
    service.started.add(Completer<String>());
    final source = await document(dir, 'changed.p7m');
    service.structural = true;
    final controller = VerificationController(service, canExtract: () => true);
    addTearDown(controller.dispose);
    final job = controller.select(source);
    await service.started.single.future;
    await File(source).writeAsString('nuovi byte');
    service.pending.single.complete(checked());
    await job;
    expect(controller.result!['code'], 'document_changed');
    expect(controller.extractable, isFalse);
  });
  test('structurally readable P7M remains extractable despite invalid integrity; save cancellation and no-overwrite', () async {
    final dir = await folder(),
        service = VerifyFake()
          ..structural = true
          ..response = checked(integrity: false);
    final controller = VerificationController(service, canExtract: () => true);
    addTearDown(controller.dispose);
    final source = await document(dir, 'document.pdf.p7m');
    await controller.select(source);
    expect(controller.extractable, isTrue);
    expect(service.exports, 1); // private structural probe
    await controller.extract((_) async => null);
    expect(service.exports, 1);
    final existing = await document(dir, 'existing.pdf');
    await controller.extract((_) async => existing);
    expect(controller.extraction!['code'], 'output_exists');
    expect(service.exports, 1);
    final saved = '${dir.path}/extracted.pdf';
    await controller.extract((request) async {
      expect(request.suggestedName, 'document.pdf');
      return saved;
    });
    expect(controller.extraction!['ok'], isTrue);
    expect(await File(saved).readAsString(), 'contenuto sintetico');
    expect(service.exports, 2);
    expect(service.signCalls, 0);
    expect(service.detectCalls, 0);
    controller.cancel();
    await controller.settled;
  });
  test(
    'changing original before extraction rejects output and asks to reverify',
    () async {
      final dir = await folder(), service = VerifyFake()..structural = true;
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      addTearDown(controller.dispose);
      final source = await document(dir, 'changed.p7m');
      await controller.select(source);
      await File(source).writeAsString('changed after verification');
      final output = '${dir.path}/must-not-exist.pdf';
      await controller.extract((_) async => output);
      expect(File(output).existsSync(), isFalse);
      expect(service.exports, 1);
      expect(controller.result!['code'], 'document_changed');
      expect(controller.extractable, isFalse);
      controller.cancel();
      await controller.settled;
    },
  );
  test('unreadable, empty, directory and malformed inputs never become unsigned verdicts', () async {
    final dir = await folder(),
        service = VerifyFake()
          ..invalidPdf = true
          ..response = {'ok': true, 'signatureCount': 0, 'signers': []};
    final controller = VerificationController(service, canExtract: () => true);
    addTearDown(controller.dispose);
    for (final source in [
      dir.path,
      '${dir.path}/missing.pdf',
      (await File('${dir.path}/empty.pdf').writeAsString('')).path,
    ]) {
      await controller.select(source);
      expect(controller.result!['ok'], isFalse);
    }
    expect(service.checks, 0);
    await controller.select(await document(dir, 'broken.pdf'));
    expect(controller.result!['code'], 'document_unreadable');
    controller.cancel();
    await controller.settled;
  });

  Future<void> size(WidgetTester t) async {
    t.view.physicalSize = const Size(1180, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
    'selection starts immediately, results have no PIN and technical findings are disclosed on request',
    (t) async {
      await size(t);
      final dir = (await t.runAsync(folder))!, service = VerifyFake();
      final source = (await t.runAsync(() => document(dir, 'signed.pdf')))!;
      await t.pumpWidget(
        CiePrototype(
          service: service,
          verificationFilePicker: () async => source,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Verifica Firma').first);
      await t.pumpAndSettle();
      final choose =
          t
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Seleziona un documento'),
                  )
                  .onPressed!
              as Future<void> Function();
      await t.runAsync(choose);
      await t.pumpAndSettle();
      expect(service.checks, 1);
      expect(service.detectCalls, 0);
      expect(service.signCalls, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Verifica firma'), findsNothing);
      expect(find.text('Numero di sottoscrittori: 1'), findsOneWidget);
      expect(find.text('Firma: Integra'), findsOneWidget);
      expect(
        find.text('Revoca: Stato di revoca non determinato'),
        findsOneWidget,
      );
      expect(find.textContaining('Emittente:'), findsNothing);
      await t.tap(find.text('Dettagli del firmatario 1'));
      await t.pumpAndSettle();
      expect(find.textContaining('Revoca della catena:'), findsOneWidget);
      expect(
        find.textContaining('Data dichiarata dal firmatario (non verificata)'),
        findsOneWidget,
      );
      await t.runAsync(() async {
        await t.tap(find.text('Concludi'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await t.pumpAndSettle();
      expect(find.text('Seleziona un documento'), findsOneWidget);
      expect(File(service.paths.single).existsSync(), isFalse);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
  testWidgets(
    'canceling a dropped document keeps late results out of the page',
    (t) async {
      await size(t);
      final dir = (await t.runAsync(folder))!, service = VerifyFake();
      final source = (await t.runAsync(() => document(dir, 'pending.pdf')))!;
      service.pending.add(Completer<JsonResult>());
      service.started.add(Completer<String>());
      await t.pumpWidget(CiePrototype(service: service));
      await t.pumpAndSettle();
      await t.tap(find.text('Verifica Firma').first);
      await t.pumpAndSettle();
      final drop = t.widget<DropTarget>(find.byType(DropTarget));
      await t.runAsync(() async {
        drop.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(source)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      expect(
        service.checks,
        1,
        reason: 'Dropped document should reach verifier',
      );
      await t.pump();
      expect(find.text('Annulla verifica'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        t
            .widget<DesktopNavigation>(find.byType(DesktopNavigation))
            .onDestinationSelected,
        isNotNull,
      );
      await t.tap(find.text('Annulla verifica'));
      await t.pump();
      expect(find.text('Seleziona un documento'), findsOneWidget);
      await t.runAsync(() async {
        service.pending.single.complete(checked(name: 'Risultato da scartare'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await t.pumpAndSettle();
      expect(find.text('Risultato da scartare'), findsNothing);
      expect(service.checks, 1);
      expect(service.signCalls, 0);
      expect(service.detectCalls, 0);
    },
  );
  testWidgets(
    'pending card observer is not a prerequisite of document verification',
    (t) async {
      await size(t);
      final dir = (await t.runAsync(folder))!,
          service = MonitorVerifyFake(),
          system = PublicSystem();
      final source = (await t.runAsync(
        () => document(dir, 'without-reader.pdf'),
      ))!;
      service.pending = Completer<JsonResult>();
      await t.pumpWidget(
        CiePrototype(
          service: service,
          verificationFilePicker: () async => source,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Verifica Firma').first);
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final action =
            t
                    .widget<FilledButton>(
                      find.widgetWithText(
                        FilledButton,
                        'Seleziona un documento',
                      ),
                    )
                    .onPressed!
                as Future<void> Function();
        await action();
      });
      await t.pumpAndSettle();
      expect(service.checks, 1);
      expect(service.detectCalls, 0);
      expect(service.signCalls, 0);
      service.pending!.complete({'ok': true, 'readers': []});
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  testWidgets(
    'null checks stay indeterminate; network errors expose codes only in details',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': true,
                  'signatureCount': 2,
                  'signers': [
                    {},
                    {
                      'commonName': 'Secondo',
                      'signatureValid': false,
                      'revocationStatus': 1,
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Firma: Integrità non determinata'), findsOneWidget);
      expect(find.text('Firma: Non integra'), findsOneWidget);
      expect(find.textContaining('Certificato revocato'), findsOneWidget);
      expect(find.textContaining('non valido'), findsNothing);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationView(
                result: {
                  'ok': false,
                  'code': 'network_failed',
                  'nativeCode': 907,
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Verifica non completata'), findsOneWidget);
      expect(find.textContaining('907'), findsNothing);
      await t.tap(find.text('Dettagli tecnici'));
      await t.pumpAndSettle();
      expect(find.textContaining('907'), findsOneWidget);
      expect(find.text('Firma: Non integra'), findsNothing);
    },
  );
  testWidgets(
    'unsigned verdict is distinct from failed or partial verification',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerificationView(
              result: {'ok': true, 'signatureCount': 0, 'signers': []},
            ),
          ),
        ),
      );
      expect(find.text('Nessuna firma trovata'), findsOneWidget);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerificationView(
              result: {
                'ok': true,
                'signatureCount': 0,
                'signers': [],
                'nativeVerification': {'ok': false},
              },
            ),
          ),
        ),
      );
      expect(find.text('Nessuna firma trovata'), findsNothing);
      expect(find.text('Verifica non completata'), findsOneWidget);
    },
  );
}
