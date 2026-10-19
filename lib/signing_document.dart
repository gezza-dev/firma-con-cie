// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

// A private immutable input for format preflight, preview and the one signing
// operation. Changing the source afterwards cannot change the bytes signed.
class SigningDocument {
  SigningDocument._(this.directory, this.path);
  final Directory directory;
  final String path;
  static Future<SigningDocument> capture(String source) async {
    final original = File(source);
    if (!await original.exists()) {
      throw const FormatException(
        'Selezionare un file leggibile, non una cartella.',
      );
    }
    final before = await original.stat();
    if (before.size == 0 || before.size > 256 * 1024 * 1024) {
      throw const FormatException(
        'Documento vuoto o troppo grande (massimo 256 MiB).',
      );
    }
    final directory = await Directory.systemTemp.createTemp('cie-signing-');
    try {
      if (!Platform.isWindows) {
        final result = await Process.run('/bin/chmod', ['700', directory.path]);
        if (result.exitCode != 0) {
          throw const FileSystemException('Cartella temporanea non protetta');
        }
      }
      final extension = source.toLowerCase().endsWith('.p7m') ? '.p7m' : '.pdf';
      final copy = await original.copy('${directory.path}/documento$extension');
      final after = await original.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          await copy.length() != before.size) {
        throw const FormatException(
          'Il documento è cambiato durante la lettura. Selezionalo di nuovo.',
        );
      }
      return SigningDocument._(directory, copy.path);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

enum SigningStep { card, document, format, appearance, pin, result }

class SignedFileRequest {
  const SignedFileRequest(this.suggestedName, this.extension);
  final String suggestedName, extension;
}

typedef SignedFilePicker = Future<String?> Function(SignedFileRequest request);

// Saving a cryptographically intact artifact is distinct from establishing
// current certificate trust/revocation. Missing fields never imply success.
String signedResultSummary(Object? verification) {
  if (verification is! Map ||
      verification['ok'] != true ||
      verification['signers'] is! List ||
      (verification['signers'] as List).isEmpty) {
    return 'Il file è stato salvato. Verifica successiva non completata: consulta i dettagli prima di fare affidamento sulla firma.';
  }
  final signers = (verification['signers'] as List);
  for (final signer in signers.whereType<Map>()) {
    if (signer['signatureValid'] == false ||
        signer['certificateWithinValidity'] == false ||
        const ['untrusted', 'invalid'].contains(signer['trustChainStatus']) ||
        const [1, 2].contains(signer['revocationStatus']) ||
        const [1, 2].contains(signer['chainRevocationStatus'])) {
      return 'Il file è stato salvato, ma la verifica segnala problemi di integrità o del certificato. Consulta i dettagli prima di fare affidamento sulla firma.';
    }
  }
  if (signers.any(
    (s) =>
        s is! Map ||
        s['signatureValid'] != true ||
        s['certificateWithinValidity'] != true ||
        s['trustChainValidated'] != true ||
        s['trustChainStatus'] != 'trusted' ||
        s['revocationStatus'] != 0 ||
        s['chainRevocationStatus'] != 0,
  )) {
    return 'Il file è stato salvato. Verifica non conclusa: catena di fiducia o stato di revoca non completamente determinati. Consulta i dettagli.';
  }
  return 'Il file è stato salvato e i controlli correnti su certificati, catena e revoca sono completati. Marche temporali e validità storica hanno esiti separati nei dettagli.';
}
