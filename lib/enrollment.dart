// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'web_access.dart';

typedef WebStatusReader = Future<JsonResult> Function();
Future<JsonResult> readWebSystemStatus() async {
  if (!Platform.isMacOS) return {};
  const channel = MethodChannel('cie.prototype/web');
  try {
    return await channel.invokeMapMethod<String, dynamic>('status') ?? {};
  } on PlatformException {
    return {'available': false};
  } on MissingPluginException {
    return {'available': false};
  }
}

class EnrollmentRecord {
  static const componentActivationMessage =
      'Il certificato è configurato, ma il componente di sistema per l’accesso ai siti non è ancora attivo su questo computer. Puoi già firmare documenti. Non occorre ripetere il PIN o abbinare nuovamente la CIE.';
  EnrollmentRecord(this.data, this.system);
  final JsonResult data, system;
  String get id => data['card'] as String;
  String get name => data['fullName'] as String? ?? '';
  String get cardNumber => data['cardNumber'] as String? ?? '';
  bool get readyForSigning => data['readyForSigning'] == true;
  bool get hasPublicData => data['publicDataSaved'] == true;
  bool get componentAvailable =>
      system['available'] as bool? ?? data['systemComponentAvailable'] == true;
  bool get webProvisioned =>
      system['certificateHexByCard'] is Map &&
          hasPublicData &&
          (system['certificateHexByCard'] as Map)[id] != data['certificateHex']
      ? false
      : system.containsKey('publishedCards')
      ? (system['publishedCards'] as List).contains(id)
      : data['webProvisioned'] == true;
  bool get identityObserved =>
      webProvisioned &&
      (system.containsKey('observedCards')
          ? (system['observedCards'] as List).contains(id)
          : data['webIdentityObserved'] == true);
  // Home describes available actions, never absence of a diagnostic observation.
  String get status => !readyForSigning
      ? 'Abbinamento per la firma da completare.'
      : 'CIE abbinata. Puoi firmare documenti.';
  String get webStatus => !hasPublicData
      ? 'Completa l’abbinamento per accedere ai siti.'
      : !webProvisioned
      ? 'Completa la configurazione per accedere ai siti.'
      : !componentAvailable
      ? 'Accesso ai siti da attivare. Consulta Impostazioni → Log.'
      : 'Accesso ai siti configurato: apri il sito nel browser.';
  Map<String, bool> get diagnosticFlags => {
    'readyForSigning': readyForSigning,
    'publicDataSaved': hasPublicData,
    'webCertificatePublished': webProvisioned,
    'systemComponentAvailable': componentAvailable,
    'webIdentityObserved': identityObserved,
  };
}

