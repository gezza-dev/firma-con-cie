// SPDX-License-Identifier: BSD-3-Clause
import 'dart:ffi';
import 'dart:io';

import 'app_settings.dart';
import 'native_bridge.dart';

// Explicit projection, never redaction of arbitrary strings or SDK messages.
class DiagnosticRecorder {
  AppDiagnosticLevel level = AppDiagnosticLevel.off;
  final List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> get events =>
      List.unmodifiable(_events.map(Map<String, dynamic>.unmodifiable));
  static const operations = {
    'load',
    'detect',
    'verify',
    'pdf_info',
    'extract',
    'sign',
    'sign_pdf',
    'change_pin',
    'unblock_pin',
    'network_probe',
    'enroll',
    'enrollments',
    'complete_enrollment',
    'forget_enrollment',
    'pair',
    'pairings',
    'unpair',
    'web_enroll',
    'web_forget',
    'web_test',
  };
  void clear() => _events.clear();
  void record(String operation, JsonResult result, int elapsedMs) {
    if (level == AppDiagnosticLevel.off ||
        !operations.contains(operation) ||
        (level == AppDiagnosticLevel.errors &&
            result['ok'] == true &&
            result['cleanupCode'] != 'pairing_store_cleanup_failed')) {
      return;
    }
    final event = <String, dynamic>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'operation': operation,
      'ok': result['ok'] == true,
      'elapsedMs': elapsedMs.clamp(0, 86400000),
    };
    // Only numeric transport codes, bounded counters and known outcome enums.
    for (final key in ['signatureCount', 'transportCode', 'httpStatus']) {
      final n = result[key];
      if (n is int && n >= 0 && n <= 10000) event[key] = n;
    }
    if (const {
      'not_started',
      'indeterminate',
      'completed',
    }.contains(result['outcome'])) {
      event['outcome'] = result['outcome'];
    }
    if (result['longTermValidation'] is Map) {
      event['archivalEngineAvailable'] =
          result['longTermValidation']['ok'] == true;
    }
    const codes = {
      'busy',
      'network_configuration_required',
      'native_unavailable',
      'network_unavailable',
      'network_ok',
      'network_failed',
      'network_config_invalid',
      'backend_missing',
      'input_missing',
      'verification_failed',
      'signer_failed',
      'cosign_input_invalid',
      'cosign_preservation_failed',
      'pin_incorrect',
      'pin_locked',
      'card_changed',
      'signing_failed',
      'output_invalid',
      'output_exists',
      'post_sign_verification_failed',
      'pdf_invalid',
      'appearance_unavailable',
      'output_publish_failed',
      'pin_operation_failed',
      'pin_operation_indeterminate',
      'pairing_invalidation_unavailable',
      'pairing_store_unavailable',
      'enrollment_removal_incomplete',
      'puk_incorrect',
      'puk_locked',
      'invalid_pin',
      'web_unavailable',
      'web_enrollment_failed',
      'web_store_unavailable',
      'web_certificate_conflict',
      'web_invalid_id',
      'web_system_test_failed',
      'invalid_puk',
      'invalid_new_pin',
      'invalid_format',
      'bridge_error',
      'operation_failed',
      'invalid_appearance',
    };
    if (result['ok'] != true) {
      event['code'] = codes.contains(result['code'])
          ? result['code']
          : 'unclassified_error';
    }
    if (operation == 'forget_enrollment' && result['ok'] != true) {
      final status = result['nativeCode'];
      if (status is int && status >= -2147483648 && status <= 4294967295) {
        event['nativeCode'] = status;
      }
      if (const {
        'web_certificate',
        'public_data',
        'pairing',
        'pairing_cache',
      }.contains(result['removalStage'])) {
        event['removalStage'] = result['removalStage'];
      }
    }
    if ((operation == 'change_pin' || operation == 'unblock_pin') &&
        result['cleanupCode'] == 'pairing_store_cleanup_failed') {
      event['cleanupCode'] = 'pairing_store_cleanup_failed';
      final status = result['cleanupNativeCode'];
      if (status is int && status >= -2147483648 && status <= 4294967295) {
        event['cleanupNativeCode'] = status;
      }
    }
    _events.add(event);
    if (_events.length > 200) _events.removeAt(0);
  }

  Map<String, dynamic> snapshot({
    required SessionNetworkConfig network,
    JsonResult? capabilities,
    List<Map<String, bool>>? webAccess,
    bool? enrollmentReadable,
  }) => {
    'schema': 1,
    'application': 'CIE ID',
    'prototypeVersion': '0.1.0',
    'operatingSystem': Platform.operatingSystem,
    'architecture': Abi.current().toString(),
    'proxyMode': network.proxy.mode.name,
    'proxyAuthenticationInSession': network.hasAuthentication,
    'diagnosticLevel': level.name,
    'retention': 'memory_only_last_200_events',
    'capabilities': {
      for (final key in [
        'ok',
        'canSign',
        'canChangePin',
        'canUnblockPin',
        'canSignPdfAppearance',
        'canCosign',
        'canExtract',
        'canConfigureNetwork',
      ])
        if (capabilities?[key] is bool) key: capabilities![key],
    },
    if (webAccess != null)
      'webAccess': {
        'enrollmentsReadable': ?enrollmentReadable,
        'cards': [
          for (final flags in webAccess.take(256))
            {
              for (final key in const [
                'removalPending',
                'readyForSigning',
                'publicDataSaved',
                'webCertificatePublished',
                'systemComponentAvailable',
                'webIdentityObserved',
              ])
                if (flags.containsKey(key)) key: flags[key],
            },
        ],
        'browserLoginTestedByStatusCheck': false,
      },
    'events': events,
  };
}

