// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

/// Local discovery only: never starts a browser or changes a profile.
List<String> installedLinuxBrowsers({
  Map<String, String>? environment,
  bool Function(String)? fileExists,
}) {
  final env = environment ?? Platform.environment;
  final exists = fileExists ?? (String path) => File(path).existsSync();
  final snap = exists('/snap/bin/firefox');
  return [
    if (exists('/usr/bin/google-chrome') ||
        exists('/usr/bin/google-chrome-stable') ||
        exists('/opt/google/chrome/chrome'))
      'chrome',
    if (exists('/usr/lib/firefox/firefox') ||
        exists('/opt/firefox/firefox') ||
        (!snap && exists('/usr/bin/firefox')) ||
        _profileFirefoxExists(env))
      'firefox',
    if (snap) 'firefox-snap',
    if (exists('/usr/bin/microsoft-edge') ||
        exists('/usr/bin/microsoft-edge-stable'))
      'edge',
  ];
}

Map<String, Map<String, String>> _readIni(File file, int maximum) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      file.lengthSync() > maximum) {
    return {};
  }
  final result = <String, Map<String, String>>{};
  Map<String, String>? section;
  for (final line in file.readAsLinesSync()) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith(';') || text.startsWith('#')) continue;
    if (text.startsWith('[') && text.endsWith(']')) {
      section = result.putIfAbsent(
        text.substring(1, text.length - 1),
        () => {},
      );
    } else if (section != null && text.contains('=')) {
      final equal = text.indexOf('=');
      section[text.substring(0, equal).trim()] = text
          .substring(equal + 1)
          .trim();
    }
  }
  return result;
}

bool _inside(Directory directory, Directory home) => directory.absolute.uri
    .normalizePath()
    .toString()
    .startsWith(home.absolute.uri.normalizePath().toString());

bool _profileFirefoxExists(Map<String, String> environment) {
  final homePath = environment['HOME'];
  if (homePath == null || !homePath.startsWith('/')) return false;
  final home = Directory(homePath);
  final customConfig = Directory(
    environment['XDG_CONFIG_HOME'] ?? '${home.path}/.config',
  );
  final roots = {
    '${home.path}/.mozilla/firefox',
    '${home.path}/.config/mozilla/firefox',
    if (customConfig.path.startsWith('/') && _inside(customConfig, home))
      '${customConfig.path}/mozilla/firefox',
  };
  for (final root in roots) {
    try {
      final profiles = _readIni(File('$root/profiles.ini'), 1024 * 1024);
      for (final entry
          in profiles.entries
              .where((entry) => RegExp(r'^Profile\d+$').hasMatch(entry.key))
              .take(256)) {
        try {
          final path = entry.value['Path'];
          if (path == null || path.isEmpty || path.split('/').contains('..')) {
            continue;
          }
          final profile = Directory(
            entry.value['IsRelative'] == '1' ? '$root/$path' : path,
          );
          if (!profile.path.startsWith('/') || !_inside(profile, home)) {
            continue;
          }
          // Match the setup helper's initialized, native profiles. Resolve the
          // directory to prevent a profile index escaping HOME through a link.
          final resolved = Directory(profile.resolveSymbolicLinksSync());
          if (!_inside(resolved, home) ||
              !File('${resolved.path}/cert9.db').existsSync() ||
              resolved.path.startsWith('${home.path}/snap/')) {
            continue;
          }
          final metadata = _readIni(
            File('${resolved.path}/compatibility.ini'),
            64 * 1024,
          );
          final platform = metadata['Compatibility']?['LastPlatformDir'];
          if (platform == null || !platform.startsWith('/')) continue;
          final installation = Directory(platform).resolveSymbolicLinksSync();
          if (installation.startsWith('/snap/') ||
              installation.startsWith('/var/lib/snapd/snap/') ||
              installation.startsWith('/app/') ||
              installation.contains('/flatpak/')) {
            continue;
          }
          final app = _readIni(
            File('$installation/application.ini'),
            64 * 1024,
          )['App'];
          if (app?['ID'] != '{ec8030f7-c20a-464f-9b0e-13a3a9e97384}' ||
              app?['Name'] != 'Firefox') {
            continue;
          }
          final executable = File('$installation/firefox');
          final info = executable.statSync();
          if (info.type != FileSystemEntityType.file || info.mode & 0x49 == 0) {
            continue;
          }
          // Inspect only the ELF header; never invoke the discovered executable.
          final handle = executable.openSync();
          try {
            final magic = handle.readSync(4);
            if (magic.length == 4 &&
                magic[0] == 0x7f &&
                magic[1] == 0x45 &&
                magic[2] == 0x4c &&
                magic[3] == 0x46) {
              return true;
            }
          } finally {
            handle.closeSync();
          }
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        }
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return false;
}
