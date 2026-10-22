// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Windows path_provider derives its final directory from the public ProductName
// in the EXE. Keep the original private directory across a display-name change.
// macOS and Linux use the unchanged bundle/application ID.
Directory persistentSupportRoot(
  Directory discovered, {
  required bool windows,
}) => windows
    ? Directory.fromUri(discovered.parent.uri.resolve('CIE%20ID/'))
    : discovered;

Future<Directory> getPersistentApplicationSupportDirectory() async =>
    persistentSupportRoot(
      await getApplicationSupportDirectory(),
      windows: Platform.isWindows,
    );
