// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'application_storage.dart';
import 'chrome_setup.dart';
import 'enrollment.dart';
import 'firefox_setup.dart';
import 'native_bridge.dart';
import 'web_access.dart';

const browserNames = <String, String>{
  'edge': 'Microsoft Edge',
  'chrome': 'Google Chrome',
  'firefox': 'Firefox',
  'firefox-snap': 'Firefox Snap',
  'safari': 'Safari',
};
const browserNotConfigured = 'Accesso ai siti con CIE non configurato.';
const _outcomeMessages = <String, String>{
  'configured': 'Browser configuration ready',
  'browser_running': 'Browser is running; configuration deferred',
  'profile_uninitialized':
      'No initialized browser profile; configuration deferred',
  'database_uninitialized':
      'Browser NSS database is not initialized; configuration deferred',
  'module_conflict':
      'Conflicting module found; existing configuration preserved',
  'os_certificates_disabled':
      'OS client certificates explicitly disabled; preferences preserved',
  'component_not_ready': 'System component unavailable or outdated',
  'component_ready': 'System component ready',
  'permission_required': 'Browser reader permission is not connected',
  'permission_not_verified':
      'System authorization did not enable reader access',
  'browser_not_supported':
      'Installed browser is outside the supported configuration',
};
typedef BrowserInventoryReader = Future<JsonResult> Function();
typedef BrowserEventWriter = Future<void> Function(
  String browser,
  String code,
  int? nativeCode,
);

class BrowserSetupCoordinator extends ChangeNotifier {
  BrowserSetupCoordinator({
    required this.platform,
    required this.inventory,
    required this.systemReader,
    required this.log,
    this.firefox,
    this.chrome,
    this.activate,
    this.interval = const Duration(seconds: 30),
  });
  final String platform;
  final BrowserInventoryReader inventory;
  final WebStatusReader systemReader;
  final BrowserEventWriter log;
  final FirefoxSetupService? firefox;
  final ChromeSetupService? chrome;
  final WebComponentActivator? activate;
  final Duration interval;
  JsonResult system = {};
  List<String> configured = const [];
  String? defaultBrowser;
  bool running = false, _disposed = false, _again = false, _forceAgain = false;
  bool _activationAttempted = false, _permissionAttempted = false;
  Timer? _timer;
  DateTime? _lastSystemRead;
  final Map<String, String> _lastEvents = {};

