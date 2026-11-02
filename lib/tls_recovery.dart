// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'native_bridge.dart';
import 'network_settings.dart';
import 'linux_ca_update.dart';

typedef TlsCommand = Future<(int, String)> Function(
  String executable,
  List<String> arguments,
  String input,
);

// Use the platform's trusted TLS client and its own certificate mechanisms.
// A CRL is never imported as a CA, and no document/certificate URL is accepted.
class TlsRecovery {
  TlsRecovery({
    bool? enabled,
    TlsCommand? command,
    this.executable,
    String? operatingSystem,
    Future<bool> Function(String)? exists,
    LinuxCaUpdater? linuxUpdater,
  }) : operatingSystem = operatingSystem ?? Platform.operatingSystem,
       enabled =
           enabled ??
           const [
             'windows',
             'macos',
             'linux',
           ].contains(operatingSystem ?? Platform.operatingSystem),
       _exists = exists ?? _pathExists,
       _linuxUpdater = linuxUpdater ?? LinuxCaUpdater(),
       _command = command ?? _execute;

  final bool enabled;
  final TlsCommand _command;
  final String? executable;
  final String operatingSystem;
  final Future<bool> Function(String) _exists;
  final LinuxCaUpdater _linuxUpdater;
  bool _offered = false;
  static const endpoints = [
    'https://www.cartaidentita.interno.gov.it/',
    'https://ldap.cie.interno.gov.it/cierootca.crl',
  ];

  static bool needsRecovery(JsonResult result) {
    if (result['transportCode'] == 60) return true;
    if (result['ok'] != true) return false;
    return (result['signers'] as List? ?? []).whereType<Map>().any(
      (s) =>
          s['trustChainStatus'] == 'trusted' &&
          s['trustSource'] == 'cie_ministry' &&
          ![1, 2].contains(s['revocationStatus']) &&
          ![1, 2].contains(s['chainRevocationStatus']) &&
          (s['revocationStatus'] == 3 || s['chainRevocationStatus'] == 3),
    );
  }

  Future<JsonResult> retry({
    required JsonResult original,
    required SessionNetworkConfig network,
    required Future<bool> Function() consent,
    required Future<JsonResult> Function() verify,
    required bool Function() isCurrent,
    required void Function(JsonResult) record,
    required Future<void> Function(bool) onRecovery,
  }) async {
    if (!enabled || _offered || !isCurrent() || !needsRecovery(original)) {
      return original;
    }
    _offered = true; // Declining/canceling must not open a dialog on every job.
    try {
      if (!await consent() || !isCurrent()) return original;
      await onRecovery(true);
      JsonResult recovered;
      final watch = Stopwatch()..start();
      try {
        recovered = await recover(
          network,
          allowLinuxUpdate: true,
          tlsFailureObserved: original['transportCode'] == 60,
          isCurrent: isCurrent,
        );
        record({...recovered, 'elapsedMs': watch.elapsedMilliseconds});
      } finally {
        await onRecovery(false);
      }
      // Transport success is not evidence about document trust or revocation.
      if (!isCurrent() ||
          (recovered['completedEndpoints'] == 0 &&
              recovered['caUpdateCompleted'] != true)) {
        return original;
      }
      final checked = await verify();
      if (original['ok'] == true && checked['ok'] != true) return original;
      return isCurrent() ? checked : original;
    } catch (_) {
      // An optional repair must never erase the original verification result.
      return original;
    }
  }

  static const linuxCaFiles = [
    '/etc/ssl/certs/ca-certificates.crt',
    '/etc/pki/tls/certs/ca-bundle.crt',
    '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
    '/etc/ssl/ca-bundle.pem',
  ];

  Future<JsonResult> recover(
    SessionNetworkConfig network, {
    bool allowLinuxUpdate = false,
    bool tlsFailureObserved = false,
    bool Function()? isCurrent,
  }) async {
    network.validate();
    final initial = await _probe(network);
    if (initial['ok'] == true ||
        operatingSystem != 'linux' ||
        !allowLinuxUpdate ||
        isCurrent?.call() == false ||
        !((tlsFailureObserved &&
                initial['code'] == 'tls_system_client_unavailable') ||
            initial['transportCode'] == 60 ||
            initial['transportCode'] == 77 ||
            initial['caStoreMissing'] == true)) {
      return initial;
    }
    final update = await _linuxUpdater.update(isCurrent: isCurrent);
    if (update['ok'] != true) {
      return {
        ...initial,
        ...update,
        'ok': false,
        'completedEndpoints': initial['completedEndpoints'] ?? 0,
        'caUpdateAttempted': true,
      };
    }
    final checked = isCurrent?.call() == false
        ? initial
        : await _probe(network);
    return {...checked, 'caUpdateAttempted': true, 'caUpdateCompleted': true};
  }

