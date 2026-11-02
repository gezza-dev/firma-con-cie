// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/network_settings.dart';
import 'package:cie_flutter_prototype/verification_flow.dart';
import 'package:cie_flutter_prototype/tls_recovery.dart';

import 'widget_test.dart' show FakeService;

JsonResult certificateResult({
  int leaf = 0,
  int chain = 3,
  String source = 'cie_ministry',
}) => {
  'ok': true,
  'signatureCount': 1,
  'signers': [
    {
      'trustChainStatus': 'trusted',
      'trustSource': source,
      'revocationStatus': leaf,
      'chainRevocationStatus': chain,
    },
  ],
};

class CommandFake {
  final calls = <(List<String>, String)>[];
  int code = 0;
  bool schannel = true;
  Completer<void>? pending;
  Future<(int, String)> call(
    String executable,
    List<String> args,
    String input,
  ) async {
    calls.add((args, input));
    if (args.contains('--version')) {
      return (0, schannel ? 'curl Schannel' : 'curl OpenSSL');
    }
    await pending?.future;
    return (code, code == 0 ? '200' : '000');
  }

  TlsRecovery service({bool enabled = true}) => TlsRecovery(
    operatingSystem: 'windows',
    enabled: enabled,
    command: call,
    executable: 'synthetic-system-curl.exe',
  );
}

class VerifyOnly extends FakeService {
  int verifications = 0;
  final paths = <String>[];
  @override
  Future<JsonResult> verify(String path) async {
    paths.add(path);
    verifications++;
    return certificateResult(chain: verifications == 1 ? 3 : 0);
  }
}

