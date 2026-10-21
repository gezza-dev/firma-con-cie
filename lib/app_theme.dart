// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData cieTheme(Brightness brightness) {
  final caption = brightness == Brightness.dark
      ? const Color(0xff8dceff)
      : const Color(0xff0076a8);
  // Share the existing azure accent with every Material control, including
  // radios, sliders, switches, progress indicators and focused input borders.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff0076a8),
    brightness: brightness,
    primary: caption,
  );
  final theme = ThemeData(
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
  // Keep the azure captions readable on both surfaces and filled buttons.
  WidgetStateProperty<Color?> enabledColor(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? null : color,
      );
  final outlineStyle = ButtonStyle(foregroundColor: enabledColor(caption));
  final filledStyle = ButtonStyle(
    foregroundColor: enabledColor(const Color(0xff8dceff)),
    backgroundColor: enabledColor(const Color(0xff14394f)),
  );
  final baseMenuLabel = theme.typography.englishLike
      .merge(theme.textTheme)
      .labelMedium!;
  final menuLabel = baseMenuLabel.copyWith(
    fontSize: baseMenuLabel.fontSize! + 1,
    color: scheme.onSurface,
  );
  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(style: outlineStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlineStyle),
    filledButtonTheme: FilledButtonThemeData(style: filledStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: filledStyle),
    navigationRailTheme: NavigationRailThemeData(
      selectedLabelTextStyle: menuLabel,
      unselectedLabelTextStyle: menuLabel,
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