class EnrollmentController {
  EnrollmentController(
    this.service, {
    this.publisher = publishWebCertificate,
    this.systemStatus = readWebSystemStatus,
  });
  final EnrollmentService service;
  final WebPublisher publisher;
  final WebStatusReader systemStatus;
  Map<String, EnrollmentRecord> records = {};
  bool readable = false;
  String? message;
  Future<void> refresh() async {
    final result = await service.enrollments();
    final invalidated = Set<String>.from(
      result['invalidatedCards'] as List? ?? [],
    );
    records.removeWhere((id, _) => invalidated.contains(id));
    readable = result['ok'] == true;
    if (!readable) {
      message = 'Archivio protetto non leggibile. Gli abbinamenti esistenti non vengono modificati.';
      return;
    }
    final nativeSystem = await service.webStatus();
    final platform = await systemStatus();
    final system = {...nativeSystem, ...platform};
    final next = <String, EnrollmentRecord>{};
    for (final raw in result['records'] as List? ?? []) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data['card'];
      if (id is! String || !RegExp(r'^[A-Za-z0-9]{1,63}$').hasMatch(id)) {
        continue;
      }
      if (!invalidated.contains(id)) next[id] = EnrollmentRecord(data, system);
    }
    // Old Web-only configurations remain visible/removable, never silently
    // converted to PIN pairings or imported from the original application.
    for (final id in {
      ...(system['configuredCards'] as List? ?? []),
      ...(system['publishedCards'] as List? ?? []),
    }) {
      if (id is String &&
          !invalidated.contains(id) &&
          RegExp(r'^[A-Za-z0-9]{1,63}$').hasMatch(id)) {
        next.putIfAbsent(id, () => EnrollmentRecord({'card': id}, system));
      }
    }
    // Legacy Web-only metadata was authenticated by the prototype previously.
    // Recover display name/printed number only. Never upgrade pairing/trust/public-data flags.
    if (service is CertificateNameService) {
      final certificates = system['certificateHexByCard'];
      for (final record in next.values) {
        if (record.name.trim().isNotEmpty && record.cardNumber.isNotEmpty) {
          continue;
        }
        final hex =
            record.data['certificateHex'] ??
            (certificates is Map ? certificates[record.id] : null);
        if (hex is! String ||
            hex.length > 16384 ||
            !RegExp(r'^(?:[a-fA-F0-9]{2})+$').hasMatch(hex)) {
          continue;
        }
        final parsed = await (service as CertificateNameService)
            .certificateName(hex);
        if (parsed['ok'] == true) {
          if (record.name.trim().isEmpty && parsed['fullName'] is String) {
            record.data['fullName'] = parsed['fullName'];
          }
          if (parsed['cardNumber'] is String) {
            record.data['cardNumber'] = parsed['cardNumber'];
          }
        }
      }
    }
    records = next;
  }

  Future<void> refreshSystem() async {
    final native = await service.webStatus();
    final platform = await systemStatus();
    final system = {...native, ...platform};
    records = records.map(
      (id, record) => MapEntry(id, EnrollmentRecord(record.data, system)),
    );
  }

  Future<JsonResult> _publish(JsonResult result, String id) async {
    if (result['ok'] != true) {
      message =
          result['message'] as String? ??
          'Abbinamento non completato. Nessun nuovo tentativo automatico.';
      await refresh();
      return result;
    }
    if (result['code'] == null) {
      final hex = result['certificateHex'];
      if (hex is String &&
          hex.length <= 16384 &&
          RegExp(r'^(?:[a-f0-9]{2})+$').hasMatch(hex)) {
        try {
          await publisher(id, hex);
        } catch (_) {
          message = 'CIE abbinata per firmare. Completa la configurazione per accedere ai siti; non occorre ripetere il PIN.';
        }
      } else {
        message = 'Dati pubblici non disponibili. Completa l’abbinamento su tua iniziativa.';
      }
    } else {
      message = result['code'] == 'web_certificate_conflict'
          ? 'Questo certificato è già associato a un altro componente di sistema. La configurazione Web di questa applicazione è stata interrotta senza modificare l’associazione esistente. Non occorre ripetere il PIN.'
          : result['message'] as String?;
    }
    await refresh();
    return result;
  }

  Future<JsonResult> enroll(String reader, String id, String pin) async {
    message = null;
    // Exactly one native call. Never chain pair() with enrollWeb(), and never
    // save a PIN closure/managed string for recovery after publication failure.
    final result = await service.enroll(reader, id, pin);
    pin = '';
    return _publish(result, id);
  }

  Future<JsonResult> complete(String id) async {
    message = null;
    final result = await _publish(await service.completeEnrollment(id), id);
    final record = records[id];
    if (result['ok'] == true &&
        message == null &&
        record?.webProvisioned == true) {
      message = record!.componentAvailable
          ? 'Certificato pubblico configurato per l’accesso ai siti. Apri il sito nel browser.'
          : EnrollmentRecord.componentActivationMessage;
    }
    return result;
  }

  Future<JsonResult> remove(String id) async {
    message = null;
    try {
      await publisher(id, null);
    } catch (_) {
      message = 'Rimozione dal sistema non completata. Riprova Rimuovi CIE senza PIN.';
      return {
        'ok': false,
        'code': 'enrollment_removal_incomplete',
        'message': message,
      };
    }
    final result = await service.forgetEnrollment(id);
    if (result['ok'] != true) {
      message =
          result['message'] as String? ??
          'Rimozione non completata. Puoi riprovare senza PIN.';
    }
    await refresh();
    return result;
  }
}
