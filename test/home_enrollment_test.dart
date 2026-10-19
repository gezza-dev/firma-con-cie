// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/card_monitor.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/diagnostics.dart';
import 'package:cie_flutter_prototype/app_settings.dart';

import 'widget_test.dart' show FakeService;
import 'signing_helpers.dart';

class UnifiedFake extends FakeService
    implements CardObservationService, EnrollmentService {
  int observations = 0, enrollCalls = 0, completeCalls = 0, forgetCalls = 0;
  bool rejectPin = false, locked = false, removeFailed = false;
  JsonResult presence = {'ok': true, 'readers': <JsonResult>[]};
  final records = <String, JsonResult>{};
  final invalidated = <String>[];
  Completer<JsonResult>? pending;
  @override
  Future<JsonResult> load() async => {
    'ok': true,
    'canPair': true,
    'canSign': true,
    'canObserveCards': true,
    'enrollmentVersion': 2,
  };
  @override
  Future<JsonResult> observeCards() async {
    observations++;
    return pending?.future ?? presence;
  }

  @override
  Future<JsonResult> enrollments() async => locked
      ? {'ok': false, 'invalidatedCards': invalidated}
      : {
          'ok': true,
          'records': records.values.toList(),
          'invalidatedCards': invalidated,
        };
  @override
  Future<JsonResult> webStatus() async => {'ok': true, 'available': false};
  @override
  Future<JsonResult> enroll(String reader, String card, String pin) async {
    enrollCalls++;
    if (rejectPin) {
      return {
        'ok': false,
        'code': 'pin_incorrect',
        'message': 'PIN non accettato. Nessun tentativo automatico.',
      };
    }
    records[card] = {
      'card': card,
      'fullName': 'Nome Cognome',
      'version': 2,
      'publicDataSaved': true,
      'readyForSigning': true,
      'certificateHex': '300100',
    };
    return {'ok': true, ...records[card]!};
  }

  @override
  Future<JsonResult> completeEnrollment(String card) async {
    completeCalls++;
    return {'ok': true, ...records[card]!};
  }

  @override
  Future<JsonResult> forgetEnrollment(String card) async {
    forgetCalls++;
    if (removeFailed) {
      return {'ok': false, 'message': 'Rimozione non completata.'};
    }
    records.remove(card);
    return {'ok': true};
  }

  void insert([String id = 'TEST']) {
    presence = {
      'ok': true,
      'readers': [
        {
          'name': 'Reader',
          'cardId': id,
          'isCie': true,
          'present': true,
          'occupied': false,
        },
      ],
    };
  }
}

class PublicSystem {
  bool available = true, failPublish = false, failForget = false;
  int publications = 0, removals = 0;
  final cards = <String>{};
  final observed = <String>{};
  Future<void> publish(String card, String? hex) async {
    if (hex == null) {
      removals++;
      if (failForget) throw PlatformException(code: 'failed');
      cards.remove(card);
    } else {
      publications++;
      if (failPublish) throw PlatformException(code: 'failed');
      cards.add(card);
    }
  }

  Future<JsonResult> status() async => {
    'available': available,
    'configuredCards': cards.toList(),
    'publishedCards': cards.toList(),
    'observedCards': observed.toList(),
  };
}

