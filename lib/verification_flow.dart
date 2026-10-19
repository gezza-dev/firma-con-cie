// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'long_term_validation.dart';

class VerificationSaveRequest {
  const VerificationSaveRequest(this.suggestedName);
  final String suggestedName;
}

typedef VerificationSavePicker = Future<String?> Function(
  VerificationSaveRequest request,
);

// Document-only jobs are serialized. Cancellation invalidates publication, not
// the native worker: a late network result must never replace a newer document.
class VerificationController extends ChangeNotifier {
  VerificationController(this.service, {required this.canExtract});
  final CieService service;
  final bool Function() canExtract;
  String path = '';
  JsonResult? result, extraction;
  bool checking = false, exporting = false, extractable = false;
  int _generation = 0, _jobs = 0;
  bool _disposed = false;
  Future<void>? _tail;
  Directory? _retained;
  String? _snapshot;
  bool get running => _jobs > 0;
  Future<void> get settled => _tail ?? Future.value();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int ticket) => !_disposed && ticket == _generation;
  Future<void> _remove(Directory? folder) async {
    try {
      if (folder != null && await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } on FileSystemException {
      // Cleanup cannot turn a canceled job into a published verification result.
      // An inaccessible temporary directory may require later manual cleanup.
    }
  }

  Future<void> select(String value) {
    if (_disposed || exporting) return Future.value();
    final ticket = ++_generation;
    final old = _retained;
    _retained = null;
    _snapshot = null;
    path = value;
    result = null;
    extraction = null;
    extractable = false;
    checking = true;
    _jobs++;
    Future<void> run() async {
      Directory? folder;
      try {
        await _remove(old);
        if (!_current(ticket)) return;
        final source = File(value);
        final stat = await source.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size == 0 ||
            stat.size > 256 * 1024 * 1024 ||
            !RegExp(
              r'\.(pdf|p7m|p7s)$',
              caseSensitive: false,
            ).hasMatch(value)) {
          throw const FormatException('document_unreadable_or_too_large');
        }
        folder = await Directory.systemTemp.createTemp('cie-verify-');
        if (!Platform.isWindows) {
          final protected = await Process.run('/bin/chmod', [
            '700',
            folder.path,
          ]);
          if (protected.exitCode != 0) {
            throw const FileSystemException('snapshot_protection_failed');
          }
        }
        final snapshot = File('${folder.path}/${source.uri.pathSegments.last}');
        await source.openRead(0, stat.size).pipe(snapshot.openWrite());
        if (await snapshot.length() != stat.size ||
            !await sameDocumentBytes(source, snapshot)) {
          throw const FormatException('document_changed');
        }
        if (!_current(ticket)) return;
        var verified = await service.verify(snapshot.path);
        if (!_current(ticket)) return;
        var readableCms = false;
        if (canExtract() && value.toLowerCase().endsWith('.p7m')) {
          // Structural extraction also works when certificate trust or signature
          // integrity failed. This private probe is never opened or published.
          try {
            final probe = await service.extract(
              snapshot.path,
              '${folder.path}/contenuto',
            );
            readableCms = probe['ok'] == true;
          } catch (_) {
            readableCms = false;
          }
        }
        if (!_current(ticket)) return;
        if (!await sameDocumentBytes(source, snapshot)) {
          throw const FormatException('document_changed');
        }
        final nativeSigners = verified['signers'] as List? ?? [];
        final ltv = verified['ltv'];
        final archived = ltv is Map && ltv['ok'] == true
            ? ltv['signatures'] as List? ?? []
            : [];
        if (verified['ok'] == true &&
            nativeSigners.isEmpty &&
            archived.isEmpty &&
            verified['signatureCount'] == 0) {
          // A parser failure/partial DSS fallback is not evidence of an unsigned document.
          final pdf = value.toLowerCase().endsWith('.pdf')
              ? await service.pdfInfo(snapshot.path, 0)
              : null;
          if (!_current(ticket)) return;
          if (verified['nativeVerification'] is Map ||
              (pdf?['ok'] != true && !readableCms)) {
            verified = {
              'ok': false,
              'code': 'document_unreadable',
              'message': 'Documento non leggibile o formato non supportato.',
            };
          }
        }
        if (!_current(ticket)) return;
        result = verified;
        extractable = readableCms;
        _retained = folder;
        _snapshot = snapshot.path;
        folder = null;
      } on FormatException catch (e) {
        if (_current(ticket)) result = {'ok': false, 'code': e.message};
      } on FileSystemException {
        if (_current(ticket)) {
          result = {'ok': false, 'code': 'document_unreadable'};
        }
      } catch (_) {
        if (_current(ticket)) {
          result = {'ok': false, 'code': 'verification_failed'};
        }
      } finally {
        await _remove(folder);
        if (_current(ticket)) checking = false;
        _jobs--;
        _changed();
      }
    }

    final previous = _tail;
    final job = previous == null ? run() : previous.then((_) => run());
    // Keep the queue usable even after a cleanup failure; never retry a job.
    _tail = job.catchError((Object _) {});
    _changed();
    return _tail!;
  }

  bool cancel() {
    if (exporting || _disposed) return false;
    _generation++;
    final old = _retained;
    _retained = null;
    _snapshot = null;
    path = '';
    result = null;
    extraction = null;
    checking = false;
    extractable = false;
    _tail = _tail?.then((_) => _remove(old)) ?? _remove(old);
    _changed();
    return true;
  }

  Future<void> extract(VerificationSavePicker picker) async {
    if (_disposed ||
        running ||
        exporting ||
        !extractable ||
        _snapshot == null) {
      return;
    }
    final snapshot = _snapshot!, original = path, ticket = _generation;
    exporting = true;
    _jobs++;
    extraction = null;
    final done = Completer<void>();
    _tail = done.future;
    _changed();
    try {
      final destination = await picker(
        VerificationSaveRequest(extractedFileName(original)),
      );
      if (destination == null || !_current(ticket)) return;
      if (!await sameDocumentBytes(File(original), File(snapshot))) {
        result = {'ok': false, 'code': 'document_changed'};
        extractable = false;
        return;
      }
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        extraction = {
          'ok': false,
          'code': 'output_exists',
          'message': 'Scegli un nuovo nome: i file esistenti non vengono sovrascritti.',
        };
        return;
      }
      final saved = await service.extract(snapshot, destination);
      if (_current(ticket)) extraction = saved;
    } catch (_) {
      if (_current(ticket)) {
        extraction = {'ok': false, 'code': 'extraction_failed'};
      }
    } finally {
      exporting = false;
      _jobs--;
      done.complete();
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final old = _retained;
    _retained = null;
    unawaited(_tail?.then((_) => _remove(old)) ?? _remove(old));
    super.dispose();
  }
}
