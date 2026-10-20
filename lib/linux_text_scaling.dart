// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Uses GTK's logical font DPI only when the Linux engine has no text scaling.
/// This replaces the default scaler; it never multiplies the engine's scaler
/// or the display's devicePixelRatio.
class LinuxTextScaling extends StatefulWidget {
  const LinuxTextScaling({super.key, required this.child});

  final Widget child;

  @override
  State<LinuxTextScaling> createState() => _LinuxTextScalingState();
}

class _LinuxTextScalingState extends State<LinuxTextScaling> {
  static const _channel = MethodChannel('cie.id/linux_text_scaling');
  double _gtkScale = 1;
  bool _receivedChange = false;
  late final bool _enabled =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    if (_enabled) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'textScaleChanged') {
          _receivedChange = true;
          _update(call.arguments);
        }
      });
      unawaited(_readInitialScale());
    }
  }

  Future<void> _readInitialScale() async {
    try {
      final scale = await _channel.invokeMethod<Object?>('getTextScale');
      // A settings notification can arrive while the initial reply is pending.
      if (!_receivedChange) _update(scale);
    } on MissingPluginException {
      // Older runners and widget tests retain Flutter's normal behaviour.
    } on PlatformException {
      // An unavailable desktop setting must not prevent startup.
    }
  }

  void _update(Object? value) {
    if (!mounted || value is! num) return;
    final scale = value.toDouble();
    if (!scale.isFinite || scale <= 0 || scale == _gtkScale) return;
    setState(() => _gtkScale = scale);
  }

  @override
  void dispose() {
    if (_enabled) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!_enabled ||
        _gtkScale == 1 ||
        media.textScaler != TextScaler.noScaling) {
      return widget.child;
    }
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(_gtkScale)),
      child: widget.child,
    );
  }
}
