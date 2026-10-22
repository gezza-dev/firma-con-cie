// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cie_flutter_prototype/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  test(
    'green accents apply only to dark controls, preserving existing surfaces',
    () {
      final dark = cieTheme(Brightness.dark).colorScheme;
      final previous = ColorScheme.fromSeed(
        seedColor: cieLogoBlue,
        brightness: Brightness.dark,
      );
      final light = cieTheme(Brightness.light).colorScheme;
      final previousLight = ColorScheme.fromSeed(
        seedColor: cieLogoBlue,
        surface: const Color(0xfff7f8fc),
      );
      expect(light, previousLight);
      expect(dark.primary.g, greaterThan(dark.primary.r));
      expect(dark.primary.g, greaterThan(dark.primary.b));
      expect(dark.primary.computeLuminance(), greaterThan(.5));
      expect(dark.surface, previous.surface);
      expect(dark.surfaceContainerLow, previous.surfaceContainerLow);
      expect(dark.surfaceContainerHighest, previous.surfaceContainerHighest);
      expect(dark.onSurface, previous.onSurface);
      expect(dark.error, previous.error);
    },
  );

  for (final brightness in Brightness.values) {
    test(
      'Material $brightness roles remain readable and match app icon bases',
      () {
        final theme = cieTheme(brightness), scheme = theme.colorScheme;
        expect(theme.useMaterial3, true);
        final backgrounds =
            (jsonDecode(File('assets/branding/themes.json').readAsStringSync())
                    as Map)['themes']
                as Map;
        expect(
          scheme.surface.toARGB32(),
          int.parse(
            (backgrounds[brightness.name] as String).replaceFirst('#', 'ff'),
            radix: 16,
          ),
        );
        expect(theme.scaffoldBackgroundColor, scheme.surface);
        // All ordinary text color pairs actually used by Material controls.
        for (final pair in [
          (scheme.onPrimary, scheme.primary),
          (scheme.onPrimaryContainer, scheme.primaryContainer),
          (scheme.onSecondaryContainer, scheme.secondaryContainer),
          (scheme.onSurface, scheme.surface),
          (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
          (scheme.primary, scheme.surface),
          (scheme.primary, scheme.surfaceContainerLow),
          (scheme.onError, scheme.error),
          (scheme.error, scheme.surface),
        ]) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness: ${pair.$1} on ${pair.$2}',
          );
        }
        expect(
          contrast(scheme.outline, scheme.surface),
          greaterThanOrEqualTo(3),
        );
      },
    );

    testWidgets(
      'Material $brightness controls use coordinated roles and states',
      (t) async {
        final theme = cieTheme(brightness), scheme = theme.colorScheme;
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Filled')),
                  const FilledButton(onPressed: null, child: Text('Disabled')),
                  TextButton(onPressed: () {}, child: const Text('Text')),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Outlined'),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Elevated'),
                  ),
                ],
              ),
            ),
          ),
        );
        final filledFinder = find.widgetWithText(FilledButton, 'Filled');
        final filled = t.widget<FilledButton>(filledFinder);
        final context = t.element(filledFinder);
        final style = filled
            .defaultStyleOf(context)
            .merge(filled.themeStyleOf(context))
            .merge(filled.style);
        expect(style.backgroundColor!.resolve({}), scheme.primary);
        expect(style.foregroundColor!.resolve({}), scheme.onPrimary);
        expect(
          style.backgroundColor!.resolve({WidgetState.disabled})!.toARGB32(),
          scheme.onSurface.withValues(alpha: .12).toARGB32(),
        );
        expect(
          style.foregroundColor!.resolve({WidgetState.disabled})!.toARGB32(),
          scheme.onSurface.withValues(alpha: .38).toARGB32(),
        );
        for (final state in [
          WidgetState.hovered,
          WidgetState.focused,
          WidgetState.pressed,
        ]) {
          final overlay = style.overlayColor!.resolve({state})!;
          expect(overlay.a, greaterThan(0));
          final background = Color.alphaBlend(overlay, scheme.primary);
          expect(
            contrast(scheme.onPrimary, background),
            greaterThanOrEqualTo(4.5),
          );
        }
        for (final type in [TextButton, OutlinedButton, ElevatedButton]) {
          final finder = find.byType(type);
          final button = t.widget<ButtonStyleButton>(finder);
          final context = t.element(finder);
          final style = switch (button) {
            TextButton b =>
              b
                  .defaultStyleOf(context)
                  .merge(b.themeStyleOf(context))
                  .merge(b.style),
            OutlinedButton b =>
              b
                  .defaultStyleOf(context)
                  .merge(b.themeStyleOf(context))
                  .merge(b.style),
            ElevatedButton b =>
              b
                  .defaultStyleOf(context)
                  .merge(b.themeStyleOf(context))
                  .merge(b.style),
            _ => throw StateError('Unexpected button'),
          };
          expect(style.foregroundColor!.resolve({}), scheme.primary);
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }
}
