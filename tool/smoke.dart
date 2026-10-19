// SPDX-License-Identifier: BSD-3-Clause
// Read-only real-backend smoke test. No PIN, login or signing operation.
import 'dart:convert';
import 'dart:io';

import 'package:cie_flutter_prototype/native_bridge.dart';

Future<void> main(List<String> args) async {
  final service = FfiCieService(BridgePaths.discover());
  final results = <String, dynamic>{
    'platform': Platform.operatingSystem,
    'dart': Platform.version,
    'hardwareSigningAttempted': false,
  };
  var failed = false;
  Future<JsonResult> verify(String path) => service.verify(path);
  final loaded = await service.load();
  results['load'] = loaded;
  if (loaded['ok'] != true) {
    stderr.writeln(jsonEncode(loaded));
    exitCode = 1;
    return;
  }
  final detected = await service.detect();
  final readers = (detected['readers'] as List? ?? []).cast<Map>();
  results['detection'] = {
    'ok': detected['ok'],
    'readerCount': readers.length,
    'cardsPresent': readers.where((r) => r['present'] == true).length,
    'cieRecognized': readers.where((r) => r['isCie'] == true).length,
    if (detected['code'] != null) 'code': detected['code'],
  };
  if (args.isNotEmpty) {
    final directory = Directory(args.first);
    final fixtures = <String, bool?>{
      'valid.pdf': true,
      'tampered.pdf': false,
      'two-signatures.pdf': true,
      'valid.p7m': true,
      'tampered.p7m': false,
      'unsigned.pdf': null,
    };
    final checks = <String, dynamic>{};
    for (final fixture in fixtures.entries) {
      final response = await verify('${directory.path}/${fixture.key}');
      final signers = (response['signers'] as List? ?? []).cast<Map>();
      final count = fixture.key == 'two-signatures.pdf'
          ? 2
          : fixture.value == null
          ? 0
          : 1;
      final passed =
          response['ok'] == true &&
          response['signatureCount'] == count &&
          signers.every(
            (s) =>
                s['signatureValid'] == fixture.value &&
                s['certificateWithinValidity'] == true &&
                s['revocationStatus'] == 3,
          ) &&
          response['trustChainValidated'] == false;
      checks[fixture.key] = {
        'passed': passed,
        'signatureCount': response['signatureCount'],
        'signatureValid': signers.map((s) => s['signatureValid']).toList(),
      };
      failed |= !passed;
    }
    final missing = await verify('${directory.path}/nonexistent.pdf');
    checks['missing_file'] =
        missing['ok'] == false && missing['code'] == 'input_missing';
    failed |= checks['missing_file'] != true;
    final recovered = await verify('${directory.path}/valid.pdf');
    checks['recovery'] =
        recovered['ok'] == true && recovered['signatureCount'] == 1;
    failed |= checks['recovery'] != true;
    results['fixtures'] = checks;
  }
  if (args.length > 1) {
    final response = await verify(args[1]);
    final signers = (response['signers'] as List? ?? []).cast<Map>();
    results['userDocument'] = {
      'ok': response['ok'],
      'signatureCount': response['signatureCount'],
      'signatures': signers
          .map(
            (s) => {
              'signatureValid': s['signatureValid'],
              'certificateWithinValidity': s['certificateWithinValidity'],
              'revocationStatus': s['revocationStatus'],
              'trustChainValidated': s['trustChainValidated'],
              'trustChainStatus': s['trustChainStatus'],
              'chainRevocationStatus': s['chainRevocationStatus'],
            },
          )
          .toList(),
    };
    failed |= response['ok'] != true;
  }
  final output = const JsonEncoder.withIndent('  ').convert(results);
  Directory('reports').createSync();
  File('reports/smoke-${Platform.operatingSystem}.json')
      .writeAsStringSync('$output\n');
  stdout.writeln(output);
  if (failed) exitCode = 1;
}
