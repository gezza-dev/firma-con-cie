import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/signature_appearance.dart';

void main() {
  for (final viewport in [
    (const Size(900, 600), 1.0),
    (const Size(640, 480), 1.5),
    (const Size(360, 480), 1.5),
  ]) {
    testWidgets('preview actions stay visible at $viewport', (tester) async {
      tester.view.physicalSize = viewport.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var confirmations = 0, cancellations = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(viewport.$2)),
            child: child!,
          ),
          home: Scaffold(
            body: SignatureAppearanceDialog(
              content: const SizedBox(
                height: 1200,
                child: Text('Anteprima PDF'),
              ),
              actions: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => cancellations++,
                    child: const Text('Annulla'),
                  ),
                  FilledButton(
                    onPressed: () => confirmations++,
                    child: const Text('Conferma anteprima'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final cancel = find.widgetWithText(TextButton, 'Annulla');
      final confirm = find.widgetWithText(FilledButton, 'Conferma anteprima');
      expect(cancel.hitTestable(), findsOneWidget);
      expect(confirm.hitTestable(), findsOneWidget);
      final footerBefore = tester.getRect(confirm);
      final scrollArea = tester.getRect(find.byType(SingleChildScrollView));
      expect(footerBefore.top, greaterThanOrEqualTo(scrollArea.bottom));
      expect(footerBefore.bottom, lessThanOrEqualTo(viewport.$1.height));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(confirm), footerBefore);
      await tester.tap(confirm);
      await tester.tap(cancel);
      expect(confirmations, 1);
      expect(cancellations, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
