import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

UnifiedFake pairedService() => UnifiedFake()
  ..records['TEST'] = {
    'card': 'TEST',
    'fullName': 'Nome Cognome',
    'version': 2,
    'publicDataSaved': true,
    'readyForSigning': true,
    'certificateHex': '300100',
  };

class ConflictingService extends UnifiedFake {
  @override
  Future<JsonResult> completeEnrollment(String card) async {
    completeCalls++;
    return {
      'ok': true,
      ...records[card]!,
      'code': 'web_certificate_conflict',
      'message': 'Completa la configurazione.',
    };
  }
}

void size(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'legacy Web-only records still offer pairing rather than claiming signing is available',
    (t) async {
      size(t);
      final service = UnifiedFake()..records['TEST'] = {'card': 'TEST'};
      final system = PublicSystem()..available = false;
      system.cards.add('TEST');
      await t.pumpWidget(
        CiePrototype(
          service: service,
          settings: MemorySettingsStore(),
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Completa abbinamento'), findsOneWidget);
      expect(find.text('Informazioni accesso ai siti'), findsNothing);
      expect(service.completeCalls, 0);
      expect(service.enrollCalls, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'published certificate with missing component explains activation without republishing or PIN',
    (t) async {
      size(t);
      final service = pairedService();
      final system = PublicSystem()..available = false;
      system.cards.add('TEST');
      await t.pumpWidget(
        CiePrototype(
          service: service,
          settings: MemorySettingsStore(),
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Completa accesso ai siti'), findsNothing);
      await t.tap(find.text('Informazioni accesso ai siti'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(EnrollmentRecord.componentActivationMessage),
        findsOneWidget,
      );
      expect(service.completeCalls, 0);
      expect(service.enrollCalls, 0);
      expect(system.publications, 0);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completion shows its result immediately when the component still needs activation',
    (t) async {
      size(t);
      final service = pairedService();
      final system = PublicSystem()..available = false;
      await t.pumpWidget(
        CiePrototype(
          service: service,
          settings: MemorySettingsStore(),
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Completa accesso ai siti'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(EnrollmentRecord.componentActivationMessage),
        findsWidgets,
      );
      expect(service.completeCalls, 1);
      expect(service.enrollCalls, 0);
      expect(system.publications, 1);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Chiudi'));
      await t.pumpAndSettle();
      expect(find.text('Informazioni accesso ai siti'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  test('completion preserves the actionable certificate conflict rather than inviting another retry', () async {
    final service = ConflictingService();
    service.records.addAll(pairedService().records);
    final system = PublicSystem();
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.refresh();
    await controller.complete('TEST');
    expect(controller.message, contains('già associato a un altro componente'));
    expect(controller.message, contains('Non occorre ripetere il PIN'));
    expect(service.completeCalls, 1);
    expect(service.enrollCalls, 0);
    expect(system.publications, 0);
  });
}
