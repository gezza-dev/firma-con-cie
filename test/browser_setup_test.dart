// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/browser_setup.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/firefox_setup.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'chrome_setup_test.dart' show FakeChromeSetup;
import 'home_enrollment_test.dart' show UnifiedFake;
import 'web_completion_feedback_test.dart' show size;

class Profiles implements FirefoxSetupService {
  final states = <String, String>{'one': 'needs_setup', 'two': 'needs_setup'};
  final writes = <String>[];
  bool open = false;
  @override
  Future<JsonResult> inspect() async => {
    'ok': true,
    'snapPermission': 'connected',
    'profiles': [
      for (final p in states.entries)
        {'id': p.key, 'target': 'firefox', 'state': p.value},
    ],
  };
  @override
  Future<JsonResult> plan(String id) async => {
    'ok': true,
    'fingerprint': 'plan-$id',
  };
  @override
  Future<JsonResult> apply(String id, String fingerprint) async {
    if (open) return {'ok': false, 'code': 'browser_running'};
    writes.add(id);
    states[id] = 'configured';
    return {'ok': true};
  }

  @override
  Future<JsonResult> connectPcsc() async => throw StateError('No Snap profile');
}

class SnapProfiles extends Profiles {
  int permissions = 0;
  @override
  Future<JsonResult> inspect() async => {
    'ok': true,
    'snapPermission': 'disconnected',
    'profiles': [
      {'id': 'snap', 'target': 'snap', 'state': 'configured'},
      {'id': 'native', 'target': 'firefox', 'state': 'configured'},
    ],
  };
  @override
  Future<JsonResult> connectPcsc() async {
    permissions++;
    return {'ok': false, 'code': 'permission_not_verified'};
  }
}

EnrollmentRecord paired([bool published = true]) => EnrollmentRecord(
  {
    'card': 'SYNTHETIC',
    'readyForSigning': true,
    'publicDataSaved': true,
    'webProvisioned': published,
  },
  {'available': true},
);

