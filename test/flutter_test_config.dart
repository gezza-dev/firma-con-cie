// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Existing UX expectations describe Italian. Set the simulated OS explicitly;
// locale resolution tests override it to exercise English/unsupported locales.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('it', 'IT');
  });
  await testMain();
}