void main() {
  test('only TLS code 60 or a trusted CIE chain with unknown revocation offers recovery', () {
    expect(TlsRecovery.needsRecovery({'ok': false, 'transportCode': 60}), true);
    expect(TlsRecovery.needsRecovery(certificateResult()), true);
    for (final result in [
      {'ok': false, 'transportCode': 7},
      certificateResult(chain: 0),
      certificateResult(leaf: 1),
      certificateResult(chain: 2),
      certificateResult(source: 'explicit_policy'),
      {'ok': true, 'signers': []},
    ]) {
      expect(TlsRecovery.needsRecovery(result), false);
    }
  });

  test(
    'no consent means no request, retry or recurring dialog in this session',
    () async {
      final fake = CommandFake(), original = certificateResult();
      final service = fake.service();
      var prompts = 0, checks = 0;
      Future<JsonResult> run() => service.retry(
        original: original,
        network: const SessionNetworkConfig(),
        consent: () async {
          prompts++;
          return false;
        },
        verify: () async {
          checks++;
          return {};
        },
        isCurrent: () => true,
        record: (_) => fail('no recovery log'),
        onRecovery: (_) async {},
      );
      expect(await run(), same(original));
      expect(await run(), same(original));
      expect(prompts, 1);
      expect(checks, 0);
      expect(fake.calls, isEmpty);
    },
  );

  test('native recovery only uses fixed HTTPS hosts with verified TLS and no inherited proxy/config', () async {
    final fake = CommandFake();
    expect(
      (await fake.service().recover(const SessionNetworkConfig()))['ok'],
      true,
    );
    expect(fake.calls.length, 3);
    for (final (args, input) in fake.calls.skip(1)) {
      expect(args.first, '-q');
      expect(args[args.indexOf('--proxy') + 1], '');
      expect(args[args.indexOf('--noproxy') + 1], '');
      expect(args[args.indexOf('--proto') + 1], '=https');
      expect(
        args,
        containsAll([
          '--head',
          '--tlsv1.2',
          '--no-ssl-auto-client-cert',
          '--max-time',
        ]),
      );
      expect(TlsRecovery.endpoints, contains(args.last));
      expect(args, isNot(contains('--insecure')));
      expect(args, isNot(contains('-L')));
      expect(input, isEmpty);
    }
  });

  test('explicit proxy and escaped authentication stay in stdin, without direct fallback', () async {
    final fake = CommandFake()..code = 60;
    const config = SessionNetworkConfig(
      proxy: ProxySettings(
        mode: ProxyMode.https,
        host: 'proxy.example',
        port: 443,
      ),
      username: 'synthetic-user',
      password: 'synthetic-"\\-password',
    );
    final result = await fake.service().recover(config);
    expect(result['ok'], false);
    expect(result['transportCode'], 60);
    expect(result['completedEndpoints'], 0);
    expect(fake.calls.length, 3);
    for (final (args, input) in fake.calls.skip(1)) {
      expect(args[args.indexOf('--proxy') + 1], 'https://proxy.example:443');
      expect(args.join(), isNot(contains('synthetic-user')));
      expect(args.join(), isNot(contains('password')));
      expect(
        input,
        'proxy-user = "synthetic-user:synthetic-\\"\\\\-password"\n',
      );
    }
    expect(result.toString(), isNot(contains('synthetic')));
  });

  test(
    'foreign TLS client and invalid configuration never make recovery requests',
    () async {
      final fake = CommandFake()..schannel = false;
      expect(
        (await fake.service().recover(
          const SessionNetworkConfig(),
        ))['completedEndpoints'],
        0,
      );
      expect(fake.calls.length, 1);
      expect(
        () => fake.service().recover(
          const SessionNetworkConfig(
            proxy: ProxySettings(
              mode: ProxyMode.http,
              host: 'https://bad/',
              port: 80,
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(fake.calls.length, 1);
    },
  );

  test(
    'successful connections alone never turn unknown revocation into good',
    () async {
      final fake = CommandFake(), original = certificateResult();
      var checked = 0;
      final result = await fake.service().retry(
        original: original,
        network: const SessionNetworkConfig(),
        consent: () async => true,
        verify: () async {
          checked++;
          return original;
        },
        isCurrent: () => true,
        record: (_) {},
        onRecovery: (_) async {},
      );
      expect(result, same(original));
      expect(checked, 1);
      expect(result['signers'][0]['chainRevocationStatus'], 3);
    },
  );

  test('verification repeats on the retained snapshot; consent cancellation discards stale results', () async {
    final folder = await Directory.systemTemp.createTemp('tls-recovery-test-');
    final file = File('${folder.path}/signed.pdf');
    await file.writeAsString('synthetic');
    final fake = CommandFake(), service = VerifyOnly();
    final recovery = fake.service();
    final controller = VerificationController(
      service,
      canExtract: () => false,
      recover: (original, retry, current) => recovery.retry(
        original: original,
        network: const SessionNetworkConfig(),
        consent: () async => true,
        verify: retry,
        isCurrent: current,
        record: (_) {},
        onRecovery: (_) async {},
      ),
    );
    try {
      await controller.select(file.path);
      expect(service.verifications, 2);
      expect(service.paths[0], service.paths[1]);
      expect(controller.result!['signers'][0]['chainRevocationStatus'], 0);
    } finally {
      controller.dispose();
      await controller.settled;
      await folder.delete(recursive: true);
    }

    final consent = Completer<bool>(), started = Completer<void>();
    final later = VerifyOnly(), transport = CommandFake();
    final pending = VerificationController(
      later,
      canExtract: () => false,
      recover: (original, retry, current) => transport.service().retry(
        original: original,
        network: const SessionNetworkConfig(),
        consent: () {
          started.complete();
          return consent.future;
        },
        verify: retry,
        isCurrent: current,
        record: (_) {},
        onRecovery: (_) async {},
      ),
    );
    final secondFolder = await Directory.systemTemp.createTemp(
      'tls-recovery-cancel-',
    );
    final second = File('${secondFolder.path}/signed.pdf');
    await second.writeAsString('synthetic');
    try {
      final job = pending.select(second.path);
      await started.future;
      pending.cancel();
      consent.complete(true);
      await job;
      expect(transport.calls, isEmpty);
      expect(later.verifications, 1);
      expect(pending.result, isNull);
    } finally {
      pending.dispose();
      await pending.settled;
      await secondFolder.delete(recursive: true);
    }
  });

  test('diagnostics retain only bounded codes and endpoint count', () {
    final recorder = DiagnosticRecorder()
      ..level = AppDiagnosticLevel.operations;
    recorder.record('tls_recovery', {
      'ok': false,
      'code': 'tls_recovery_incomplete',
      'transportCode': 60,
      'httpStatus': 0,
      'completedEndpoints': 1,
      'password': 'secret',
      'certificate': 'private',
      'stderr': 'personal',
    }, 12);
    expect(recorder.events.single['completedEndpoints'], 1);
    expect(recorder.events.toString(), isNot(contains('secret')));
    expect(recorder.events.toString(), isNot(contains('personal')));
  });

  test('a failed verification retry preserves the readable original document result', () async {
    final original = certificateResult();
    final result = await CommandFake().service().retry(
      original: original,
      network: const SessionNetworkConfig(),
      consent: () async => true,
      verify: () async => {'ok': false, 'code': 'verification_failed'},
      isCurrent: () => true,
      record: (_) {},
      onRecovery: (_) async {},
    );
    expect(result, same(original));
  });

  for (final enabled in [false, true]) {
    test(
      'disabled platform or failed transport preserves the original check (enabled=$enabled)',
      () async {
        final fake = CommandFake()..code = 60;
        final original = certificateResult();
        var prompts = 0, checks = 0;
        final result = await fake
            .service(enabled: enabled)
            .retry(
              original: original,
              network: const SessionNetworkConfig(),
              consent: () async {
                prompts++;
                return true;
              },
              verify: () async {
                checks++;
                return certificateResult(chain: 0);
              },
              isCurrent: () => true,
              record: (_) {},
              onRecovery: (_) async {},
            );
        expect(result, same(original));
        expect(checks, 0);
        expect(prompts, enabled ? 1 : 0);
        if (!enabled) expect(fake.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'the app offers consent after verification, remains responsive and only re-verifies',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final folder = Directory.systemTemp.createTempSync('tls-ui-test-');
      final source = File('${folder.path}/signed.pdf')
        ..writeAsStringSync('synthetic');
      addTearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });
      final fake = CommandFake()..pending = Completer<void>();
      final service = VerifyOnly();
      await tester.pumpWidget(
        CiePrototype(
          service: service,
          verificationFilePicker: () async => source.path,
          tlsRecovery: fake.service(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifica Firma').first);
      await tester.pumpAndSettle();
      final choose =
          tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Seleziona un documento'),
                  )
                  .onPressed!
              as Future<void> Function();
      Future<void>? selected;
      await tester.runAsync(() async {
        selected = choose();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Consenti e riprova'), findsOneWidget);
      expect(fake.calls, isEmpty);
      await tester.tap(find.text('Consenti e riprova'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(
        find.text('Aggiornamento dei certificati di sicurezza…'),
        findsOneWidget,
      );
      expect(service.verifications, 1);
      fake.pending!.complete();
      await tester.runAsync(() async {
        await selected;
      });
      await tester.pumpAndSettle();
      expect(service.verifications, 2);
      expect(service.signCalls, 0);
      expect(service.paths[0], service.paths[1]);
      expect(
        find.text('Revoca: Non revocato secondo le prove consultate'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    },
  );

  for (final language in ['it', 'en']) {
    testWidgets(
      'consent dialog $language is explicit and dismissible without networking',
      (tester) async {
        bool? answer;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: CieLocalizations.supportedLocales,
            localizationsDelegates: const [
              CieLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  answer = await confirmTlsRecovery(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'it'
                ? 'Aggiornamento dei certificati di sicurezza'
                : 'Security certificate update',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            language == 'it'
                ? 'La lista dei certificati revocati'
                : 'The certificate revocation list',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'it' ? 'Consenti e riprova' : 'Allow and retry',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(language == 'it' ? 'Non ora' : 'Not now'));
        await tester.pumpAndSettle();
        expect(answer, false);
      },
    );
  }

  test(
    'live Windows Schannel requests use only public CIE services without a card',
    () async {
      final result = await TlsRecovery().recover(const SessionNetworkConfig());
      expect(result['ok'], true);
      expect(result['completedEndpoints'], 2);
    },
    skip:
        !Platform.isWindows ||
        Platform.environment['CIE_TLS_RECOVERY_LIVE'] != '1',
  );
}
