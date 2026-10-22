// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Shared Material 3 palette: logo blue in light mode, pale green accents in
// dark mode. All three desktop platforms use the same component color roles.
const cieLogoBlue = Color(0xff4c65ad);
const cieDarkGreenSeed = Color(0xff7bbf8e);

ColorScheme _darkGreenControls(ColorScheme base) {
  final green = ColorScheme.fromSeed(
    seedColor: cieDarkGreenSeed,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  // Change interactive accents as paired Material roles, retaining the current
  // window/card surfaces, neutral text and red error colors.
  return base.copyWith(
    primary: green.primary,
    onPrimary: green.onPrimary,
    primaryContainer: green.primaryContainer,
    onPrimaryContainer: green.onPrimaryContainer,
    primaryFixed: green.primaryFixed,
    primaryFixedDim: green.primaryFixedDim,
    onPrimaryFixed: green.onPrimaryFixed,
    onPrimaryFixedVariant: green.onPrimaryFixedVariant,
    secondary: green.secondary,
    onSecondary: green.onSecondary,
    secondaryContainer: green.secondaryContainer,
    onSecondaryContainer: green.onSecondaryContainer,
    secondaryFixed: green.secondaryFixed,
    secondaryFixedDim: green.secondaryFixedDim,
    onSecondaryFixed: green.onSecondaryFixed,
    onSecondaryFixedVariant: green.onSecondaryFixedVariant,
    tertiary: green.tertiary,
    onTertiary: green.onTertiary,
    tertiaryContainer: green.tertiaryContainer,
    onTertiaryContainer: green.onTertiaryContainer,
    tertiaryFixed: green.tertiaryFixed,
    tertiaryFixedDim: green.tertiaryFixedDim,
    onTertiaryFixed: green.onTertiaryFixed,
    onTertiaryFixedVariant: green.onTertiaryFixedVariant,
    inversePrimary: green.inversePrimary,
    surfaceTint: green.surfaceTint,
  );
}

ThemeData cieTheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: cieLogoBlue,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    // Keep the light window background matched to the existing app icon base.
    surface: brightness == Brightness.light ? const Color(0xfff7f8fc) : null,
  );
  final scheme = brightness == Brightness.dark
      ? _darkGreenControls(base)
      : base;
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
  final baseMenuLabel = theme.typography.englishLike
      .merge(theme.textTheme)
      .labelMedium!;
  final menuLabel = baseMenuLabel.copyWith(
    fontSize: baseMenuLabel.fontSize! + 1,
  );
  // Buttons, inputs, dialogs and selection controls use Material defaults,
  // including paired foreground/background colors and disabled/hover states.
  // Preserve the existing rail typography and layout.
  return theme.copyWith(
    navigationRailTheme: NavigationRailThemeData(
      selectedLabelTextStyle: menuLabel.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      unselectedLabelTextStyle: menuLabel.copyWith(
        color: scheme.onSurfaceVariant,
      ),
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