  Future<JsonResult> cachedSystemStatus() async => system;
  bool get hasConfiguredBrowser => configured.isNotEmpty;

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh(forceSystem: true));
  }

  Future<void> _record(String id, String code, [int? nativeCode]) async {
    final signature = '$code/$nativeCode';
    if (_lastEvents[id] == signature) return;
    try {
      await log(id, code, nativeCode);
      _lastEvents[id] = signature;
    } catch (_) {
      /* Logging must not block use of the app. */
    }
  }

  Future<void> refresh({bool forceSystem = false}) async {
    if (_disposed) return;
    if (running) {
      _again = true;
      _forceAgain = _forceAgain || forceSystem;
      return;
    }
    running = true;
    final enabled = <String>{};
    try {
      // Native discovery has its own worker; Linux discovery uses a Dart isolate.
      final found = await inventory().timeout(const Duration(seconds: 15));
      if (_disposed) return;
      final installed = (found['installed'] as List? ?? [])
          .whereType<String>()
          .where(browserNames.containsKey)
          .toSet();
      defaultBrowser = browserNames.containsKey(found['default'])
          ? found['default'] as String
          : null;
      if (installed.isEmpty) await _record('system', 'no_installed_browsers');
      if (found['ok'] != true) {
        await _record(
          'system',
          'browser_inventory_failed',
          found['nativeCode'] as int?,
        );
      }
      if (forceSystem ||
          _lastSystemRead == null ||
          DateTime.now().difference(_lastSystemRead!) >=
              const Duration(minutes: 1)) {
        system = await systemReader().timeout(const Duration(seconds: 40));
        _lastSystemRead = DateTime.now();
        if (platform == 'macos' &&
            system['available'] != true &&
            system['canActivateComponent'] == true &&
            system['componentHostOutdated'] != true &&
            !_activationAttempted &&
            activate != null) {
          _activationAttempted = true;
          final result = await activate!().timeout(const Duration(seconds: 30));
          await _record(
            'system',
            result['ok'] == true
                ? 'component_activated'
                : _code(result),
          );
          system = await systemReader().timeout(const Duration(seconds: 40));
        }
      }
      await _record(
        'system',
        system['available'] == true ? 'component_ready' : 'component_not_ready',
        system['componentStatusCode'] as int?,
      );
      for (final id in installed) {
        if (_disposed) break;
        if ((id == 'edge' && platform != 'windows') ||
            (id == 'safari' && platform != 'macos')) {
          await _record(id, 'browser_not_supported');
          continue;
        }
        if (system['available'] != true) {
          await _record(id, 'component_not_ready');
          continue;
        }
        if (platform != 'linux') {
          // These browsers consume the OS certificate store, not separate modules.
          final states = found['nativeStates'];
          final code = states is Map && states[id] is String
              ? states[id] as String
              : 'configured';
          if (code == 'configured') enabled.add(id);
          await _record(id, code);
        } else if (id == 'chrome' && chrome != null) {
          if (await _configureChrome()) enabled.add(id);
        }
      }
      if (platform == 'linux' &&
          firefox != null &&
          system['available'] == true &&
          installed.any((id) => id.startsWith('firefox'))) {
        enabled.addAll(await _configureFirefox(installed));
      }
    } catch (_) {
      // An incomplete inspection cannot certify a browser from an older snapshot.
      await _record('system', 'browser_setup_unavailable');
    } finally {
      if (!_disposed) {
        configured = enabled.toList()
          ..sort((a, b) {
            if (a == defaultBrowser) return -1;
            if (b == defaultBrowser) return 1;
            return browserNames[a]!.compareTo(browserNames[b]!);
          });
        notifyListeners();
      }
      running = false;
      if (_again && !_disposed) {
        _again = false;
        final force = _forceAgain;
        _forceAgain = false;
        unawaited(refresh(forceSystem: force));
      }
    }
  }

  Future<bool> _configureChrome() async {
    try {
      final status = await chrome!.inspect();
      if (status['ok'] == true && status['state'] == 'configured') {
        await _record('chrome', 'configured');
        return true;
      }
      if (status['state'] != 'needs_setup') {
        await _record('chrome', _code(status));
        return false;
      }
      final plan = await chrome!.plan();
      if (_disposed) return false;
      if (plan['ok'] != true || plan['fingerprint'] is! String) {
        await _record('chrome', _code(plan));
        return false;
      }
      final result = await chrome!.apply(plan['fingerprint'] as String);
      final after = await chrome!.inspect();
      final ready =
          result['ok'] == true &&
          after['ok'] == true &&
          after['state'] == 'configured';
      await _record('chrome', ready ? 'configured' : _code(result));
      return ready;
    } catch (_) {
      await _record('chrome', 'configuration_unavailable');
      return false;
    }
  }

  Future<Set<String>> _configureFirefox(Set<String> installed) async {
    final ready = <String>{};
    try {
      var status = await firefox!.inspect();
      if (status['ok'] != true) {
        await _record('firefox', _code(status));
        return ready;
      }
      final profiles = (status['profiles'] as List? ?? [])
          .whereType<Map>()
          .toList();
      for (final profile in profiles) {
        if (_disposed) break;
        final browser = profile['target'] == 'snap'
            ? 'firefox-snap'
            : 'firefox';
        if (!installed.contains(browser) ||
            profile['state'] == 'profile_uninitialized') {
          continue;
        }
        if (profile['state'] == 'configured') continue;
        if (profile['state'] != 'needs_setup' || profile['id'] is! String) {
          await _record(browser, _code(profile));
          continue;
        }
        final id = profile['id'] as String;
        try {
          final plan = await firefox!.plan(id);
          if (_disposed) break;
          if (plan['ok'] != true || plan['fingerprint'] is! String) {
            await _record(browser, _code(plan));
            continue;
          }
          final result = await firefox!.apply(
            id,
            plan['fingerprint'] as String,
          );
          if (result['ok'] != true) await _record(browser, _code(result));
        } catch (_) {
          await _record(browser, 'configuration_unavailable');
        }
      }
      status = await firefox!.inspect();
      final after = (status['profiles'] as List? ?? []).whereType<Map>();
      final snapConfigured = after.any(
        (p) => p['target'] == 'snap' && p['state'] == 'configured',
      );
      if (snapConfigured &&
          !_disposed &&
          status['snapPermission'] == 'disconnected' &&
          !_permissionAttempted) {
        // The OS may ask the user for authorization. Never repeat a denied prompt.
        _permissionAttempted = true;
        final result = await firefox!.connectPcsc();
        await _record(
          'firefox-snap',
          result['ok'] == true ? 'permission_connected' : _code(result),
        );
        status = await firefox!.inspect();
      }
      final verified = (status['profiles'] as List? ?? []).whereType<Map>();
      for (final id in installed.where((id) => id.startsWith('firefox'))) {
        final target = id == 'firefox-snap' ? 'snap' : 'firefox';
        final configuredProfile =
            status['ok'] == true &&
            verified.any(
              (p) => p['target'] == target && p['state'] == 'configured',
            );
        if (configuredProfile &&
            (target != 'snap' || status['snapPermission'] == 'connected')) {
          ready.add(id);
          await _record(id, 'configured');
        } else if (!verified.any((p) => p['target'] == target)) {
          await _record(id, 'profile_uninitialized');
        } else if (target == 'snap' &&
            status['snapPermission'] != 'connected') {
          await _record(id, 'permission_required');
        }
      }
    } catch (_) {
      await _record('firefox', 'configuration_unavailable');
    }
    return ready;
  }

  String _code(Map result) {
    final code = result['code'] ?? result['state'];
    return code is String && RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(code)
        ? code
        : 'configuration_unavailable';
  }

  String pairedMessage(EnrollmentRecord record) {
    if (record.removalPending) return record.webStatus;
    if (!record.readyForSigning ||
        !record.hasPublicData ||
        !record.webProvisioned ||
        !record.componentAvailable ||
        configured.isEmpty) {
      return browserNotConfigured;
    }
    return 'Accesso ai siti con CIE configurato. Apri il sito nei seguenti browser: ${configured.map((id) => browserNames[id]!).join(', ')}.';
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Always-on, bounded setup log. Only fixed browser IDs, outcome codes and
/// numeric native codes are persisted, never profile paths, card data or PINs.
class BrowserSetupLog {
  BrowserSetupLog({this.directory});
  final Directory? directory;
  Future<void> _tail = Future.value();
  Future<void> record(String browser, String code, int? nativeCode) {
    final next = _tail.catchError((_) {}).then((_) async {
      final root =
          directory ??
          Directory(
            '${(await getPersistentApplicationSupportDirectory()).path}/logs',
          );
      final rootType = await FileSystemEntity.type(
        root.path,
        followLinks: false,
      );
      if (rootType == FileSystemEntityType.link) {
        throw const FileSystemException('Invalid log directory');
      }
      await root.create(recursive: true);
      if (!Platform.isWindows) {
        await Process.run('/bin/chmod', ['700', root.path]);
      }
      final file = File('${root.path}/browser-setup.jsonl');
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('Invalid log file');
      }
      if (await file.exists() && await file.length() > 512 * 1024) {
        final previous = File('${root.path}/browser-setup.previous.jsonl');
        if (await FileSystemEntity.type(previous.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FileSystemException('Invalid log file');
        }
        await file.rename(previous.path);
      }
      final safeCode = RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(code)
          ? code
          : 'unclassified_error';
      final event = {
        'time': DateTime.now().toUtc().toIso8601String(),
        'browser': browserNames.containsKey(browser) ? browser : 'system',
        'code': safeCode,
        'message':
            _outcomeMessages[safeCode] ?? 'Browser setup outcome: $safeCode',
        if (nativeCode != null &&
            nativeCode >= -2147483648 &&
            nativeCode <= 4294967295)
          'nativeCode': nativeCode,
      };
      await file.writeAsString(
        '${jsonEncode(event)}\n',
        mode: FileMode.append,
        flush: true,
      );
      if (!Platform.isWindows) {
        await Process.run('/bin/chmod', ['700', root.path]);
        await Process.run('/bin/chmod', ['600', file.path]);
      }
    });
    _tail = next;
    return next;
  }
}

Future<JsonResult> readBrowserInventory() async {
  if (Platform.isWindows) {
    const channel = MethodChannel('cie.id/windows-web-setup');
    await channel.invokeMethod<bool>('checkBrowsers');
    for (var attempt = 0; attempt < 50; attempt++) {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'browserStatus',
      );
      if (result?['pending'] != true) {
        return _withNativeFirefoxState(Map<String, dynamic>.from(result ?? {}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return {'ok': false, 'code': 'browser_inventory_timeout'};
  }
  if (Platform.isMacOS) {
    final result = await const MethodChannel('cie.prototype/web')
        .invokeMapMethod<String, dynamic>('browserInventory');
    return _withNativeFirefoxState(Map<String, dynamic>.from(result ?? {}));
  }
  return Isolate.run(_linuxBrowserInventory);
}

Future<JsonResult> _withNativeFirefoxState(JsonResult found) async {
  if ((found['installed'] as List? ?? []).contains('firefox')) {
    try {
      found['nativeStates'] = {
        'firefox': await Isolate.run(_nativeFirefoxState),
      };
    } catch (_) {
      // A damaged Firefox profile must not hide healthy OS-store browsers.
      found['nativeStates'] = {'firefox': 'profile_inspection_failed'};
    }
  }
  return found;
}

String _nativeFirefoxState() {
  final base = Platform.isWindows
      ? '${Platform.environment['APPDATA']}/Mozilla/Firefox'
      : '${Platform.environment['HOME']}/Library/Application Support/Firefox';
  return inspectNativeFirefoxProfiles(Directory(base));
}

String inspectNativeFirefoxProfiles(Directory base) {
  // Read initialized profiles only. Firefox's built-in OS client-certificate
  // module is enabled by default. Never overwrite an explicit user override.
  final index = File('${base.path}/profiles.ini');
  if (!index.existsSync() || index.lengthSync() > 1024 * 1024) {
    return 'profile_uninitialized';
  }
  var profiles = 0, enabled = 0;
  final sections = index.readAsStringSync().split(
    RegExp(r'^\[', multiLine: true),
  );
  for (final section in sections.where((s) => s.startsWith('Profile'))) {
    final path = RegExp(
      r'^Path=(.+)$',
      multiLine: true,
    ).firstMatch(section)?.group(1)?.trim();
    if (path == null || path.split(RegExp(r'[/\\]')).contains('..')) continue;
    final relative = !RegExp(
      r'^IsRelative=0\s*$',
      multiLine: true,
    ).hasMatch(section);
    final directory = Directory(relative ? '${base.path}/$path' : path);
    if ((!relative && !directory.isAbsolute) ||
        FileSystemEntity.typeSync(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      continue;
    }
    final preferences = File('${directory.path}/prefs.js');
    if (FileSystemEntity.typeSync(preferences.path, followLinks: false) !=
            FileSystemEntityType.file ||
        preferences.lengthSync() > 2 * 1024 * 1024) {
      continue;
    }
    profiles++;
    var configured = true;
    for (final name in ['prefs.js', 'user.js']) {
      final file = File('${directory.path}/$name');
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          file.lengthSync() > 2 * 1024 * 1024) {
        continue;
      }
      final matches = RegExp(
        r'''user_pref\(\s*["']security\.osclientcerts\.autoload["']\s*,\s*(true|false)\s*\)''',
      ).allMatches(file.readAsStringSync());
      if (matches.isNotEmpty) configured = matches.last.group(1) == 'true';
    }
    if (configured) enabled++;
  }
  return enabled > 0
      ? 'configured'
      : profiles == 0
      ? 'profile_uninitialized'
      : 'os_certificates_disabled';
}

Future<JsonResult> _linuxBrowserInventory() async {
  bool exists(String path) => File(path).existsSync();
  final snap = exists('/snap/bin/firefox');
  final installed = <String>[
    if (exists('/usr/bin/google-chrome') ||
        exists('/usr/bin/google-chrome-stable') ||
        exists('/opt/google/chrome/chrome'))
      'chrome',
    if (exists('/usr/lib/firefox/firefox') ||
        exists('/opt/firefox/firefox') ||
        (!snap && exists('/usr/bin/firefox')))
      'firefox',
    if (snap) 'firefox-snap',
    if (exists('/usr/bin/microsoft-edge') ||
        exists('/usr/bin/microsoft-edge-stable'))
      'edge',
  ];
  String? selected;
  Process? process;
  try {
    process = await Process.start('/usr/bin/xdg-settings', [
      'get',
      'default-web-browser',
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    final result = await Future.wait([process.exitCode, output, errors])
        .timeout(const Duration(seconds: 5));
    final text = result[1] as String;
    if (text.length < 4096) {
      if (text.contains('firefox_firefox')) {
        selected = 'firefox-snap';
      } else if (text.contains('firefox')) {
        selected = 'firefox';
      } else if (text.contains('google-chrome')) {
        selected = 'chrome';
      } else if (text.contains('microsoft-edge')) {
        selected = 'edge';
      }
    }
  } catch (_) {
    process?.kill();
  }
  return {'ok': true, 'installed': installed, 'default': selected};
}