void main() {
  test(
    'Snap authorization failure is requested once and preserves native Firefox',
    () async {
      final profiles = SnapProfiles();
      final events = <String>[];
      final coordinator = BrowserSetupCoordinator(
        platform: 'linux',
        inventory: () async => {
          'ok': true,
          'installed': ['firefox', 'firefox-snap'],
          'default': 'firefox-snap',
        },
        systemReader: () async => {'available': true},
        firefox: profiles,
        log: (id, code, _) async => events.add('$id:$code'),
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      await coordinator.refresh();
      expect(profiles.permissions, 1);
      expect(coordinator.configured, ['firefox']);
      expect(events, contains('firefox-snap:permission_not_verified'));
    },
  );
  test('default changes reorder ready browsers and missing inventory clears stale names', () async {
    var selected = 'edge';
    var installed = ['edge', 'chrome'];
    final coordinator = BrowserSetupCoordinator(
      platform: 'windows',
      inventory: () async => {
        'ok': true,
        'installed': installed,
        'default': selected,
      },
      systemReader: () async => {'available': true},
      log: (_, _, _) async =>
          throw const FileSystemException('Log unavailable'),
    );
    addTearDown(coordinator.dispose);
    await coordinator.refresh();
    expect(coordinator.configured, ['edge', 'chrome']);
    selected = 'chrome';
    await coordinator.refresh();
    expect(coordinator.configured, ['chrome', 'edge']);
    installed = [];
    await coordinator.refresh();
    expect(coordinator.configured, isEmpty);
    expect(coordinator.pairedMessage(paired()), browserNotConfigured);
  });
  test('a forced refresh arriving during a check is preserved', () async {
    final wait = Completer<JsonResult>();
    final twice = Completer<void>();
    var inventoryReads = 0, componentReads = 0;
    final coordinator = BrowserSetupCoordinator(
      platform: 'windows',
      inventory: () async {
        inventoryReads++;
        return inventoryReads == 1
            ? await wait.future
            : {
                'ok': true,
                'installed': ['chrome'],
              };
      },
      systemReader: () async {
        componentReads++;
        if (componentReads == 2) twice.complete();
        return {'available': true};
      },
      log: (_, _, _) async {},
    );
    addTearDown(coordinator.dispose);
    final first = coordinator.refresh();
    await coordinator.refresh(forceSystem: true);
    wait.complete({
      'ok': true,
      'installed': ['chrome'],
    });
    await first;
    await twice.future;
    expect(componentReads, 2);
  });
  test('configures all initialized Firefox profiles and puts a configured default first', () async {
    final firefox = Profiles();
    final chrome = FakeChromeSetup();
    final events = <String>[];
    final coordinator = BrowserSetupCoordinator(
      platform: 'linux',
      inventory: () async => {
        'ok': true,
        'installed': ['firefox', 'chrome'],
        'default': 'chrome',
      },
      systemReader: () async => {'available': true},
      firefox: firefox,
      chrome: chrome,
      log: (browser, code, _) async => events.add('$browser:$code'),
    );
    addTearDown(coordinator.dispose);
    await coordinator.refresh();
    expect(firefox.writes, ['one', 'two']);
    expect(chrome.writes, 1);
    expect(coordinator.configured, ['chrome', 'firefox']);
    expect(
      coordinator.pairedMessage(paired()),
      contains('Google Chrome, Firefox.'),
    );
    await coordinator.refresh();
    expect(firefox.writes, ['one', 'two']);
    expect(chrome.writes, 1);
    expect(events, contains('chrome:configured'));
  });
  test(
    'open browser is deferred, other browser succeeds, later refresh retries',
    () async {
      final firefox = Profiles()..open = true;
      final events = <String>[];
      final coordinator = BrowserSetupCoordinator(
        platform: 'linux',
        inventory: () async => {
          'ok': true,
          'installed': ['firefox', 'chrome'],
          'default': 'firefox',
        },
        systemReader: () async => {'available': true},
        firefox: firefox,
        chrome: FakeChromeSetup(),
        log: (browser, code, _) async => events.add('$browser:$code'),
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      expect(coordinator.configured, ['chrome']);
      expect(firefox.writes, isEmpty);
      expect(events, contains('firefox:browser_running'));
      expect(coordinator.pairedMessage(paired()), contains('Google Chrome.'));
      expect(
        coordinator.pairedMessage(paired()),
        isNot(contains('browser_running')),
      );
      firefox.open = false;
      await coordinator.refresh();
      expect(coordinator.configured, ['firefox', 'chrome']);
      expect(firefox.writes, ['one', 'two']);
    },
  );
  test('conflicting profile is untouched and does not hide another configured profile', () async {
    final firefox = Profiles()..states['two'] = 'module_conflict';
    final events = <String>[];
    final coordinator = BrowserSetupCoordinator(
      platform: 'linux',
      inventory: () async => {
        'ok': true,
        'installed': ['firefox'],
      },
      systemReader: () async => {'available': true},
      firefox: firefox,
      log: (browser, code, _) async => events.add('$browser:$code'),
    );
    addTearDown(coordinator.dispose);
    await coordinator.refresh();
    expect(firefox.writes, ['one']);
    expect(firefox.states['two'], 'module_conflict');
    expect(coordinator.configured, ['firefox']);
    expect(events, contains('firefox:module_conflict'));
  });
  for (final platform in ['windows', 'macos', 'linux']) {
    test(
      '$platform uses the same unconfigured and configured paired messages',
      () async {
        final ids = platform == 'macos' ? ['safari', 'chrome'] : ['chrome'];
        final coordinator = BrowserSetupCoordinator(
          platform: platform,
          inventory: () async => {
            'ok': true,
            'installed': ids,
            'default': 'chrome',
          },
          systemReader: () async => {'available': true},
          chrome: FakeChromeSetup(),
          log: (_, _, _) async {},
        );
        addTearDown(coordinator.dispose);
        expect(coordinator.pairedMessage(paired()), browserNotConfigured);
        await coordinator.refresh();
        expect(
          coordinator.pairedMessage(paired()),
          startsWith(
            'Accesso ai siti con CIE configurato. Apri il sito nei seguenti browser: Google Chrome',
          ),
        );
        expect(coordinator.pairedMessage(paired(false)), browserNotConfigured);
      },
    );
  }
  test(
    'Windows missing component never elevates or configures browsers',
    () async {
      final chrome = FakeChromeSetup();
      var activated = 0;
      final coordinator = BrowserSetupCoordinator(
        platform: 'windows',
        inventory: () async => {
          'ok': true,
          'installed': ['edge', 'chrome', 'firefox'],
        },
        systemReader: () async => {
          'available': false,
          'componentStatusCode': 10,
        },
        chrome: chrome,
        activate: () async {
          activated++;
          return {'ok': true};
        },
        log: (_, _, _) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      expect(coordinator.configured, isEmpty);
      expect(activated, 0);
      expect(chrome.writes, 0);
    },
  );
  test(
    'macOS activation is attempted once and unsupported Edge is not listed',
    () async {
      var activated = 0;
      final coordinator = BrowserSetupCoordinator(
        platform: 'macos',
        inventory: () async => {
          'ok': true,
          'installed': ['edge', 'safari'],
          'default': 'edge',
        },
        systemReader: () async => {
          'available': false,
          'canActivateComponent': true,
        },
        activate: () async {
          activated++;
          return {'ok': false};
        },
        log: (_, _, _) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      await coordinator.refresh(forceSystem: true);
      expect(activated, 1);
      expect(coordinator.configured, isEmpty);
    },
  );
  test(
    'uninitialized browser is retried when profile becomes available',
    () async {
      final chrome = FakeChromeSetup()..state = 'database_uninitialized';
      final coordinator = BrowserSetupCoordinator(
        platform: 'linux',
        inventory: () async => {
          'ok': true,
          'installed': ['chrome'],
        },
        systemReader: () async => {'available': true},
        chrome: chrome,
        log: (_, _, _) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      expect(chrome.writes, 0);
      chrome.state = 'needs_setup';
      await coordinator.refresh();
      expect(chrome.writes, 1);
    },
  );
  test(
    'overlapping refreshes coalesce and disposal prevents pending writes',
    () async {
      final wait = Completer<JsonResult>();
      var reads = 0;
      final chrome = FakeChromeSetup();
      final coordinator = BrowserSetupCoordinator(
        platform: 'linux',
        inventory: () {
          reads++;
          return wait.future;
        },
        systemReader: () async => {'available': true},
        chrome: chrome,
        log: (_, _, _) async {},
      );
      final pending = coordinator.refresh();
      await coordinator.refresh();
      expect(reads, 1);
      coordinator.dispose();
      wait.complete({
        'ok': true,
        'installed': ['chrome'],
      });
      await pending;
      expect(chrome.writes, 0);
    },
  );
  test(
    'macOS uses native Firefox capability without opening private profiles',
    () async {
      var inspections = 0;
      final found = await completeNativeBrowserInventory(
        {
          'ok': true,
          'installed': ['safari', 'firefox'],
          'nativeStates': {'firefox': 'configured'},
          'default': 'firefox',
        },
        platform: 'macos',
        firefoxInspector: () async {
          inspections++;
          throw const FileSystemException('Protected browser profile');
        },
      );
      expect(inspections, 0);
      expect(found['nativeStates'], {'firefox': 'configured'});
      final coordinator = BrowserSetupCoordinator(
        platform: 'macos',
        inventory: () async => found,
        systemReader: () async => {'available': true},
        log: (_, _, _) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.refresh();
      expect(coordinator.configured, ['firefox', 'safari']);
    },
  );
  test(
    'macOS does not certify missing or unsupported Firefox capability',
    () async {
      for (final state in [null, 'browser_version_unsupported']) {
        var inspected = false;
        final found = await completeNativeBrowserInventory(
          {
            'ok': true,
            'installed': ['safari', 'firefox'],
            if (state != null) 'nativeStates': {'firefox': state},
          },
          platform: 'macos',
          firefoxInspector: () async {
            inspected = true;
            return 'configured';
          },
        );
        expect(inspected, false);
        expect(
          (found['nativeStates'] as Map)['firefox'],
          state ?? 'browser_version_unavailable',
        );
        final coordinator = BrowserSetupCoordinator(
          platform: 'macos',
          inventory: () async => found,
          systemReader: () async => {'available': true},
          log: (_, _, _) async {},
        );
        await coordinator.refresh();
        expect(coordinator.configured, ['safari']);
        coordinator.dispose();
      }
    },
  );
  test('Windows retains profile overrides and inspection failures', () async {
    for (final state in ['configured', 'os_certificates_disabled']) {
      var inspections = 0;
      final found = await completeNativeBrowserInventory(
        {
          'ok': true,
          'installed': ['firefox'],
        },
        platform: 'windows',
        firefoxInspector: () async {
          inspections++;
          return state;
        },
      );
      expect(inspections, 1);
      expect(found['nativeStates'], {'firefox': state});
    }
    final failed = await completeNativeBrowserInventory(
      {
        'ok': true,
        'installed': ['firefox'],
      },
      platform: 'windows',
      firefoxInspector: () async {
        throw const FileSystemException('Unreadable synthetic profile');
      },
    );
    expect(failed['nativeStates'], {'firefox': 'profile_inspection_failed'});
  });
  test('native Firefox checks initialized profiles and respects explicit OS-certificate overrides', () async {
    final dir = await Directory.systemTemp.createTemp('browser-profiles-');
    addTearDown(() => dir.delete(recursive: true));
    expect(inspectNativeFirefoxProfiles(dir), 'profile_uninitialized');
    final profile = await Directory('${dir.path}/Profiles/one')
        .create(recursive: true);
    await File('${dir.path}/profiles.ini')
        .writeAsString('[Profile0]\nIsRelative=1\nPath=Profiles/one\n');
    final prefs = File('${profile.path}/prefs.js');
    await prefs.writeAsString('user_pref("unrelated", true);');
    expect(inspectNativeFirefoxProfiles(dir), 'configured');
    await File('${profile.path}/user.js')
        .writeAsString('user_pref("security.osclientcerts.autoload", false);');
    expect(inspectNativeFirefoxProfiles(dir), 'os_certificates_disabled');
    expect(await prefs.readAsString(), 'user_pref("unrelated", true);');
    final custom = await Directory('${dir.path}/custom').create();
    await File('${custom.path}/prefs.js')
        .writeAsString('user_pref("unrelated", false);');
    await File('${dir.path}/profiles.ini')
        .writeAsString('[Profile0]\nIsRelative=0\nPath=${custom.path}\n');
    expect(inspectNativeFirefoxProfiles(dir), 'configured');
  });
  test('setup file log is bounded, serializes writes and excludes arbitrary strings', () async {
    final dir = await Directory.systemTemp.createTemp('browser-log-');
    addTearDown(() => dir.delete(recursive: true));
    final log = BrowserSetupLog(directory: dir);
    await Future.wait([
      log.record('chrome', 'configured', null),
      log.record('secret-path', 'invalid/code', 10),
    ]);
    final file = File('${dir.path}/browser-setup.jsonl');
    final rows = (await file.readAsLines())
        .map((line) => jsonDecode(line) as Map)
        .toList();
    expect(rows.length, 2);
    expect(rows.last['browser'], 'system');
    expect(rows.last['code'], 'unclassified_error');
    expect(await file.readAsString(), isNot(contains('secret-path')));
    await file.writeAsString('x' * (512 * 1024 + 1));
    await log.record('chrome', 'browser_running', null);
    expect(
      await File('${dir.path}/browser-setup.previous.jsonl').exists(),
      true,
    );
    expect(await file.length(), lessThan(4096));
    await file.writeAsString('x' * (512 * 1024 + 1));
    await log.record('firefox', 'configured', null);
    expect(await file.length(), lessThan(4096));
  });
  testWidgets(
    'background discovery does not disable navigation and errors stay out of successful Home',
    (t) async {
      size(t);
      final wait = Completer<JsonResult>();
      final events = <String>[];
      final coordinator = BrowserSetupCoordinator(
        platform: 'windows',
        inventory: () => wait.future,
        systemReader: () async => {'available': true},
        log: (id, code, _) async => events.add('$id:$code'),
      );
      final service = UnifiedFake()
        ..records['TEST'] = {
          'card': 'TEST',
          'readyForSigning': true,
          'publicDataSaved': true,
          'webProvisioned': true,
        };
      await t.pumpWidget(
        CiePrototype(
          service: service,
          browserSetup: coordinator,
          webStatusReader: coordinator.cachedSystemStatus,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(browserNotConfigured), findsOneWidget);
      await t.tap(find.text('Verifica Firma').first);
      await t.pumpAndSettle();
      expect(find.text('Seleziona un documento'), findsWidgets);
      wait.complete({
        'ok': true,
        'installed': ['chrome', 'firefox'],
        'default': 'chrome',
        'nativeStates': {'firefox': 'os_certificates_disabled'},
      });
      await t.pumpAndSettle();
      await t.tap(find.text('Home').first);
      await t.pumpAndSettle();
      expect(
        find.textContaining('nei seguenti browser: Google Chrome.'),
        findsOneWidget,
      );
      expect(find.textContaining('os_certificates_disabled'), findsNothing);
      expect(events, contains('firefox:os_certificates_disabled'));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
