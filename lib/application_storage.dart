// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Windows path_provider derives its final directory from the public ProductName
// in the EXE. Keep the original private directory across a display-name change.
// macOS and Linux use the unchanged bundle/application ID.
Future<Directory> resolvePersistentSupportDirectory({
  required bool windows,
  required String? roamingAppData,
  required Future<Directory> Function() discover,
}) async {
  if (!windows) return discover();
  // The Windows plugin creates its ProductName directory while discovering
  // it. Resolve the stable private path directly to avoid creating a second
  // archive (even an empty one) after a public-name change.
  if (roamingAppData == null ||
      roamingAppData.isEmpty ||
      !Directory(roamingAppData).isAbsolute) {
    throw const FileSystemException(
      'Application support directory unavailable',
    );
  }
  return Directory.fromUri(
    Directory(roamingAppData).uri.resolve('gezza-dev/CIE%20ID/'),
  );
}

Future<Directory> getPersistentApplicationSupportDirectory() async =>
    resolvePersistentSupportDirectory(
      windows: Platform.isWindows,
      roamingAppData: Platform.environment['APPDATA'],
      discover: getApplicationSupportDirectory,
    );
