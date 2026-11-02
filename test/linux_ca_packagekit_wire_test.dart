// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:dbus/dbus.dart';
// Pinned test-only authentication identity for a private test bus. Never
// use a real system bus or inspect the current user's identity in this test.
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/linux_ca_update.dart';

const service = 'org.freedesktop.PackageKit';
const txInterface = '$service.Transaction';
const caId = 'ca-certificates;2026;all;synthetic-repo';

class SyntheticTransaction extends DBusObject {
  SyntheticTransaction(super.path, this.calls, this.deny);
  final List<DBusMethodCall> calls;
  final bool deny;
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    calls.add(call);
    if (call.name == 'SetHints') {
      return call.signature == DBusSignature('as')
          ? DBusMethodSuccessResponse()
          : DBusMethodErrorResponse.invalidArgs();
    }
    if (call.name == 'Cancel') return DBusMethodSuccessResponse();
    if (call.name == 'Resolve') {
      if (call.signature != DBusSignature('tas')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      if (call.values[1].asStringArray().single == 'ca-certificates') {
        await emitSignal(txInterface, 'Package', [
          const DBusUint32(2),
          const DBusString(caId),
          const DBusString('synthetic'),
        ]);
      }
    } else if (call.name == 'InstallPackages') {
      if (call.signature != DBusSignature('tas')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      if (deny && call.values[0].asUint64() & LinuxCaUpdater.simulate == 0) {
        await emitSignal(txInterface, 'ErrorCode', [
          const DBusUint32(54),
          const DBusString('private-native-details'),
        ]);
        await emitSignal(txInterface, 'Finished', [
          const DBusUint32(2),
          const DBusUint32(1),
        ]);
        return DBusMethodSuccessResponse();
      }
      await emitSignal(txInterface, 'Package', [
        const DBusUint32(19),
        const DBusString(caId),
        const DBusString('synthetic'),
      ]);
    } else if (call.name != 'RefreshCache' ||
        call.signature != DBusSignature('b')) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    await emitSignal(txInterface, 'Finished', [
      const DBusUint32(1),
      const DBusUint32(1),
    ]);
    return DBusMethodSuccessResponse();
  }
}

class SyntheticRoot extends DBusObject {
  SyntheticRoot(this.serviceBus, this.deny)
    : super(DBusObjectPath('/org/freedesktop/PackageKit'));
  final DBusClient serviceBus;
  final bool deny;
  final calls = <DBusMethodCall>[];
  int next = 0;
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != service || call.name != 'CreateTransaction') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    final path = DBusObjectPath('/org/freedesktop/PackageKit/t${next++}');
    await serviceBus.registerObject(SyntheticTransaction(path, calls, deny));
    return DBusMethodSuccessResponse([path]);
  }
}

void main() {
  for (final denied in [false, true]) {
    test(
      'PackageKit protocol and authorization flags on an isolated bus: denied=$denied',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'cie-packagekit-wire-',
        );
        final server = DBusServer();
        final address = await server.listenAddress(
          DBusAddress.unix(dir: folder),
        );
        DBusClient client() => DBusClient(
          address,
          authClient: DBusAuthClient(uid: '1000', requestUnixFd: false),
        );
        final serviceBus = client(), caller = client();
        try {
          final root = SyntheticRoot(serviceBus, denied);
          await serviceBus.registerObject(root);
          await serviceBus.requestName(service);
          final updater = LinuxCaUpdater(
            transport: () => PackageKitCaTransport(bus: caller),
          );
          final result = await updater.update().timeout(
            const Duration(seconds: 12),
          );
          expect(result['ok'], !denied);
          if (denied) {
            expect(result['packageManagerCode'], 54);
            expect(
              result.toString(),
              isNot(contains('private-native-details')),
            );
          }
          final installs = root.calls
              .where((call) => call.name == 'InstallPackages')
              .toList();
          expect(installs.length, 2);
          expect(
            installs.every((call) => call.allowInteractiveAuthorization),
            true,
          );
          expect(installs.map((call) => call.values[0].asUint64()), [22, 18]);
          expect(
            installs.every(
              (call) => call.values[1].asStringArray().single == caId,
            ),
            true,
          );
          expect(
            root.calls
                .where((call) => call.name == 'SetHints')
                .every(
                  (call) => call.values.single.asStringArray().contains(
                    'interactive=true',
                  ),
                ),
            true,
          );
        } finally {
          await caller.close();
          await serviceBus.close();
          await server.close();
          await folder.delete(recursive: true);
        }
      },
      skip: !Platform.isLinux,
    );
  }
}
