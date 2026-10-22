// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef ObservationResult = Map<String, dynamic>;

// Only public observation runs here. Private operations continue through the
// original bridge and can never be killed, timed out or retried by this class.
class CardObservationProcess {
  CardObservationProcess(
    this.executable,
    this.arguments, {
    this.timeout = const Duration(seconds: 5),
    this.cooldown = const Duration(seconds: 8),
  });
  final String executable;
  final List<String> arguments;
  final Duration timeout, cooldown;
  _Worker? _worker;
  Future<ObservationResult>? _flight;
  int _generation = 0;
  DateTime? _retryAfter;
  bool _closed = false;

  static ObservationResult failure(String code) => {
    'ok': false,
    'code': code,
    'readers': <dynamic>[],
  };

  Future<ObservationResult> query({bool manual = false}) {
    if (_closed) return Future.value(failure('observation_cancelled'));
    if (_flight != null) return Future.value(failure('busy'));
    if (!manual &&
        _retryAfter != null &&
        DateTime.now().isBefore(_retryAfter!)) {
      return Future.value(failure('pcsc_timeout'));
    }
    final generation = _generation;
    final result = _query(generation, manual);
    _flight = result;
    unawaited(
      result.whenComplete(() {
        if (identical(_flight, result)) _flight = null;
      }),
    );
    return result;
  }

  Future<ObservationResult> _query(int generation, bool manual) async {
    try {
      return await (() async {
        var worker = _worker;
        if (worker == null) {
          // No shell, PIN, reader identifier or document path in argv.
          final process = await Process.start(
            executable,
            arguments,
            workingDirectory: File(executable).absolute.parent.path,
          );
          worker = _Worker(process);
          if (_closed || generation != _generation) {
            await worker.stop();
            return failure('observation_cancelled');
          }
          _worker = worker;
        }
        final result = await worker.request(manual ? 'detect' : 'observe');
        if (worker.dead) {
          await cancel();
        } else if (result['ok'] == true) {
          _retryAfter = null;
        }
        // Explicit detection is a one-shot operation, also used by CLI tools.
        // Do not keep their event loop alive with an unused child afterwards.
        if (manual) await cancel();
        return result;
      })().timeout(timeout);
    } on TimeoutException {
      _retryAfter = DateTime.now().add(cooldown);
      await cancel();
      return failure('pcsc_timeout');
    } on Object {
      await cancel();
      return failure('pcsc_unavailable');
    }
  }

  Future<void> cancel() async {
    ++_generation;
    final worker = _worker;
    _worker = null;
    await worker?.stop();
  }

  Future<void> close() async {
    _closed = true;
    await cancel();
  }
}

class _Worker {
  _Worker(this.process) {
    _stdout = process.stdout.listen(
      _read,
      onError: (_) => _failed(),
      onDone: _failed,
    );
    // Backend diagnostics are drained, never accumulated or shown as identity data.
    _stderr = process.stderr.listen((_) {}, onError: (_) {});
    unawaited(process.exitCode.then((_) => _failed()));
  }
  static const prefix = 'CIE_OBSERVER_JSON=';
  static const maxBytes = 256 * 1024;
  final Process process;
  late final StreamSubscription<List<int>> _stdout, _stderr;
  Completer<ObservationResult>? _response;
  final List<int> _buffer = [];
  int _bytes = 0;
  bool _dead = false;
  bool get dead => _dead;
  Future<void>? _stopping;

  Future<ObservationResult> request(String command) {
    if (_dead || _response != null) throw StateError('worker unavailable');
    _bytes = 0;
    final response = _response = Completer<ObservationResult>();
    process.stdin.writeln(command);
    return response.future;
  }

  void _read(List<int> bytes) {
    if (_dead) return;
    _bytes += bytes.length;
    if (_bytes > maxBytes) {
      _failed();
      return;
    }
    for (final byte in bytes) {
      if (byte != 10) {
        _buffer.add(byte);
        continue;
      }
      try {
        final line = utf8.decode(_buffer).trim();
        _buffer.clear();
        if (!line.startsWith(prefix)) continue;
        final result = jsonDecode(line.substring(prefix.length));
        if (result is! Map<String, dynamic> ||
            result['ok'] is! bool ||
            (result['ok'] == true && result['readers'] is! List)) {
          throw const FormatException('invalid observation');
        }
        final response = _response;
        if (response == null) {
          throw const FormatException('unsolicited response');
        }
        _response = null;
        response.complete(result);
      } on Object {
        _failed();
        return;
      }
    }
  }

  void _failed() {
    _dead = true;
    final response = _response;
    _response = null;
    response?.complete(CardObservationProcess.failure('pcsc_unavailable'));
    // Also reap a worker which flooded output or broke the protocol.
    unawaited(stop());
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    _dead = true;
    final response = _response;
    _response = null;
    response?.complete(CardObservationProcess.failure('observation_cancelled'));
    // EOF works even while the operation thread is stuck. SIGKILL/TerminateProcess
    // bounds cleanup if the loader or runtime cannot service the EOF watchdog.
    unawaited(process.stdin.close().catchError((_) {}));
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on Object {
      /* No native thread in the GUI process can prevent its exit. */
    }
    await _stdout.cancel();
    await _stderr.cancel();
  }
}