void main() {
  test('PIN invalidation removes pairing and prevents stale system certificates resurrecting it', () async {
    final service = UnifiedFake();
    final system = PublicSystem();
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.enroll('Reader', 'TEST', '12345678');
    expect(controller.records['TEST']!.readyForSigning, isTrue);
    expect(system.cards, contains('TEST'));
    service.invalidated.add('TEST');
    await controller.refresh();
    expect(controller.records, isEmpty);
    // An inaccessible Keychain still provides independent invalidation metadata.
    service.locked = true;
    await controller.refresh();
    expect(controller.records, isEmpty);
    service.locked = false;
    service.invalidated.clear();
    await controller.refresh();
    expect(controller.records['TEST']!.readyForSigning, isTrue);
  });

  testWidgets(
    'monitor drains a single scan, drops a paused response and resumes without overlap',
    (t) async {
      final service = UnifiedFake()..pending = Completer<JsonResult>();
      final monitor = CardMonitor(service);
      var changes = 0;
      monitor.addListener(() => changes++);
      await monitor.setPaused(false);
      expect(service.observations, 1);
      final pausing = monitor.setPaused(true);
      service.pending!.complete({
        'ok': true,
        'readers': [
          {'name': 'stale'},
        ],
      });
      await t.pump();
      await pausing;
      expect(changes, 0);
      expect(monitor.readers, isEmpty);
      service.pending = null;
      service.insert();
      await monitor.setPaused(false);
      await t.pump();
      expect(changes, 1);
      await t.pump(const Duration(seconds: 1));
      expect(service.observations, 3);
      expect(changes, 1);
      await monitor.setPaused(true);
      await t.pump(const Duration(seconds: 5));
      expect(service.observations, 3);
      monitor.dispose();
      await t.pump(const Duration(seconds: 5));
      expect(service.observations, 3);
    },
  );
  testWidgets(
    'late system publication is observed at a low rate without authentication',
    (t) async {
      final service = UnifiedFake()..insert();
      var statusReads = 0;
      final monitor = CardMonitor(
        service,
        afterChange: () async {
          statusReads++;
        },
      );
      await monitor.setPaused(false);
      await t.pump();
      expect(statusReads, 1);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(statusReads, 2);
      expect(service.enrollCalls, 0);
      expect(service.detectCalls, 0);
      monitor.dispose();
    },
  );
  test('public publication failure survives restart and recovers without another authentication', () async {
    final service = UnifiedFake(), system = PublicSystem()..failPublish = true;
    final first = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await first.enroll('Reader', 'TEST', '12345678');
    expect(service.enrollCalls, 1);
    expect(first.records['TEST']!.readyForSigning, isTrue);
    expect(first.records['TEST']!.webProvisioned, isFalse);
    expect(first.message, contains('non occorre ripetere il PIN'));
    system.failPublish = false;
    final restarted = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await restarted.refresh();
    await restarted.complete('TEST');
    expect(service.enrollCalls, 1);
    expect(service.completeCalls, 1);
    expect(restarted.records['TEST']!.webProvisioned, isTrue);
    expect(restarted.records['TEST']!.identityObserved, isFalse);
    expect(
      restarted.records['TEST']!.webStatus,
      'Accesso ai siti configurato: apri il sito nel browser.',
    );
  });
  test('missing component and old pairings are distinct from a complete configuration', () async {
    final service = UnifiedFake(), system = PublicSystem()..available = false;
    service.records['OLD'] = {
      'card': 'OLD',
      'version': 1,
      'readyForSigning': true,
      'publicDataSaved': false,
    };
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.refresh();
    expect(controller.records['OLD']!.readyForSigning, isTrue);
    expect(controller.records['OLD']!.hasPublicData, isFalse);
    expect(service.enrollCalls, 0);
    await controller.enroll('Reader', 'TEST', '12345678');
    expect(
      controller.records['TEST']!.webStatus,
      contains('Accesso ai siti da attivare'),
    );
  });
  test('coordinated removal preserves native records when OS removal fails, then retries without PIN', () async {
    final service = UnifiedFake(), system = PublicSystem();
    final controller = EnrollmentController(
      service,
      publisher: system.publish,
      systemStatus: system.status,
    );
    await controller.enroll('Reader', 'TEST', '12345678');
    system.failForget = true;
    expect((await controller.remove('TEST'))['ok'], isFalse);
    expect(service.forgetCalls, 0);
    expect(service.records.containsKey('TEST'), isTrue);
    system.failForget = false;
    service.removeFailed = true;
    expect((await controller.remove('TEST'))['ok'], isFalse);
    expect(controller.records.containsKey('TEST'), isTrue);
    service.removeFailed = false;
    expect((await controller.remove('TEST'))['ok'], isTrue);
    expect(controller.records, isEmpty);
    expect(service.enrollCalls, 1);
  });
  test(
    'failed PIN has no publication, silent fallback, or automatic retry',
    () async {
      final service = UnifiedFake()..rejectPin = true;
      final system = PublicSystem();
      final controller = EnrollmentController(
        service,
        publisher: system.publish,
        systemStatus: system.status,
      );
      expect(
        (await controller.enroll('Reader', 'TEST', '00000000'))['code'],
        'pin_incorrect',
      );
      expect(service.enrollCalls, 1);
      expect(system.publications, 0);
      expect(service.completeCalls, 0);
      expect(service.records, isEmpty);
    },
  );
  test('a published certificate for another saved revision never makes the new record ready', () {
    final record = EnrollmentRecord(
      {
        'card': 'TEST',
        'readyForSigning': true,
        'publicDataSaved': true,
        'certificateHex': '300100',
      },
      {
        'available': true,
        'publishedCards': ['TEST'],
        'observedCards': ['TEST'],
        'certificateHexByCard': {'TEST': '300200'},
      },
    );
    expect(record.webProvisioned, isFalse);
    expect(record.identityObserved, isFalse);
    expect(record.webStatus, contains('Completa la configurazione'));
  });
  test('new enrollment diagnostics omit identities, public certificate, and secrets', () {
    final diagnostic = DiagnosticRecorder()
      ..level = AppDiagnosticLevel.operations;
    diagnostic.record('enroll', {
      'ok': true,
      'card': 'TEST',
      'fullName': 'PRIVATE NAME',
      'certificateHex': '300100',
      'pin': '12345678',
    }, 5);
    final event = diagnostic.events.single.toString();
    for (final value in ['PRIVATE NAME', 'TEST', '300100', '12345678']) {
      expect(event, isNot(contains(value)));
    }
  });
  Future<void> start(
    WidgetTester t,
    UnifiedFake service,
    PublicSystem system,
  ) async {
    t.view.physicalSize = const Size(1400, 1300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      CiePrototype(
        service: service,
        webPublisher: system.publish,
        webStatusReader: system.status,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'automatic Home pairs once and preserves the chosen page through insertion/removal',
    (t) async {
      final service = UnifiedFake(), system = PublicSystem();
      await start(t, service, system);
      expect(find.text('Rileva carta'), findsNothing);
      expect(find.text('Collega il lettore.'), findsOneWidget);
      await t.tap(find.text('Verifica Firma').first);
      await t.pumpAndSettle();
      service.insert();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        find.text(
          'La verifica dei documenti non richiede lettore, carta o PIN.',
        ),
        findsOneWidget,
      );
      expect(service.enrollCalls, 0);
      await t.tap(find.text('Home').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Abbina CIE'));
      await t.pumpAndSettle();
      final scans = service.observations;
      await t.pump(const Duration(seconds: 3));
      expect(service.observations, scans);
      await t.enterText(find.byType(TextField), '12345678');
      await t.tap(find.text('Abbina'));
      await t.pumpAndSettle();
      expect(service.enrollCalls, 1);
      expect(system.publications, 1);
      expect(find.text('Nome Cognome'), findsOneWidget);
      expect(find.text('Configura accesso ai siti'), findsNothing);
      await t.tap(find.text('Concludi'));
      await t.pumpAndSettle();
      service.presence = {'ok': true, 'readers': []};
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('Nome Cognome'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
  testWidgets(
    'card occupancy clears a typed PIN and disables signing without private calls',
    (t) async {
      final service = UnifiedFake()..insert();
      final system = PublicSystem();
      await start(t, service, system);
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      await signingDocument(t);
      await t.enterText(find.byType(TextField), '12345678');
      (service.presence['readers'] as List).first['occupied'] = true;
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Firma'),
      );
      expect(button.onPressed, isNull);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  testWidgets(
    'ambiguous readers do not choose a signing card and canceling pairing sends no PIN',
    (t) async {
      final service = UnifiedFake(), system = PublicSystem();
      service.presence = {
        'ok': true,
        'readers': [
          for (final id in ['ONE', 'TWO'])
            {'name': id, 'cardId': id, 'isCie': true, 'present': true},
        ],
      };
      await start(t, service, system);
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      expect(find.text('Seleziona un documento'), findsOneWidget);
      expect(service.signCalls, 0);
      await t.tap(find.text('Home').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Abbina CIE · ONE'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annulla'));
      await t.pumpAndSettle();
      expect(service.enrollCalls, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
