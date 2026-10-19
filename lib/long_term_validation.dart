// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'network_settings.dart';

// Windows may expose SYSTEMROOT rather than SystemRoot. Keep required OS
// variables regardless of casing, without inheriting Java agents or proxies.
Map<String, String> ltvProcessEnvironment(Map<String, String> source) => {
  for (final entry in source.entries)
    if (const {
      'SYSTEMROOT',
      'WINDIR',
      'TEMP',
      'TMP',
      'HOME',
      'LANG',
      'LC_ALL',
    }.contains(entry.key.toUpperCase()))
      entry.key: entry.value,
};

Map<String, dynamic> ltvUnavailable(String code) => {
  'ok': false,
  'schema': 1,
  'code': code,
  'allSignaturesLtaValid': false,
};

Map<String, dynamic> decodeLtvResponse(String output) {
  try {
    final result = Map<String, dynamic>.from(jsonDecode(output) as Map);
    if (result['schema'] != 1 || result['ok'] != true) {
      return ltvUnavailable('ltv_validation_failed');
    }
    final signatures = (result['signatures'] as List).cast<Map>();
    if (result['engine'] != 'EU DSS 6.5.1' ||
        result['validationLevel'] != 'ARCHIVAL_DATA' ||
        (result['offline'] != true &&
            !(result['offline'] == false &&
                result['historicalPolicy'] == 'authenticated_crl_v1' &&
                result['crlRetrieval'] is Map &&
                result['crlRetrieval']['enabled'] == true)) ||
        result['signatureCount'] != signatures.length ||
        signatures.length > 128) {
      return ltvUnavailable('ltv_response_invalid');
    }
    for (final signature in signatures) {
      // A raw DSS indication alone must never authorize historical validity.
      if (signature['historicalReason'] == 'revocation_reason_unknown') {
        signature['historicalStatus'] = 'indeterminate';
        if (signature['longTermStatus'] == 'passed') {
          signature['longTermStatus'] = 'indeterminate';
        }
      }
      final verifiedTimestamp = (signature['timestamps'] as List? ?? []).any(
        (t) =>
            t is Map &&
            t['type'] == 'SIGNATURE_TIMESTAMP' &&
            t['time'] == signature['historicalReferenceTime'] &&
            t['imprintIntact'] == true &&
            t['archivalIndication'] == 'PASSED',
      );
      if (signature['historicalStatus'] == 'passed' &&
          (result['historicalPolicy'] != 'authenticated_crl_v1' ||
              signature['indication'] != 'TOTAL_PASSED' ||
              signature['historicalReferenceTime'] is! String ||
              '${signature['historicalReferenceTime']}'.isEmpty ||
              !verifiedTimestamp)) {
        signature['historicalStatus'] = 'indeterminate';
        signature['historicalReason'] = 'historical_response_inconsistent';
      }
    }
    // Never promote a detected profile or a general TOTAL_PASSED to LTA validity.
    result['allSignaturesLtaValid'] =
        signatures.isNotEmpty &&
        signatures.every(
          (s) =>
              s['longTermStatus'] == 'passed' &&
              s['indication'] == 'TOTAL_PASSED' &&
              s['archiveIndication'] == 'PASSED' &&
              s['latestArchiveValidated'] == true &&
              s['currentRevisionCovered'] == true &&
              s['unexpectedPdfChanges'] == false &&
              s['historicalReason'] != 'revocation_reason_unknown' &&
              '${s['profile']}'.endsWith('BASELINE-LTA') &&
              s['archiveTimestampCount'] is int &&
              s['archiveTimestampCount'] > 0,
        );
    return result;
  } catch (_) {
    return ltvUnavailable('ltv_response_invalid');
  }
}

