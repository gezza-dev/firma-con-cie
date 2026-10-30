// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/card_observation_process.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/card_monitor.dart';

void main() {
  late Directory temporary;
  late String fixture;
  final workers = <CardObservationProcess>[];
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('cie-observer-test-');
    final packages = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    );
    final flutter = (packages['packages'] as List).singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk =
        Uri.parse(
              '${(flutter['rootUri'] as String).replaceFirst(RegExp(r'/$'), '')}/',
            )
            .resolve(
              '../../bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
            )
            .toFilePath();
    fixture =
        '${temporary.path}/fake_observer${Platform.isWindows ? '.exe' : ''}';
    final compiled = await Process.run(sdk, [
      'compile',
      'exe',
      'test/fixtures/observation_child.dart',
      '-o',
      fixture,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });
  tearDown(() async {
    for (final w in workers) {
      await w.close();
    }
    workers.clear();
  });
  tearDownAll(() async => temporary.delete(recursive: true));

  CardObservationProcess worker(
    String mode, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    final w = CardObservationProcess(fixture, [
      mode,
      '${temporary.path}/${DateTime.now().microsecondsSinceEpoch}.txt',
    ], timeout: timeout);
    workers.add(w);
    return w;
  }

  Future<void> entered(CardObservationProcess w) async {
    final file = File(w.arguments[1]);
    for (var i = 0; i < 100; i++) {
      if (file.existsSync() && file.readAsLinesSync().length > 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Synthetic worker did not receive its command');
  }

  Future<void> reaped(CardObservationProcess w) async {
    final child = int.parse(File(w.arguments[1]).readAsLinesSync().first);
    if (Platform.isWindows) {
      final list = await Process.run('tasklist', [
        '/FI',
        'PID eq $child',
        '/FO',
        'CSV',
        '/NH',
      ]);
      expect('${list.stdout}', isNot(contains('"$child"')));
    } else {
      final probe = await Process.run('/bin/kill', ['-0', '$child']);
      expect(probe.exitCode, isNot(0), reason: 'child survived cleanup');
    }
  }

  test('persistent worker reports insertion/removal and serializes manual detection', () async {
    final w = worker('normal');
    final inserted = await w.query(),
        removed = await w.query(),
        manual = await w.query(manual: true);
    expect(inserted['readers'], hasLength(1));
    expect(removed['readers'], isEmpty);
    expect(inserted['pid'], removed['pid']);
    expect(manual['pid'], inserted['pid']);
    await reaped(w); // one-shot detection must not keep a CLI tool alive
    expect(File(w.arguments[1]).readAsLinesSync().skip(1), [
      'observe',
      'observe',
      'detect',
    ]);
    await w.close();
    await reaped(w);
  });
  test(
    'hung PCSC times out, child is reaped, cooldown prevents restart storm',
    () async {
      final w = worker('hang', timeout: const Duration(milliseconds: 500));
      final result = await w.query();
      expect(result['code'], 'pcsc_timeout');
      await reaped(w);
      expect((await w.query())['code'], 'pcsc_timeout');
      expect(File(w.arguments[1]).readAsLinesSync().length, 2);
    },
  );
  test('closing while reader is hung interrupts immediately without waiting for deadline', () async {
    final w = worker('hang', timeout: const Duration(seconds: 30));
    final query = w.query();
    await entered(w);
    expect((await w.query())['code'], 'busy');
    final watch = Stopwatch()..start();
    await w.close();
    expect((await query)['code'], 'observation_cancelled');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    await reaped(w);
  });
  for (final mode in ['crash', 'malformed', 'flood']) {
    test('$mode is bounded and cannot leave a child alive', () async {
      final w = worker(mode);
      expect((await w.query())['ok'], false);
      await w.close();
      await reaped(w);
    });
  }
  test(
    'missing helper fails closed with no in-process PCSC fallback',
    () async {
      final w = CardObservationProcess('${temporary.path}/missing', []);
      workers.add(w);
      expect((await w.query())['code'], 'pcsc_unavailable');
    },
  );
  test(
    'cancelling during process startup cannot leave a late worker running',
    () async {
      final w = worker('hang');
      final query = w.query();
      await w.close();
      expect((await query)['code'], 'observation_cancelled');
      if (File(w.arguments[1]).existsSync()) await reaped(w);
    },
  );
  test(
    'Ffi service releases busy state after observation is cancelled',
    () async {
      final w = worker('hang', timeout: const Duration(seconds: 30));
      final service = FfiCieService(
        const BridgePaths('missing', 'missing', ''),
        observationProcess: w,
      );
      final monitor = CardMonitor(service);
      await monitor.setPaused(false);
      await entered(w);
      final pause = monitor.setPaused(true);
      await service
          .cancelCardObservation(); // Explicit app shutdown, not an edit pause.
      await pause.timeout(const Duration(seconds: 2));
      await reaped(w);
      expect((await service.load())['code'], 'native_unavailable');
      monitor.dispose();
    },
  );
}
