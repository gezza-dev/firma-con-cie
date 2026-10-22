// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/paired_card_identity.dart';

import 'home_enrollment_test.dart' show UnifiedFake, PublicSystem;

void main() {
  void save(UnifiedFake service, String id, String number) {
    service.records[id] = {
      'card': id,
      'fullName': 'Titolare $id',
      'cardNumber': number,
      'readyForSigning': true,
      'publicDataSaved': true,
      'certificateHex': '300100',
    };
  }

  Future<void> start(WidgetTester t, UnifiedFake service) async {
    t.view.physicalSize = const Size(1400, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final system = PublicSystem();
    await t.pumpWidget(
      CiePrototype(
        service: service,
        webPublisher: system.publish,
        webStatusReader: system.status,
      ),
    );
    await t.pumpAndSettle();
  }

  Finder pairButton(bool another) =>
      find.byKey(ValueKey(another ? 'add-another-card' : 'pair-card'));
  PairedCardIdentity identity(WidgetTester t, String id) =>
      t.widget<PairedCardIdentity>(
        find.byKey(ValueKey('paired-card-identity-$id')),
      );
  Future<void> update(
    WidgetTester t,
    UnifiedFake service,
    JsonResult presence,
  ) async {
    service.presence = presence;
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  }

  JsonResult reader(String id, {String? number, bool occupied = false}) => {
    'name': 'Reader $id',
    'present': true,
    'isCie': true,
    'cardId': id,
    'occupied': occupied,
    'cardNumber': ?number,
  };
  JsonResult presence(List<JsonResult> readers) => {
    'ok': true,
    'readers': readers,
  };

  testWidgets(
    'first and subsequent pairing buttons share location and filled style, including absent cards',
    (t) async {
      final first = UnifiedFake();
      await start(t, first);
      final initial = pairButton(false);
      expect(t.widget<FilledButton>(initial).onPressed, isNull);
      final position = t.getTopLeft(initial),
          height = t.getSize(initial).height;
      await t.pumpWidget(const SizedBox.shrink());
      final paired = UnifiedFake();
      save(paired, 'A', 'CA00001AA');
      // Reuse the same viewport setup, with a new service and widget tree.
      final system = PublicSystem();
      await t.pumpWidget(
        CiePrototype(
          service: paired,
          webPublisher: system.publish,
          webStatusReader: system.status,
        ),
      );
      await t.pumpAndSettle();
      final another = pairButton(true);
      expect(t.widget<FilledButton>(another).onPressed, isNull);
      expect(t.getTopLeft(another), position);
      expect(t.getSize(another).height, height);
      expect(
        find.widgetWithText(OutlinedButton, 'Abbina un’altra CIE'),
        findsNothing,
      );
      expect(identity(t, 'A').present, false);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'button and each thumbnail track the exact CIE across insertion, replacement, removal and errors',
    (t) async {
      final service = UnifiedFake();
      save(service, 'A', 'CA00001AA');
      save(service, 'B', 'CA00002BB');
      await start(t, service);
      bool enabled() =>
          t.widget<FilledButton>(pairButton(true)).onPressed != null;
      expect(enabled(), false);
      expect(identity(t, 'A').present, false);
      expect(identity(t, 'B').present, false);
      await update(t, service, presence([reader('A')]));
      expect(enabled(), false);
      expect(identity(t, 'A').present, true);
      expect(identity(t, 'B').present, false);
      await update(t, service, presence([reader('B')]));
      expect(enabled(), false);
      expect(identity(t, 'A').present, false);
      expect(identity(t, 'B').present, true);
      await update(t, service, presence([reader('NEW')]));
      expect(enabled(), true);
      expect(identity(t, 'A').present, false);
      expect(identity(t, 'B').present, false);
      await update(
        t,
        service,
        presence([
          {'name': 'Reader', 'present': false, 'isCie': false},
        ]),
      );
      expect(enabled(), false);
      await update(t, service, presence([]));
      expect(enabled(), false);
      await update(t, service, {'ok': false, 'code': 'pcsc_timeout'});
      expect(enabled(), false);
      expect(identity(t, 'A').present, false);
      expect(identity(t, 'B').present, false);
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'signing thumbnails follow the exact detected CIE while absent cards remain selectable',
    (t) async {
      final service = UnifiedFake();
      save(service, 'A', 'CA00001AA');
      save(service, 'B', 'CA00002BB');
      await start(t, service);
      await t.tap(find.text('Firma Elettronica').first);
      await t.pumpAndSettle();
      CieCardIllustration thumbnail(String id) => t.widget<CieCardIllustration>(
        find.descendant(
          of: find.byKey(ValueKey('signing-card-$id')),
          matching: find.byType(CieCardIllustration),
        ),
      );
      void check(bool a, bool b) {
        expect(thumbnail('A').inColor, a);
        expect(thumbnail('B').inColor, b);
        for (final id in ['A', 'B']) {
          expect(
            t.widget<ListTile>(find.byKey(ValueKey('signing-card-$id'))).onTap,
            isNotNull,
          );
        }
      }

      check(false, false);
      await update(t, service, presence([reader('A')]));
      check(true, false);
      await update(t, service, presence([reader('B')]));
      check(false, true);
      await update(
        t,
        service,
        presence([reader('ALIAS', number: 'ca00001aa')]),
      );
      check(true, false);
      await update(t, service, presence([reader('NEW')]));
      check(false, false);
      await update(t, service, presence([]));
      check(false, false);
      await update(t, service, {'ok': false, 'code': 'pcsc_timeout'});
      check(false, false);
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'Home status and pairing button align with the visible card artwork and details',
    (t) async {
      final service = UnifiedFake();
      save(service, 'A', 'CA00001AA');
      service.presence = presence([
        {'name': 'Reader', 'present': false, 'isCie': false},
      ]);
      await start(t, service);
      final card = find.byKey(const ValueKey('paired-card-identity-A'));
      final image = find.descendant(
        of: card,
        matching: find.byType(CieCardIllustration),
      );
      final illustration = t.widget<CieCardIllustration>(image);
      final artworkLeft =
          t.getTopLeft(image).dx +
          illustration.width * CieCardIllustration.artworkLeftFraction;
      final status = find.text('Appoggia la CIE al lettore.');
      expect(status, findsOneWidget);
      expect(t.getTopLeft(status).dx, closeTo(artworkLeft, 0.01));
      expect(t.getTopLeft(pairButton(true)).dx, closeTo(artworkLeft, 0.01));
      expect(
        t.getTopLeft(find.text('CIE abbinata. Puoi firmare documenti.')).dx,
        closeTo(artworkLeft, 0.01),
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background and minimized app continue public detection, OS suspension stops it',
    (t) async {
      final service = UnifiedFake();
      save(service, 'A', 'CA00001AA');
      await start(t, service);
      addTearDown(
        () =>
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final before = service.observations;
      await update(t, service, presence([reader('A')]));
      expect(service.observations, greaterThan(before));
      expect(identity(t, 'A').present, true);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final hidden = service.observations;
      service.presence = presence([]);
      await t.pump(const Duration(seconds: 1));
      expect(service.observations, greaterThan(hidden));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pumpAndSettle();
      expect(identity(t, 'A').present, false);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      final paused = service.observations;
      await t.pump(const Duration(seconds: 3));
      expect(service.observations, paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await update(t, service, presence([reader('A')]));
      expect(identity(t, 'A').present, true);
      expect(service.enrollCalls, 0);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'printed card number also matches a saved CIE, without comparing holder names',
    (t) async {
      final service = UnifiedFake();
      save(service, 'A', 'CA00001AA');
      service.presence = presence([reader('ALIAS', number: 'ca00001aa')]);
      await start(t, service);
      expect(t.widget<FilledButton>(pairButton(true)).onPressed, isNull);
      expect(identity(t, 'A').present, true);
      await update(t, service, presence([reader('NEW', occupied: true)]));
      expect(t.widget<FilledButton>(pairButton(true)).onPressed, isNull);
      expect(identity(t, 'A').present, false);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
