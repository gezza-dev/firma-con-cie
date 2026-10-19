// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

// Shared lifecycle: one bounded PC/SC observation in flight, none while private
// work, a modal, or an inactive application owns the interaction. Never a PIN.
class CardMonitor extends ChangeNotifier {
  CardMonitor(
    this.service, {
    this.interval = const Duration(seconds: 1),
    this.afterChange,
  });
  final CardObservationService service;
  final Duration interval;
  final Future<void> Function()? afterChange;
  List<JsonResult> readers = [];
  String? code;
  bool checked = false;
  bool _paused = true, _disposed = false;
  int _generation = 0, _systemTicks = 5;
  Timer? _timer;
  Future<void>? _flight;
  String _snapshot = '';
  Future<void> setPaused(bool value) async {
    if (_disposed) return;
    if (!value && !_paused && (_timer?.isActive ?? false)) return;
    if (_paused != value) {
      _paused = value;
      _generation++;
      if (!value) _systemTicks = 5;
    }
    _timer?.cancel();
    if (value) {
      await _flight;
      return;
    }
    if (_flight == null) {
      unawaited(_tick());
    } else {
      await _flight;
      if (!_disposed && !_paused) _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && !_paused) {
      _timer = Timer(interval, () => unawaited(_tick()));
    }
  }

  Future<void> _tick() async {
    if (_disposed || _paused || _flight != null) return;
    final generation = _generation;
    final done = Completer<void>();
    _flight = done.future;
    try {
      final result = await service.observeCards();
      if (_disposed ||
          _paused ||
          generation != _generation ||
          result['code'] == 'busy') {
        return;
      }
      final next = jsonEncode(result);
      if (next != _snapshot || (afterChange != null && ++_systemTicks >= 5)) {
        _systemTicks = 0;
        await afterChange?.call();
        if (_disposed || _paused || generation != _generation) return;
        _snapshot = next;
        code = result['ok'] == true ? null : result['code'] as String?;
        checked = true;
        readers = result['ok'] == true
            ? (result['readers'] as List? ?? [])
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList()
            : [];
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed &&
          !_paused &&
          generation == _generation &&
          code != 'pcsc_unavailable') {
        code = 'pcsc_unavailable';
        checked = true;
        readers = [];
        notifyListeners();
      }
    } finally {
      _flight = null;
      done.complete();
      _schedule();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
