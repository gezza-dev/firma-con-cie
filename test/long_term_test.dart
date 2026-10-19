// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/long_term_validation.dart';
import 'package:cie_flutter_prototype/long_term_view.dart';
import 'package:cie_flutter_prototype/verification_view.dart';

Map<String, dynamic> response(Map<String, dynamic> signature) => {
  'ok': true,
  'schema': 1,
  'engine': 'EU DSS 6.5.1',
  'validationLevel': 'ARCHIVAL_DATA',
  'offline': true,
  'signatureCount': 1,
  'signatures': [signature],
  'allSignaturesLtaValid': true,
};
Map<String, dynamic> valid() => {
  'profile': 'PAdES-BASELINE-LTA',
  'indication': 'TOTAL_PASSED',
  'archiveIndication': 'PASSED',
  'latestArchiveValidated': true,
  'currentRevisionCovered': true,
  'unexpectedPdfChanges': false,
  'archiveTimestampCount': 2,
  'longTermStatus': 'passed',
};
void main() {
  test(
    'Windows DNS environment survives while Java injection stays excluded',
    () {
      for (final rootKey in ['SYSTEMROOT', 'SystemRoot', 'systemroot']) {
        final source = {
          rootKey: r'C:\Windows',
          'TEMP': r'C:\Temp',
          'JAVA_TOOL_OPTIONS': '-javaagent:untrusted.jar',
          '_JAVA_OPTIONS': '-Dhttps.proxyHost=untrusted',
          'HTTPS_PROXY': 'http://untrusted',
          'PATH': 'untrusted',
        };
        expect(ltvProcessEnvironment(source), {
          rootKey: r'C:\Windows',
          'TEMP': r'C:\Temp',
        });
      }
    },
  );
  test(
    'raw DSS success cannot authorize history without a verified timestamp',
    () {
      final result = decodeLtvResponse(
        jsonEncode({
          ...response({
            ...valid(),
            'historicalStatus': 'passed',
            'historicalReason': 'historical_certificate_status_verified',
            'historicalReferenceTime': '2020-12-10T11:19:57Z',
            'timestamps': [],
          }),
          'historicalPolicy': 'authenticated_crl_v1',
        }),
      );
      expect(
        (result['signatures'] as List).first['historicalStatus'],
        'indeterminate',
      );
    },
  );
  test(
    'bounded CRL mode is accepted and unknown revocation cannot claim LTA',
    () {
      final result = decodeLtvResponse(
        jsonEncode({
          ...response({
            ...valid(),
            'historicalStatus': 'passed',
            'historicalReason': 'revocation_reason_unknown',
          }),
          'offline': false,
          'historicalPolicy': 'authenticated_crl_v1',
          'crlRetrieval': {'enabled': true},
        }),
      );
      expect(result['ok'], true);
      expect(result['allSignaturesLtaValid'], false);
      final signature = (result['signatures'] as List).first;
      expect(signature['historicalStatus'], 'indeterminate');
      expect(signature['longTermStatus'], 'indeterminate');
      expect(
        decodeLtvResponse(
          jsonEncode({...response(valid()), 'offline': false}),
        )['ok'],
        false,
      );
    },
  );
  testWidgets('unknown revocation reason is visible as indeterminate history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LongTermView(
              result: response({
                ...valid(),
                'historicalStatus': 'indeterminate',
                'historicalReason': 'revocation_reason_unknown',
                'longTermStatus': 'no_archive_data',
                'archiveTimestampCount': 0,
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Validità storica non determinabile'), findsOneWidget);
    expect(
      find.textContaining('Il motivo della revoca non è riconosciuto'),
      findsOneWidget,
    );
    expect(
      find.text('Validità storica verificata alla data della marca'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  test('archival verdict needs more than a detected LTA profile', () {
    final fake = response({...valid(), 'indication': 'INDETERMINATE'});
    expect(decodeLtvResponse(jsonEncode(fake))['allSignaturesLtaValid'], false);
    expect(
      decodeLtvResponse(jsonEncode(response(valid())))['allSignaturesLtaValid'],
      true,
    );
  });
  test('unsigned revisions and missing archive proof never pass', () {
    for (final patch in [
      {'currentRevisionCovered': false},
      {'latestArchiveValidated': false},
      {'unexpectedPdfChanges': true},
      {'archiveTimestampCount': 0},
    ]) {
      expect(
        decodeLtvResponse(
          jsonEncode(response({...valid(), ...patch})),
        )['allSignaturesLtaValid'],
        false,
      );
    }
  });
  test('malformed or stale worker results cannot claim success', () {
    expect(decodeLtvResponse('invalid json')['ok'], false);
    expect(
      decodeLtvResponse(
        jsonEncode({...response(valid()), 'signatureCount': 2}),
      )['ok'],
      false,
    );
    expect(
      decodeLtvResponse(
        jsonEncode({
          ...response(valid()),
          'validationLevel': 'BASIC_SIGNATURES',
        }),
      )['ok'],
      false,
    );
  });
  test(
    'absent private JVM is an unavailable check, not a positive verdict',
    () async {
      final folder = await Directory.systemTemp.createTemp('cie-ltv-missing-');
      try {
        final result = await LongTermValidator(folder)
            .verify('not-a-document.pdf');
        expect(result['code'], 'ltv_runtime_missing');
        expect(result['allSignaturesLtaValid'], false);
      } finally {
        await folder.delete();
      }
    },
  );
  test('both engines use one snapshot and reject a changed original', () async {
    final folder = await Directory.systemTemp.createTemp('cie-snapshot-test-');
    final source = File('${folder.path}/example.pdf');
    await source.writeAsString('original bytes');
    String? usedSnapshot;
    try {
      final result = await verifyDocumentSnapshot(
        source.path,
        native: (path) async {
          usedSnapshot = path;
          expect(path, isNot(source.path));
          expect(await File(path).readAsString(), 'original bytes');
          await source.writeAsString('changed bytes');
          return {'ok': true};
        },
        archival: (path) async {
          expect(path, usedSnapshot);
          expect(await File(path).readAsString(), 'original bytes');
          return response(valid());
        },
      );
      expect(result['code'], 'document_changed');
      expect(await File(usedSnapshot!).exists(), false);
    } finally {
      await folder.delete(recursive: true);
    }
  });
  test('snapshot is removed when an engine fails', () async {
    final folder = await Directory.systemTemp.createTemp('cie-snapshot-error-');
    final source = File('${folder.path}/example.p7m');
    await source.writeAsString('synthetic');
    String? snapshot;
    try {
      await expectLater(
        verifyDocumentSnapshot(
          source.path,
          native: (path) async {
            snapshot = path;
            throw StateError('fixture failure');
          },
          archival: (_) async => response(valid()),
        ),
        throwsStateError,
      );
      expect(await File(snapshot!).exists(), false);
      expect(await source.readAsString(), 'synthetic');
    } finally {
      await folder.delete(recursive: true);
    }
  });
  testWidgets(
    'detected LTA profile with insufficient proof is visibly indeterminate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LongTermView(
                result: response({
                  ...valid(),
                  'longTermStatus': 'indeterminate',
                  'indication': 'INDETERMINATE',
                }),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Validità a lungo termine non determinabile'),
        findsOneWidget,
      );
      expect(
        find.text('Validazione LTA superata secondo la policy locale'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('archival success remains separate from eIDAS qualification', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VerificationView(
              result: {
                'ok': true,
                'signatureCount': 1,
                'signers': <Map>[],
                'documentTimestampCount': 2,
                'documentTimestampStatus': 'indeterminate',
                'ltv': response(valid()),
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Validità storica e a lungo termine'));
    await tester.pumpAndSettle();
    expect(
      find.text('Validazione LTA superata secondo la policy locale'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('non attesta la qualificazione eIDAS'),
      findsOneWidget,
    );
    expect(find.textContaining('Marche del documento PDF:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
