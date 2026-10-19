// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData cieTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff4c65ad),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff7f8fc)
        : scheme.surface,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

class AppThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  void select(String code) {
    final next = switch (code) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mode == next) return;
    mode = next;
    notifyListeners();
    const MethodChannel('cie.id/application')
        .invokeMethod<void>('setTheme', code)
        .catchError((_) {});
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppThemeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.notifier;
}
