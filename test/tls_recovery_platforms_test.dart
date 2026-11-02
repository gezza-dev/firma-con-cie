// SPDX-License-Identifier: BSD-3-Clause
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/linux_ca_update.dart';
import 'package:cie_flutter_prototype/network_settings.dart';
import 'package:cie_flutter_prototype/tls_recovery.dart';

const id = 'ca-certificates;2026.01;all;distribution-repository';

class PackageFake implements CaPackageTransport {
  final calls = <(String, List<DBusValue>)>[];
  List<(int, String)> plan = [(19, id)];
  bool installed = false, closed = false, deny = false;
  void Function()? onPlan;
  @override
  Future<CaPackageResult> run(String method, List<DBusValue> values) async {
    calls.add((method, values));
    if (method == 'Resolve') {
      return CaPackageResult(
        true,
        packages: values[1].asStringArray().single == 'ca-certificates'
            ? [(2, id)]
            : [],
      );
    }
    if (method == 'InstallPackages') {
      if (values[0].asUint64() & LinuxCaUpdater.simulate != 0) {
        onPlan?.call();
        return CaPackageResult(true, packages: plan);
      }
      installed = !deny;
      return CaPackageResult(!deny, code: deny ? 54 : 0);
    }
    return const CaPackageResult(true);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('PackageKit refreshes, resolves exact CA names, simulates and requests only trusted reinstall', () async {
    final bus = PackageFake();
    final result = await LinuxCaUpdater(transport: () => bus).update();
    expect(result['ok'], true);
    expect(result['caUpdateCompleted'], true);
    expect(bus.closed, true);
    expect(bus.calls.map((v) => v.$1), [
      'RefreshCache',
      'Resolve',
      'Resolve',
      'Resolve',
      'InstallPackages',
      'InstallPackages',
    ]);
    final installs = bus.calls.where((v) => v.$1 == 'InstallPackages').toList();
    expect(installs.first.$2[0].asUint64(), (1 << 1) | (1 << 2) | (1 << 4));
    expect(installs.last.$2[0].asUint64(), (1 << 1) | (1 << 4));
    expect(installs.last.$2[1].asStringArray(), [id]);
  });

  for (final plan in <(int, String)>[
    (12, 'unrelated-app;1;x86_64;repo'),
    (13, id),
    (15, id),
    (20, id),
    (23, id),
  ]) {
    test(
      'unsafe package plan is refused before authorization/install: $plan',
      () async {
        final bus = PackageFake()..plan = [plan];
        final result = await LinuxCaUpdater(transport: () => bus).update();
        expect(result['code'], 'tls_ca_update_plan_rejected');
        expect(bus.installed, false);
        expect(bus.calls.where((v) => v.$1 == 'InstallPackages').length, 1);
        expect(bus.closed, true);
      },
    );
  }

  test('system authorization failure and cancellation never report a successful CA update', () async {
    final denied = PackageFake()..deny = true;
    final result = await LinuxCaUpdater(transport: () => denied).update();
    expect(result['ok'], false);
    expect(result['packageManagerCode'], 54);
    var current = true;
    final cancelled = PackageFake()..onPlan = () => current = false;
    final cancelledResult = await LinuxCaUpdater(transport: () => cancelled)
        .update(isCurrent: () => current);
    expect(cancelledResult['code'], 'tls_ca_update_cancelled');
    expect(cancelled.installed, false);
  });

  for (final os in ['windows', 'macos', 'linux']) {
    test(
      'platform $os uses the proper trusted client and fixed targets',
      () async {
        final calls = <List<String>>[];
        final version = switch (os) {
          'windows' => 'curl Schannel',
          'macos' => 'curl (SecureTransport) LibreSSL',
          _ => 'curl OpenSSL',
        };
        final recovery = TlsRecovery(
          operatingSystem: os,
          executable: '/synthetic/curl',
          exists: (name) async =>
              name == TlsRecovery.linuxCaFiles.first ||
              name == '/etc/ssl/certs',
          linuxUpdater: LinuxCaUpdater(
            transport: () => throw StateError('No package update needed'),
          ),
          command: (_, args, input) async {
            calls.add(args);
            return (0, args.contains('--version') ? version : '200');
          },
        );
        final result = await recovery.recover(
          const SessionNetworkConfig(),
          allowLinuxUpdate: true,
          tlsFailureObserved: true,
        );
        expect(result['ok'], true);
        expect(calls.length, 3);
        for (final args in calls.skip(1)) {
          expect(args.last, isIn(TlsRecovery.endpoints));
          expect(
            args[args.indexOf('--output') + 1],
            os == 'windows' ? 'NUL' : '/dev/null',
          );
          expect(args.contains('--no-ssl-auto-client-cert'), os == 'windows');
          expect(args.contains('--cacert'), os == 'linux');
          expect(args.contains('--proxy-cacert'), os == 'linux');
          expect(args, isNot(contains('--insecure')));
        }
      },
    );
  }

  test('Linux missing CA store is repaired only after consent; then actual verification is repeated', () async {
    final bus = PackageFake();
    var checks = 0, prompts = 0;
    final recovery = TlsRecovery(
      operatingSystem: 'linux',
      executable: '/synthetic/curl',
      exists: (_) async => bus.installed,
      linuxUpdater: LinuxCaUpdater(transport: () => bus),
      command: (_, args, input) async =>
          (0, args.contains('--version') ? 'curl OpenSSL' : '200'),
    );
    final result = await recovery.retry(
      original: {'ok': false, 'transportCode': 60},
      network: const SessionNetworkConfig(),
      consent: () async {
        prompts++;
        return true;
      },
      verify: () async {
        checks++;
        return {'ok': true};
      },
      isCurrent: () => true,
      record: (_) {},
      onRecovery: (_) async {},
    );
    expect(result['ok'], true);
    expect(prompts, 1);
    expect(checks, 1);
    expect(bus.installed, true);
    var touched = false;
    final declined = TlsRecovery(
      operatingSystem: 'linux',
      linuxUpdater: LinuxCaUpdater(
        transport: () {
          touched = true;
          return PackageFake();
        },
      ),
    );
    await declined.retry(
      original: {'ok': false, 'transportCode': 60},
      network: const SessionNetworkConfig(),
      consent: () async => false,
      verify: () async => throw StateError('Must not retry'),
      isCurrent: () => true,
      record: (_) {},
      onRecovery: (_) async {},
    );
    expect(touched, false);
  });

  test('a Linux transport error unrelated to TLS never starts package installation', () async {
    var touched = false;
    final recovery = TlsRecovery(
      operatingSystem: 'linux',
      executable: '/synthetic/curl',
      exists: (_) async => true,
      linuxUpdater: LinuxCaUpdater(
        transport: () {
          touched = true;
          return PackageFake();
        },
      ),
      command: (_, args, input) async =>
          args.contains('--version') ? (0, 'curl OpenSSL') : (7, '000'),
    );
    final result = await recovery.recover(
      const SessionNetworkConfig(),
      allowLinuxUpdate: true,
      tlsFailureObserved: true,
    );
    expect(result['ok'], false);
    expect(result['transportCode'], 7);
    expect(touched, false);
  });

  test('a missing PackageKit service leaves verification indeterminate and records no native text', () async {
    final recovery = TlsRecovery(
      operatingSystem: 'linux',
      exists: (_) async => false,
      linuxUpdater: LinuxCaUpdater(
        transport: () => throw StateError('private native details'),
      ),
    );
    final result = await recovery.recover(
      const SessionNetworkConfig(),
      allowLinuxUpdate: true,
    );
    expect(result['ok'], false);
    expect(result['code'], 'tls_ca_update_unavailable');
    expect(result.toString(), isNot(contains('private native')));
    expect(result['caUpdateCompleted'], false);
  });
}
