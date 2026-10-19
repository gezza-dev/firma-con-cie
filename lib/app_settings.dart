// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'network_settings.dart';
export 'network_settings.dart';

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings value);
}

class MemorySettingsStore implements SettingsStore {
  AppSettings value = const AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings value) async {
    value.proxy.validate();
    this.value = value;
  }
}

class FileSettingsStore implements SettingsStore {
  FileSettingsStore({Directory? directory}) : _provided = directory;
  final Directory? _provided;
  Future<Directory> _directory() async {
    final root = Directory.fromUri(
      (_provided ??
              Directory(
                '${(await getApplicationSupportDirectory()).path}/settings',
              ))
          .absolute
          .uri,
    );
    final entryPath = root.path.replaceFirst(RegExp(r'[/\\]+$'), '');
    if (entryPath.isEmpty || RegExp(r'^[a-zA-Z]:$').hasMatch(entryPath)) {
      throw const FileSystemException('Cartella impostazioni non valida');
    }
    if (await FileSystemEntity.type(entryPath, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Cartella impostazioni non valida');
    }
    await root.create(recursive: true);
    if (!Platform.isWindows &&
        (await Process.run('/bin/chmod', ['700', root.path])).exitCode != 0) {
      throw const FileSystemException('Impossibile proteggere le impostazioni');
    }
    return root;
  }

  @override
  Future<AppSettings> load() async {
    final file = File.fromUri(
      (await _directory()).uri.resolve('settings.json'),
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const AppSettings();
    if (type != FileSystemEntityType.file || await file.length() > 65536) {
      throw const FormatException('Impostazioni non valide');
    }
    return AppSettings.fromJson(jsonDecode(await file.readAsString()));
  }

  @override
  Future<void> save(AppSettings value) async {
    value.proxy.validate();
    final root = await _directory();
    final file = File.fromUri(root.uri.resolve('settings.json'));
    final temporary = File(
      '${file.path}.tmp-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
