// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:cie_flutter_prototype/linux_text_scaling.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeService;

const channel = MethodChannel('cie.id/linux_text_scaling');

void main() {
  void scalingTest(
    String name,
    WidgetTesterCallback callback, {
    TargetPlatform platform = TargetPlatform.linux,
  }) => testWidgets(
    name,
    callback,
    variant: TargetPlatformVariant.only(platform),
  );

  Future<void> notify(WidgetTester t, Object? scale) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('textScaleChanged', scale)),
      (_) {},
    );
    await t.pump();
  }

  void mock(WidgetTester t, Future<Object?> Function(MethodCall) handler) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
  }

  Future<void> mount(
    WidgetTester t, {
    double platformScale = 1,
    double dpr = 1,
  }) async {
    t.platformDispatcher.textScaleFactorTestValue = platformScale;
    t.view.devicePixelRatio = dpr;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (_, child) => LinuxTextScaling(child: child!),
        home: const Scaffold(body: Text('Scale probe')),
      ),
    );
    await t.pumpAndSettle();
  }

  double scale(WidgetTester t) =>
      MediaQuery.textScalerOf(t.element(find.text('Scale probe'))).scale(16) /
      16;

  for (final value in [0.8, 1.0, 1.25, 1.5, 2.0]) {
    scalingTest('uses GTK logical font scale $value once', (t) async {
      mock(t, (_) async => value);
      await mount(t);
      expect(scale(t), value);
    });
  }

  for (final platform in [0.8, 1.25, 1.5, 2.0]) {
    scalingTest('preserves engine scale $platform without multiplying GTK', (
      t,
    ) async {
      mock(t, (_) async => 1.25);
      await mount(t, platformScale: platform);
      expect(scale(t), platform);
      await notify(t, 1.5);
      expect(scale(t), platform);
    });
  }

  scalingTest('display scaling is independent of logical font scaling', (
    t,
  ) async {
    mock(t, (_) async => 1.25);
    await mount(t, dpr: 2);
    final context = t.element(find.text('Scale probe'));
    expect(MediaQuery.devicePixelRatioOf(context), 2);
    expect(scale(t), 1.25);
  });

  scalingTest('updates at runtime and returns to 100%', (t) async {
    mock(t, (_) async => 1.25);
    await mount(t);
    await notify(t, 1.5);
    expect(scale(t), 1.5);
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    await t.pumpAndSettle();
    expect(scale(t), 1.5);
    t.platformDispatcher.textScaleFactorTestValue = 1;
    await t.pumpAndSettle();
    expect(scale(t), 1.5);
    await notify(t, 1.0);
    expect(scale(t), 1);
  });

  scalingTest('ignores invalid settings and late startup replies', (t) async {
    final initial = Completer<Object?>();
    mock(t, (_) => initial.future);
    await mount(t);
    await notify(t, 1.5);
    initial.complete(1.25);
    await t.pumpAndSettle();
    expect(scale(t), 1.5);
    for (final bad in [null, 'large', -1, 0, double.nan, double.infinity]) {
      await notify(t, bad);
      expect(scale(t), 1.5);
    }
    await t.pumpWidget(const SizedBox());
    await notify(t, 2.0);
    expect(t.takeException(), isNull);
  });

  scalingTest('missing or failed channel keeps engine behaviour', (t) async {
    await mount(t);
    expect(scale(t), 1);
    await t.pumpWidget(const SizedBox());
    mock(t, (_) async => throw PlatformException(code: 'unavailable'));
    await mount(t, platformScale: 1.25);
    expect(scale(t), 1.25);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    scalingTest('$platform does not request or override Linux scaling', (
      t,
    ) async {
      var calls = 0;
      mock(t, (_) async {
        calls++;
        return 1.5;
      });
      await mount(t, platformScale: 1.25);
      expect(calls, 0);
      expect(scale(t), 1.25);
    }, platform: platform);
  }

  for (final gtkScale in [1.25, 1.5]) {
    scalingTest('Home and dialogs fit at GTK scale $gtkScale', (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      mock(t, (_) async => gtkScale);
      final service = FakeService();
      await t.pumpWidget(CiePrototype(service: service));
      await t.pumpAndSettle();
      final context = t.element(find.byKey(const ValueKey('page-title')));
      expect(MediaQuery.textScalerOf(context).scale(16), 16 * gtkScale);
      expect(t.takeException(), isNull);
      // Dialogs are inserted into the Navigator; they need the same scaler.
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Dialog scale probe'),
            content: Text('Software only'),
          ),
        ),
      );
      await t.pumpAndSettle();
      final dialogContext = t.element(find.text('Dialog scale probe'));
      expect(MediaQuery.textScalerOf(dialogContext).scale(16), 16 * gtkScale);
      expect(t.takeException(), isNull);
      expect(service.signCalls, 0);
      await t.pumpWidget(const SizedBox());
    });
  }
}
