// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cie_flutter_prototype/app_notification.dart';
import 'package:cie_flutter_prototype/app_localizations.dart';

void main() {
  for (final language in ['it', 'en']) {
    testWidgets('informational dialog closes with the $language label', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: CieLocalizations.supportedLocales,
          localizationsDelegates: const [
            CieLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(
            body: AppNotification(message: 'Operazione terminata.'),
          ),
        ),
      );
      await t.pumpAndSettle();
      final label = language == 'it' ? 'Chiudi' : 'OK';
      expect(find.widgetWithText(TextButton, label), findsOneWidget);
      expect(find.text(language == 'it' ? 'OK' : 'Chiudi'), findsNothing);
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets(
    'long notification is scrollable, wraps and has a reachable close action',
    (t) async {
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final message = List.filled(
        80,
        'Un messaggio completo e leggibile.',
      ).join('\n');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppNotification(message: message)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(t.widget<Text>(find.text(message)).softWrap, isTrue);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'two notifications are serialized; a theme rebuild never replays them',
    (t) async {
      final theme = ValueNotifier(ThemeMode.light);
      addTearDown(theme.dispose);
      final visibility = <bool>[];
      await t.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: theme,
          builder: (_, mode, _) => MaterialApp(
            themeMode: mode,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: AppNotificationScope(
              onVisibilityChanged: visibility.add,
              child: const Scaffold(
                body: Column(
                  children: [
                    AppNotification(message: 'Primo avviso'),
                    AppNotification(message: 'Secondo avviso'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Primo avviso'), findsOneWidget);
      expect(find.text('Secondo avviso'), findsNothing);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Secondo avviso'), findsOneWidget);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      theme.value = ThemeMode.dark;
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(visibility, [true, false, true, false]);
    },
  );

  testWidgets(
    'a new event with identical wording is presented once after completion',
    (t) async {
      final event = ValueNotifier<Object?>(null);
      addTearDown(event.dispose);
      var acknowledged = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<Object?>(
              valueListenable: event,
              builder: (_, value, _) => AppNotification(
                message: value == null ? null : 'Operazione terminata.',
                event: value,
                enabled: true,
                onDismissed: () {
                  acknowledged++;
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        event.value = Object();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await t.tap(find.text('Chiudi'));
        await t.pumpAndSettle();
      }
      expect(acknowledged, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
