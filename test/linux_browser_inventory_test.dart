// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/browser_setup.dart';
import 'package:cie_flutter_prototype/firefox_setup.dart';
import 'package:cie_flutter_prototype/linux_browser_inventory.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

class ConfiguredFirefox implements FirefoxSetupService {
  @override
  Future<JsonResult> inspect() async => {
    'ok': true,
    'snapPermission': 'connected',
    'profiles': [
      {'id': 'native', 'target': 'firefox', 'state': 'configured'},
      {'id': 'snap', 'target': 'snap', 'state': 'configured'},
    ],
  };
  @override
  Future<JsonResult> plan(String profile) async =>
      throw StateError('No writes expected');
  @override
  Future<JsonResult> apply(String profile, String fingerprint) async =>
      throw StateError('No writes expected');
  @override
  Future<JsonResult> connectPcsc() async =>
      throw StateError('No permission change expected');
}

void main() {
  group('Linux portable Firefox discovery', () {
    late Directory home, root, profile, installation;
    late Map<String, String> environment;

    void write(String name, String text) => File(name)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    void initialize({bool absolute = false}) {
      write(
        '${root.path}/profiles.ini',
        '[Profile0]\nIsRelative=${absolute ? 0 : 1}\nPath=${absolute ? profile.path : 'native'}\n',
      );
      write(
        '${profile.path}/cert9.db',
        'synthetic database; never opened by NSS',
      );
      write(
        '${profile.path}/compatibility.ini',
        '[Compatibility]\nLastPlatformDir=${installation.path}\n',
      );
      write(
        '${installation.path}/application.ini',
        '[App]\nName=Firefox\nID={ec8030f7-c20a-464f-9b0e-13a3a9e97384}\n',
      );
      final executable = File('${installation.path}/firefox')
        ..writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);
      expect(
        Process.runSync('/bin/chmod', ['700', executable.path]).exitCode,
        0,
      );
    }

    List<String> inventory([Set<String> system = const {}]) =>
        installedLinuxBrowsers(
          environment: environment,
          fileExists: system.contains,
        );

    Map<String, List<int>> contents() => {
      for (final file in home.listSync(recursive: true).whereType<File>())
        file.path: file.readAsBytesSync(),
    };

    setUp(() {
      home = Directory.systemTemp.createTempSync('cie-firefox-inventory-');
      root = Directory('${home.path}/.mozilla/firefox');
      profile = Directory('${root.path}/native');
      installation = Directory('${home.path}/Download/Firefox standard');
      environment = {'HOME': home.path};
    });
    tearDown(() => home.deleteSync(recursive: true));

    test('finds portable Firefox alongside Snap without changing any file', () {
      initialize();
      final before = contents();
      expect(
        inventory({
          '/snap/bin/firefox',
          '/usr/bin/firefox',
          '/usr/bin/google-chrome',
        }),
        ['chrome', 'firefox', 'firefox-snap'],
      );
      expect(contents(), before);
    });

    test(
      'reads absolute profiles and both default and custom XDG config roots',
      () {
        for (final config in [
          '${home.path}/.config',
          '${home.path}/my-config',
        ]) {
          root = Directory('$config/mozilla/firefox');
          profile = Directory('${root.path}/native');
          environment['XDG_CONFIG_HOME'] = config;
          initialize(absolute: true);
          expect(inventory(), ['firefox']);
          root.deleteSync(recursive: true);
        }
      },
    );

    test('stale profile does not certify a removed executable', () {
      initialize();
      File('${installation.path}/firefox').deleteSync();
      expect(inventory(), isEmpty);
    });

    test(
      'uninitialized profiles do not establish portable browser availability',
      () {
        initialize();
        File('${profile.path}/cert9.db').deleteSync();
        expect(inventory(), isEmpty);
      },
    );

    test(
      'requires Firefox identity and an executable ELF without running it',
      () {
        initialize();
        final app = File('${installation.path}/application.ini');
        final original = app.readAsStringSync();
        app.writeAsStringSync(
          original.replaceFirst('Name=Firefox', 'Name=Other'),
        );
        expect(inventory(), isEmpty);
        app.writeAsStringSync(
          original.replaceFirst(
            '{ec8030f7-c20a-464f-9b0e-13a3a9e97384}',
            'other',
          ),
        );
        expect(inventory(), isEmpty);
        app.writeAsStringSync(original);
        final executable = File('${installation.path}/firefox');
        executable.writeAsStringSync('#!/bin/sh\nexit 99\n');
        expect(inventory(), isEmpty);
        executable.writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);
        expect(
          Process.runSync('/bin/chmod', ['600', executable.path]).exitCode,
          0,
        );
        expect(inventory(), isEmpty);
      },
    );

    test('missing or oversized metadata is ignored and healthy profiles still work', () {
      initialize();
      final metadata = File('${profile.path}/compatibility.ini');
      final original = metadata.readAsStringSync();
      metadata.writeAsStringSync('x' * (64 * 1024 + 1));
      expect(inventory(), isEmpty);
      metadata.deleteSync();
      expect(inventory(), isEmpty);
      metadata.writeAsStringSync(original);
      final index = File('${root.path}/profiles.ini');
      index.writeAsStringSync(
        '[Profile0]\nIsRelative=1\nPath=missing\n[Profile1]\nIsRelative=1\nPath=native\n',
      );
      expect(inventory(), ['firefox']);
    });

    test('Snap wrapper and Snap-only profiles are not native Firefox', () {
      root = Directory('${home.path}/snap/firefox/common/.mozilla/firefox');
      profile = Directory('${root.path}/native');
      initialize();
      expect(inventory({'/snap/bin/firefox', '/usr/bin/firefox'}), [
        'firefox-snap',
      ]);
    });

    test('profile paths outside HOME and unsupported Flatpak installations are excluded', () {
      initialize();
      File('${root.path}/profiles.ini')
          .writeAsStringSync('[Profile0]\nIsRelative=0\nPath=/tmp/outside\n');
      expect(inventory(), isEmpty);
      installation = Directory(
        '${home.path}/.local/share/flatpak/app/org.mozilla.firefox',
      );
      initialize();
      expect(inventory(), isEmpty);
    });

    test(
      'system Firefox remains distinct from Snap and standard paths still work',
      () {
        expect(inventory({'/usr/lib/firefox/firefox', '/snap/bin/firefox'}), [
          'firefox',
          'firefox-snap',
        ]);
        expect(inventory({'/usr/bin/firefox'}), ['firefox']);
        expect(inventory(), isEmpty);
      },
    );

    test('coordinator lists both configured Firefox installations without setup writes', () async {
      initialize();
      final before = contents();
      final coordinator = BrowserSetupCoordinator(
        platform: 'linux',
        inventory: () async => {
          'ok': true,
          'installed': inventory({'/snap/bin/firefox'}),
        },
        systemReader: () async => {'ok': true, 'available': true},
        firefox: ConfiguredFirefox(),
        log: (_, _, _) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      expect(coordinator.configured, ['firefox', 'firefox-snap']);
      expect(contents(), before);
    });
  }, skip: !Platform.isLinux);
}
