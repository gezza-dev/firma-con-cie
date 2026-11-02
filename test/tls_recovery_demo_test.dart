// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/tls_recovery_demo.dart';

void main() {
  for (final scenario in ['refuse', 'success', 'failure']) {
    testWidgets('interactive TLS simulation: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TlsRecoveryDemo());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('nessun certificato viene rimosso'),
        findsOneWidget,
      );
      if (scenario == 'failure') {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Simula certificati HTTPS mancanti'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aggiornamento dei certificati di sicurezza'),
        findsOneWidget,
      );
      await tester.tap(
        find.text(scenario == 'refuse' ? 'Non ora' : 'Consenti e riprova'),
      );
      await tester.pump();
      if (scenario != 'refuse') {
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.textContaining('Recupero simulato in corso'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('simulation-result')))
            .data,
        contains(
          scenario == 'refuse'
              ? 'consenso negato'
              : scenario == 'success'
              ? 'recupero riuscito'
              : 'recupero non riuscito',
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });
  }
}