class DiagnosticCieService
    implements
        CieService,
        SigningInfoService,
        NetworkService,
        PairingService,
        WebAccessService,
        CardObservationService,
        CancellableCardObservation,
        EnrollmentService,
        CertificateNameService {
  DiagnosticCieService(this.delegate, this.recorder);
  final CieService delegate;
  final DiagnosticRecorder recorder;
  Future<JsonResult> _run(
    String op,
    Future<JsonResult> Function() action,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      recorder.record(op, result, watch.elapsedMilliseconds);
      return result;
    } catch (_) {
      recorder.record(op, {'ok': false}, watch.elapsedMilliseconds);
      rethrow;
    }
  }

  @override
  void blockNetworkConfiguration() {
    if (delegate is NetworkService) {
      (delegate as NetworkService).blockNetworkConfiguration();
    }
  }

  @override
  void setNetwork(SessionNetworkConfig config) {
    if (delegate is NetworkService) {
      (delegate as NetworkService).setNetwork(config);
    }
  }

  @override
  Future<JsonResult> probeNetwork(SessionNetworkConfig config) => _run(
    'network_probe',
    () => delegate is NetworkService
        ? (delegate as NetworkService).probeNetwork(config)
        : Future.value({'ok': false, 'code': 'network_unavailable'}),
  );
  Future<JsonResult> _pairing(
    String operation,
    Future<JsonResult> Function(PairingService) call,
  ) => _run(
    operation,
    () => delegate is PairingService
        ? call(delegate as PairingService)
        : Future.value({'ok': false, 'code': 'pairing_unavailable'}),
  );
  // Presence ticks contain no document or private operation. Do not fill the
  // diagnostic ring with periodic events (or retain any reader/card identity).
  @override
  Future<JsonResult> observeCards() => delegate is CardObservationService
      ? (delegate as CardObservationService).observeCards()
      : Future.value({'ok': false, 'code': 'observation_unavailable'});

  @override
  Future<void> cancelCardObservation() async {
    if (delegate is CancellableCardObservation) {
      await (delegate as CancellableCardObservation).cancelCardObservation();
    }
  }

  Future<JsonResult> _enrollment(
    String op,
    Future<JsonResult> Function(EnrollmentService) action,
  ) => _run(
    op,
    () => delegate is EnrollmentService
        ? action(delegate as EnrollmentService)
        : Future.value({'ok': false, 'code': 'enrollment_unavailable'}),
  );
  @override
  Future<JsonResult> enroll(String reader, String card, String fullPin) =>
      _enrollment('enroll', (s) => s.enroll(reader, card, fullPin));
  @override
  Future<JsonResult> enrollments() =>
      _enrollment('enrollments', (s) => s.enrollments());
  @override
  Future<JsonResult> completeEnrollment(String card) =>
      _enrollment('complete_enrollment', (s) => s.completeEnrollment(card));
  @override
  Future<JsonResult> forgetEnrollment(String card) =>
      _enrollment('forget_enrollment', (s) => s.forgetEnrollment(card));
  @override
  Future<JsonResult> webStatus() => delegate is EnrollmentService
      ? (delegate as EnrollmentService).webStatus()
      : Future.value({'ok': false});
  @override
  Future<JsonResult> pairings() => _pairing('pairings', (p) => p.pairings());
  @override
  Future<JsonResult> pair(String reader, String card, String fullPin) =>
      _pairing('pair', (p) => p.pair(reader, card, fullPin));
  @override
  Future<JsonResult> unpair(String card) =>
      _pairing('unpair', (p) => p.unpair(card));
  @override
  Future<JsonResult> enrollWeb(String reader, String card, String fullPin) =>
      _run(
        'web_enroll',
        () => delegate is WebAccessService
            ? (delegate as WebAccessService).enrollWeb(reader, card, fullPin)
            : Future.value({'ok': false, 'code': 'web_unavailable'}),
      );
  @override
  Future<JsonResult> forgetWeb(String card) => _run(
    'web_forget',
    () => delegate is WebAccessService
        ? (delegate as WebAccessService).forgetWeb(card)
        : Future.value({'ok': false, 'code': 'web_unavailable'}),
  );
  @override
  Future<JsonResult> testWeb(String card) => _run(
    'web_test',
    () => delegate is WebAccessService
        ? (delegate as WebAccessService).testWeb(card)
        : Future.value({'ok': false, 'code': 'web_unavailable'}),
  );

  @override
  Future<JsonResult> load() => _run('load', delegate.load);
  @override
  Future<JsonResult> detect() => _run('detect', delegate.detect);
  @override
  Future<JsonResult> verify(String path) =>
      _run('verify', () => delegate.verify(path));
  @override
  Future<JsonResult> signingInfo(String path) async {
    if (delegate is SigningInfoService) {
      return _run(
        'signing_info',
        () => (delegate as SigningInfoService).signingInfo(path),
      );
    }
    // Older runtimes cannot safely offer co-signing. PDF parser remains authoritative.
    final info = await pdfInfo(path, 0);
    return {
      'ok': true,
      'pdfSupported': info['ok'] == true,
      'cosignSupported': false,
    };
  }

  @override
  Future<JsonResult> pdfInfo(String path, int page) =>
      _run('pdf_info', () => delegate.pdfInfo(path, page));
  @override
  Future<JsonResult> extract(String input, String output) =>
      _run('extract', () => delegate.extract(input, output));
  @override
  Future<JsonResult> sign({
    required String reader,
    required String card,
    required String input,
    required String output,
    required String format,
    required String pin,
    PdfAppearance? appearance,
    bool replaceExisting = false,
  }) => _run(
    appearance == null ? 'sign' : 'sign_pdf',
    () => delegate.sign(
      reader: reader,
      card: card,
      input: input,
      output: output,
      format: format,
      pin: pin,
      appearance: appearance,
      replaceExisting: replaceExisting,
    ),
  );
  @override
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  }) => _run(
    unblock ? 'unblock_pin' : 'change_pin',
    () => delegate.updatePin(
      reader: reader,
      card: card,
      authentication: authentication,
      newPin: newPin,
      unblock: unblock,
    ),
  );
  // Public personal data stays out of diagnostics, including certificate input.
  @override
  Future<JsonResult> certificateName(String hex) =>
      delegate is CertificateNameService
      ? (delegate as CertificateNameService).certificateName(hex)
      : Future.value({'ok': false});
}