  Future<JsonResult> _probe(SessionNetworkConfig network) async {
    network.validate();
    String? caFile;
    var caDirectory = false;
    if (operatingSystem == 'linux') {
      for (final name in linuxCaFiles) {
        if (await _exists(name)) {
          caFile = name;
          break;
        }
      }
      caDirectory = await _exists('/etc/ssl/certs');
      if (caFile == null && !caDirectory) {
        return {
          'ok': false,
          'code': 'tls_ca_store_missing',
          'transportCode': 77,
          'completedEndpoints': 0,
          'caStoreMissing': true,
        };
      }
    }
    try {
      final executable =
          this.executable ??
          (operatingSystem == 'windows' ? _systemCurl() : '/usr/bin/curl');
      final version = await _command(executable, ['-q', '--version'], '');
      final nativeClient = switch (operatingSystem) {
        'windows' => version.$2.contains('Schannel'),
        'macos' =>
          version.$2.contains('SecureTransport') ||
              version.$2.contains('SecTrust'),
        'linux' => version.$2.contains('curl '),
        _ => false,
      };
      if (version.$1 != 0 || !nativeClient) {
        return {
          'ok': false,
          'code': 'tls_system_client_unavailable',
          'completedEndpoints': 0,
        };
      }
      var completed = 0, transport = 0, http = 0;
      for (final endpoint in endpoints) {
        final proxy = network.proxy;
        final args = [
          '-q',
          '--config',
          '-',
          '--silent',
          '--head',
          '--proto',
          '=https',
          '--tlsv1.2',
          if (operatingSystem == 'windows') '--no-ssl-auto-client-cert',
          '--connect-timeout',
          '5',
          '--max-time',
          '10',
          '--output',
          operatingSystem == 'windows' ? 'NUL' : '/dev/null',
          '--write-out',
          '%{http_code}',
          '--proxy',
          proxy.mode == ProxyMode.direct
              ? ''
              : '${proxy.mode.name}://${proxy.host}:${proxy.port}',
          '--noproxy',
          '',
          '--proxy-basic',
          if (caFile != null) ...['--cacert', caFile, '--proxy-cacert', caFile],
          if (caDirectory) ...[
            '--capath',
            '/etc/ssl/certs',
            '--proxy-capath',
            '/etc/ssl/certs',
          ],
          endpoint,
        ];
        // No shell, curlrc, arbitrary URL, redirect, insecure option or direct
        // fallback. Proxy secrets travel only through a private stdin pipe.
        String quoted(String value) =>
            value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        final input = network.hasAuthentication
            ? 'proxy-user = "${quoted('${network.username}:${network.password}')}"\n'
            : '';
        final result = await _command(executable, args, input);
        final status = int.tryParse(result.$2.trim()) ?? 0;
        if (result.$1 == 0 && status == 200) {
          completed++;
        } else if (transport == 0 && http == 0) {
          transport = result.$1.clamp(0, 1000);
          http = status.clamp(0, 599);
        }
      }
      return {
        'ok': completed == endpoints.length,
        'code': completed == endpoints.length
            ? 'tls_recovery_completed'
            : 'tls_recovery_incomplete',
        'completedEndpoints': completed,
        'transportCode': transport,
        'httpStatus': http,
      };
    } catch (_) {
      return {
        'ok': false,
        'code': 'tls_system_client_unavailable',
        'completedEndpoints': 0,
      };
    }
  }

  static Future<bool> _pathExists(String path) async =>
      await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

  static String _systemCurl() {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    // Resolve the native system directory through Windows, never PATH or an
    // environment-supplied SystemRoot. Works for native x64 and ARM64 Dart.
    final getDirectory = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Uint32 Function(Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, int)
        >('GetSystemDirectoryW');
    final buffer = calloc<Uint16>(32768);
    try {
      final length = getDirectory(buffer.cast(), 32768);
      if (length == 0 || length >= 32768) throw const FormatException();
      return '${buffer.cast<Utf16>().toDartString(length: length)}\\curl.exe';
    } finally {
      calloc.free(buffer);
    }
  }

  static Future<(int, String)> _execute(
    String executable,
    List<String> arguments,
    String input,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      includeParentEnvironment: false,
      environment: Map.of(Platform.environment)
        ..removeWhere(
          (key, _) =>
              const [
                'CURL_CA_BUNDLE',
                'SSL_CERT_FILE',
                'SSL_CERT_DIR',
                'CURL_SSL_BACKEND',
                'SSLKEYLOGFILE',
                'LD_LIBRARY_PATH',
                'LD_PRELOAD',
              ].contains(key) ||
              key.startsWith('DYLD_'),
        ),
    );
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 15), () {
      timedOut = true;
      process.kill();
    });
    final output = <int>[];
    final stdoutDone = process.stdout.forEach((chunk) {
      if (output.length + chunk.length <= 8192) {
        output.addAll(chunk);
      } else {
        timedOut = true;
        process.kill();
      }
    });
    // Never retain native error strings: they may contain proxy credentials or
    // personal configuration. Only numeric exit/HTTP codes leave this method.
    final stderrDone = process.stderr.drain<void>();
    try {
      try {
        process.stdin.write(input);
        await process.stdin.close();
      } catch (_) {}
      final code = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      return (timedOut ? 28 : code, utf8.decode(output, allowMalformed: true));
    } finally {
      timer.cancel();
    }
  }
}

Future<bool> confirmTlsRecovery(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Aggiornamento dei certificati di sicurezza')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              tr(
                context,
                'Alcuni controlli online non sono riusciti. Potrebbero mancare certificati di sicurezza nell’archivio locale.\n\nVuoi consentire un controllo aggiuntivo tramite i servizi ufficiali CIE? Il sistema operativo applicherà le proprie regole di fiducia e, dove previsto, potrà recuperare i certificati mancanti. Su richiesta potrà comparire l’autorizzazione amministrativa per aggiornare il pacchetto dei certificati attendibili.\n\nLa lista dei certificati revocati viene consultata per la verifica e non viene installata come certificato. Il documento resta sul computer; non servono la CIE o il PIN. Al termine verrà ripetuta soltanto la verifica.',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Non ora')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Consenti e riprova')),
          ),
        ],
      ),
    ) ??
    false;
