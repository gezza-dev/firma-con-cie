// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/browser_setup.dart';
import 'package:cie_flutter_prototype/card_monitor.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/home_card_status.dart';
import 'package:cie_flutter_prototype/web_component_setup.dart';

import 'home_enrollment_test.dart' show UnifiedFake;

class ObservationService
    implements CardObservationService, CancellableCardObservation {
  int cancellations = 0, reads = 0;
  Completer<JsonResult>? pending;
  @override
  Future<JsonResult> observeCards() {
    reads++;
    return pending?.future ??
        Future.value({'ok': true, 'readers': <JsonResult>[]});
  }

  @override
  Future<void> cancelCardObservation() async {
    cancellations++;
    if (pending != null && !pending!.isCompleted) {
      pending!.complete({'ok': false, 'code': 'observation_cancelled'});
    }
  }
}

void main() {
  testWidgets(
    'editing pauses preserve the cache and drain probes; disposal still cancels',
    (t) async {
      final service = ObservationService();
      final monitor = CardMonitor(service);
      await monitor.setPaused(false);
      await t.pump();
      expect(monitor.checked, isTrue);
      await monitor.setPaused(true);
      expect(service.cancellations, 0);
      await monitor.setPaused(false);
      await t.pump();
      expect(service.reads, 2);
      service.pending = Completer<JsonResult>();
      await t.pump(const Duration(seconds: 1));
      final pause = monitor.setPaused(true);
      expect(service.cancellations, 0);
      service.pending!.complete({'ok': true, 'readers': <JsonResult>[]});
      await pause;
      expect(monitor.checked, isTrue);
      monitor.dispose();
      expect(service.cancellations, 1);
    },
  );
  test(
    'uncertain inspection does not replace confirmed component state',
    () async {
      var platform = <String, dynamic>{
        'available': true,
        'activationState': 'enabled',
      };
      final controller = EnrollmentController(
        UnifiedFake(),
        publisher: (_, _) async {},
        systemStatus: () async => platform,
      );
      await controller.refreshSystem();
      expect(controller.system['available'], true);
      platform = {'ok': false, 'code': 'busy'};
      await controller.refreshSystem();
      expect(controller.system['available'], true);
      expect(controller.system['systemInspectionPending'], true);
      platform = {
        'available': false,
        'activationState': 'unknown',
        'canActivateComponent': true,
      };
      await controller.refreshSystem();
      expect(controller.system['available'], true);
      platform = {
        'available': false,
        'activationState': 'disabled',
        'canActivateComponent': true,
      };
      await controller.refreshSystem();
      expect(controller.system['available'], false);
      expect(
        WebComponentSetupNotice.fromStatus(controller.system)!.action,
        WebComponentAction.activate,
      );
    },
  );
  test('unknown metadata cannot propose activation and identification failure is not evidence of another app', () {
    expect(
      WebComponentSetupNotice.fromStatus({
        'available': false,
        'activationState': 'unknown',
        'canActivateComponent': true,
      }),
      isNull,
    );
    expect(
      homeCardStatus(
        readers: [
          {'present': true, 'occupied': false, 'identificationCode': -3},
        ],
        checked: true,
      ),
      'Riconoscimento della CIE in corso…',
    );
  });
  test('pause discards a late unavailable result and cannot activate the component', () async {
    Completer<JsonResult>? pending;
    var activations = 0;
    final coordinator = BrowserSetupCoordinator(
      platform: 'macos',
      inventory: () async => {
        'ok': true,
        'installed': ['safari'],
      },
      systemReader: () async => pending?.future ?? {'available': true},
      activate: () async {
        activations++;
        return {'ok': true};
      },
      log: (_, _, _) async {},
    );
    await coordinator.refresh(forceSystem: true);
    expect(coordinator.configured, ['safari']);
    pending = Completer<JsonResult>();
    final refresh = coordinator.refresh(forceSystem: true);
    await Future<void>.delayed(Duration.zero);
    coordinator.setPaused(true);
    pending.complete({'available': false, 'canActivateComponent': true});
    await coordinator.whenIdle;
    await refresh;
    expect(activations, 0);
    expect(coordinator.system['available'], true);
    expect(coordinator.configured, ['safari']);
    coordinator.dispose();
  });
  test(
    'busy metadata cannot erase ready browsers or cause activation',
    () async {
      var busy = false;
      var activations = 0;
      final coordinator = BrowserSetupCoordinator(
        platform: 'macos',
        inventory: () async => {
          'ok': true,
          'installed': ['safari'],
        },
        systemReader: () async =>
            busy ? {'ok': false, 'code': 'busy'} : {'available': true},
        statusRetryDelay: Duration.zero,
        activate: () async {
          activations++;
          return {'ok': true};
        },
        log: (_, _, _) async {},
      );
      await coordinator.refresh(forceSystem: true);
      busy = true;
      await coordinator.refresh(forceSystem: true);
      expect(coordinator.system['available'], true);
      expect(coordinator.configured, ['safari']);
      expect(activations, 0);
      coordinator.dispose();
    },
  );
}
