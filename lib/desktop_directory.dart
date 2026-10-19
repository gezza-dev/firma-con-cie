// SPDX-License-Identifier: BSD-3-Clause
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

final class _Guid extends Struct {
  @Uint32()
  external int a;
  @Uint16()
  external int b;
  @Uint16()
  external int c;
  @Array(8)
  external Array<Uint8> d;
}

// Ask the OS for Desktop, including a redirected/OneDrive Desktop on Windows.
// This is a dialog preference; no card or certificate operation is involved.
Future<String?> desktopDirectory() async {
  if (Platform.isMacOS) {
    try {
      return await const MethodChannel('cie.id/file-dialogs')
          .invokeMethod<String>('desktopDirectory');
    } on MissingPluginException {
      return _homeDesktop();
    }
  }
  if (Platform.isWindows) {
    final id = calloc<_Guid>(), output = calloc<Pointer<Utf16>>();
    final free = DynamicLibrary.open('ole32.dll')
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CoTaskMemFree');
    try {
      // FOLDERID_Desktop {B4BFCC3A-DB2C-424C-B029-7FE99A87C641}
      id.ref
        ..a = 0xb4bfcc3a
        ..b = 0xdb2c
        ..c = 0x424c;
      const tail = [0xb0, 0x29, 0x7f, 0xe9, 0x9a, 0x87, 0xc6, 0x41];
      for (var i = 0; i < tail.length; i++) {
        id.ref.d[i] = tail[i];
      }
      final get = DynamicLibrary.open('shell32.dll')
          .lookupFunction<
            Int32 Function(
              Pointer<_Guid>,
              Uint32,
              Pointer<Void>,
              Pointer<Pointer<Utf16>>,
            ),
            int Function(
              Pointer<_Guid>,
              int,
              Pointer<Void>,
              Pointer<Pointer<Utf16>>,
            )
          >('SHGetKnownFolderPath');
      if (get(id, 0, nullptr, output) >= 0 && output.value != nullptr) {
        return output.value.toDartString();
      }
      return _homeDesktop();
    } finally {
      if (output.value != nullptr) free(output.value.cast());
      calloc.free(output);
      calloc.free(id);
    }
  }
  if (Platform.isLinux) {
    try {
      final result = await Process.run('xdg-user-dir', ['DESKTOP']);
      final path = result.stdout.toString().trim();
      if (result.exitCode == 0 && path.startsWith('/')) return path;
    } on ProcessException {
      /* Use the conventional location if unavailable. */
    }
  }
  return _homeDesktop();
}

String? _homeDesktop() {
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  return home == null ? null : '$home${Platform.pathSeparator}Desktop';
}
