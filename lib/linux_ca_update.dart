// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

class CaPackageResult {
  const CaPackageResult(this.ok, {this.packages = const [], this.code = 0});
  final bool ok;
  final List<(int, String)> packages;
  final int code;
}

abstract interface class CaPackageTransport {
  Future<CaPackageResult> run(String method, List<DBusValue> values);
  Future<void> close();
}

// PackageKit owns repository verification and Polkit authorization. The app
// neither collects an administrator password nor executes a privileged shell.
class LinuxCaUpdater {
  LinuxCaUpdater({CaPackageTransport Function()? transport})
    : _transport = transport ?? (() => PackageKitCaTransport());
  final CaPackageTransport Function() _transport;
  static const names = [
    'ca-certificates',
    'ca-certificates-mozilla',
    'ca-certificates-utils',
  ];
  static const trustedReinstall = (1 << 1) | (1 << 4);
  static const simulate = 1 << 2;
  static const newestNative = (1 << 16) | (1 << 18) | (1 << 21);

  static bool allowedId(String id) {
    final parts = id.split(';');
    return id.length <= 1024 &&
        !id.runes.any((c) => c < 32 || c == 127) &&
        parts.length == 4 &&
        names.contains(parts[0]) &&
        parts[1].isNotEmpty &&
        parts[2].isNotEmpty;
  }

  Future<Map<String, dynamic>> update({bool Function()? isCurrent}) async {
    CaPackageTransport? transport;
    Map<String, dynamic> failure(String code, [int native = 0]) => {
      'ok': false,
      'code': code,
      'packageManagerCode': native.clamp(0, 10000),
      'caUpdateCompleted': false,
    };
    try {
      if (isCurrent?.call() == false) return failure('tls_ca_update_cancelled');
      transport = _transport();
      final refreshed = await transport.run('RefreshCache', [
        const DBusBoolean(true),
      ]);
      if (!refreshed.ok) return failure('tls_ca_update_failed', refreshed.code);
      final ids = <String>{};
      for (final name in names) {
        if (isCurrent?.call() == false) {
          return failure('tls_ca_update_cancelled');
        }
        final resolved = await transport.run('Resolve', [
          const DBusUint64(newestNative),
          DBusArray.string([name]),
        ]);
        if (!resolved.ok) {
          if (name == names.first) {
            return failure('tls_ca_update_failed', resolved.code);
          }
          continue; // Optional CA-data packages do not exist on every distro.
        }
        for (final (_, id) in resolved.packages) {
          if (!allowedId(id) || id.split(';').first != name) {
            return failure('tls_ca_update_plan_rejected');
          }
          ids.add(id);
        }
      }
      if (!ids.any((id) => id.startsWith('ca-certificates;'))) {
        return failure('tls_ca_update_unavailable');
      }
      if (ids.length > 12 || isCurrent?.call() == false) {
        return failure('tls_ca_update_cancelled');
      }
      final planned = await transport.run('InstallPackages', [
        const DBusUint64(trustedReinstall | simulate),
        DBusArray.string(ids),
      ]);
      if (!planned.ok) return failure('tls_ca_update_failed', planned.code);
      // No full upgrade, key import, repository change, removal or downgrade.
      // Refuse plans which would change packages outside the certificate set.
      if (planned.packages.any(
        (p) => !allowedId(p.$2) || const [13, 15, 20, 23].contains(p.$1),
      )) {
        return failure('tls_ca_update_plan_rejected');
      }
      if (isCurrent?.call() == false) return failure('tls_ca_update_cancelled');
      final installed = await transport.run('InstallPackages', [
        const DBusUint64(trustedReinstall),
        DBusArray.string(ids),
      ]);
      return installed.ok
          ? {
              'ok': true,
              'code': 'tls_ca_update_completed',
              'caUpdateCompleted': true,
            }
          : failure('tls_ca_update_failed', installed.code);
    } catch (_) {
      return failure('tls_ca_update_unavailable');
    } finally {
      try {
        await transport?.close();
      } catch (_) {}
    }
  }
}

class PackageKitCaTransport implements CaPackageTransport {
  PackageKitCaTransport({DBusClient? bus}) : _bus = bus ?? DBusClient.system() {
    if (bus == null && !Platform.isLinux) {
      throw UnsupportedError('PackageKit requires Linux');
    }
  }
  final DBusClient _bus;
  static const service = 'org.freedesktop.PackageKit';
  static const transactionInterface = '$service.Transaction';

  @override
  Future<CaPackageResult> run(String method, List<DBusValue> values) async {
    if (!const [
      'RefreshCache',
      'Resolve',
      'InstallPackages',
    ].contains(method)) {
      throw ArgumentError('Unsupported certificate transaction');
    }
    final root = DBusRemoteObject(
      _bus,
      name: service,
      path: DBusObjectPath('/org/freedesktop/PackageKit'),
    );
    final created = await root
        .callMethod(
          service,
          'CreateTransaction',
          [],
          replySignature: DBusSignature('o'),
        )
        .timeout(const Duration(seconds: 15));
    final object = DBusRemoteObject(
      _bus,
      name: service,
      path: created.returnValues.single.asObjectPath(),
    );
    final done = Completer<CaPackageResult>();
    final packages = <(int, String)>[];
    var code = 0;
    void invalid() {
      if (!done.isCompleted) done.complete(const CaPackageResult(false));
    }

    final subscription =
        DBusSignalStream(
          _bus,
          sender: service,
          path: object.path,
          interface: transactionInterface,
        ).listen(
          (signal) {
            if (done.isCompleted) return;
            if (signal.name == 'Package') {
              if (signal.signature != DBusSignature('uss') ||
                  packages.length >= 512) {
                invalid();
                return;
              }
              final id = signal.values[1].asString();
              if (id.length > 1024) {
                invalid();
                return;
              }
              packages.add((signal.values[0].asUint32(), id));
            } else if (signal.name == 'ErrorCode') {
              if (signal.signature != DBusSignature('us')) {
                invalid();
                return;
              }
              code = signal.values[0]
                  .asUint32(); // Deliberately discard error details.
            } else if (signal.name == 'Finished') {
              if (signal.signature != DBusSignature('uu')) {
                invalid();
                return;
              }
              done.complete(
                CaPackageResult(
                  signal.values[0].asUint32() == 1 && code == 0,
                  packages: packages,
                  code: code,
                ),
              );
            } else if (const [
              'RepoSignatureRequired',
              'EulaRequired',
              'MediaChangeRequired',
            ].contains(signal.name)) {
              invalid(); // Never accept new signing keys, EULAs or installation media.
            }
          },
          onError: (_) => invalid(),
          onDone: invalid,
        );
    try {
      await object
          .callMethod(transactionInterface, 'SetHints', [
            DBusArray.string(['interactive=true', 'background=false']),
          ], replySignature: DBusSignature(''))
          .timeout(const Duration(seconds: 15));
      await object
          .callMethod(
            transactionInterface,
            method,
            values,
            replySignature: DBusSignature(''),
            allowInteractiveAuthorization: true,
          )
          .timeout(const Duration(minutes: 3));
      return await done.future.timeout(const Duration(minutes: 3));
    } catch (_) {
      // Ask the package daemon to cancel safely; never kill a root installer.
      try {
        await object
            .callMethod(
              transactionInterface,
              'Cancel',
              [],
              replySignature: DBusSignature(''),
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      return CaPackageResult(false, code: code);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> close() => _bus.close();
}