class LongTermValidator {
  LongTermValidator(this.folder);
  final Directory folder;
  factory LongTermValidator.fromBridge(String bridge) {
    final native = File(bridge).absolute.parent;
    final adjacent = Directory('${native.path}/ltv');
    return LongTermValidator(
      adjacent.existsSync()
          ? adjacent
          : Directory(
              '${native.parent.parent.path}/Resources/CIEPrototype/ltv',
            ),
    );
  }
  Future<Map<String, dynamic>> verify(
    String document, {
    SessionNetworkConfig network = const SessionNetworkConfig(),
  }) async {
    network.validate();
    final platform = Platform.isWindows
        ? 'windows-x86_64'
        : Abi.current() == Abi.macosArm64
        ? 'macos-arm64'
        : 'macos-x86_64';
    final java = File(
      '${folder.path}/jre/$platform/bin/java${Platform.isWindows ? '.exe' : ''}',
    );
    if (!java.existsSync() ||
        !File('${folder.path}/cie-ltv-worker.jar').existsSync()) {
      return ltvUnavailable('ltv_runtime_missing');
    }
    Process? process;
    try {
      final separator = Platform.isWindows ? ';' : ':';
      // No shell, no inherited Java agent/options/proxy settings. The worker has
      // only bounded CRL GETs through the private C++ helper; no document upload.
      process = await Process.start(
        java.path,
        [
          '-Xms32m',
          '-Xmx512m',
          '-Djava.awt.headless=true',
          '-Dfile.encoding=UTF-8',
          '-cp',
          '${folder.path}/cie-ltv-worker.jar$separator${folder.path}/lib/*',
          'it.cieid.ltv.Worker',
          File(document).absolute.path,
          '${folder.path}/trust',
          '${folder.path}/fetcher/cie_crl_fetch${Platform.isWindows ? '.exe' : ''}',
          '--network-stdin',
        ],
        includeParentEnvironment: false,
        environment: ltvProcessEnvironment(Platform.environment),
      );
      process.stdin.add(utf8.encode(network.toWire()));
      await process.stdin.close();
      var total = 0;
      final output = process.stdout.fold<List<int>>(<int>[], (bytes, chunk) {
        total += chunk.length;
        if (total > 4 * 1024 * 1024) {
          process?.kill();
          throw const FormatException('ltv_output_limit');
        }
        return bytes..addAll(chunk);
      });
      // Discard library diagnostics: they may contain certificate identities.
      final diagnostics = process.stderr.drain<void>();
      final completed = await Future.wait<Object>([
        process.exitCode,
        output,
        diagnostics.then((_) => true),
      ]).timeout(const Duration(seconds: 90));
      final exit = completed[0] as int;
      final bytes = completed[1] as List<int>;
      if (exit != 0) return ltvUnavailable('ltv_worker_failed');
      return decodeLtvResponse(utf8.decode(bytes));
    } on TimeoutException {
      await _stopWorker(process);
      return ltvUnavailable('ltv_timeout');
    } catch (_) {
      await _stopWorker(process);
      return ltvUnavailable('ltv_worker_failed');
    }
  }
}

Future<void> _stopWorker(Process? process) async {
  if (process == null) return;
  process.kill();
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}

Future<bool> sameDocumentBytes(File original, File snapshot) async {
  RandomAccessFile? first, second;
  try {
    first = await original.open();
    second = await snapshot.open();
    if (await first.length() != await second.length()) return false;
    while (true) {
      final a = await first.read(64 * 1024);
      final b = await second.read(64 * 1024);
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      if (a.isEmpty) return true;
    }
  } on FileSystemException {
    return false;
  } finally {
    await first?.close();
    await second?.close();
  }
}

/// Both engines read one private snapshot. Reject results if the original has
/// changed, and remove the snapshot on success, error or worker timeout.
Future<Map<String, dynamic>> verifyDocumentSnapshot(
  String document, {
  required Future<Map<String, dynamic>> Function(String) native,
  required Future<Map<String, dynamic>> Function(String) archival,
}) async {
  final source = File(document).absolute;
  final info = await source.stat();
  if (info.type != FileSystemEntityType.file ||
      info.size == 0 ||
      info.size > 256 * 1024 * 1024) {
    return {
      'ok': false,
      'code': 'document_unreadable_or_too_large',
      'message': 'Selezionare un documento leggibile di dimensioni non superiori a 256 MiB.',
    };
  }
  final folder = await Directory.systemTemp.createTemp('cie-document-');
  try {
    final snapshot = File('${folder.path}/${source.uri.pathSegments.last}');
    // Bound the copy to the initial size even if a source is being appended to.
    await source.openRead(0, info.size).pipe(snapshot.openWrite());
    if (await snapshot.length() != info.size) {
      throw const FileSystemException('document_copy_incomplete');
    }
    final current = await native(snapshot.path);
    final ltv = await archival(snapshot.path);
    if (!await sameDocumentBytes(source, snapshot)) {
      return {
        'ok': false,
        'code': 'document_changed',
        'message': 'Il documento è cambiato durante la verifica. Ripeti il controllo sul file aggiornato.',
      };
    }
    if (current['ok'] != true && ltv['ok'] == true) {
      return {
        'ok': true,
        'signatureCount': ltv['signatureCount'],
        'signers': <Map>[],
        'nativeVerification': current,
        'ltv': ltv,
        'verificationUsesSnapshot': true,
      };
    }
    return {...current, 'ltv': ltv, 'verificationUsesSnapshot': true};
  } finally {
    await folder.delete(recursive: true);
  }
}
