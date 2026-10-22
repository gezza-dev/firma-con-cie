// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/application_storage.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/preferences.dart';

void main() {
  test('Windows rename retains existing settings and signing preferences without copying data', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cie-brand-storage-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final oldRoot = Directory.fromUri(
      temporary.uri.resolve('gezza-dev/CIE%20ID/'),
    );
    final settings = Directory.fromUri(oldRoot.uri.resolve('settings/'));
    final preferences = Directory.fromUri(
      oldRoot.uri.resolve('signature-preferences/'),
    );
    await FileSettingsStore(directory: settings)
        .save(const AppSettings(languageCode: 'en', themeCode: 'dark'));
    await FilePreferencesStore(directory: preferences).saveFormat('p7m');
    final settingsFile = File.fromUri(settings.uri.resolve('settings.json'));
    final original = await settingsFile.readAsBytes();
    final imageName = 'image-${'a'.padLeft(32, 'a')}.png';
    final image = File.fromUri(preferences.uri.resolve(imageName));
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4uoAAAAASUVORK5CYII=',
    );
    await image.writeAsBytes(imageBytes);
    final preferencesFile = File.fromUri(
      preferences.uri.resolve('preferences.json'),
    );
    final savedPreferences = jsonDecode(
      await preferencesFile.readAsString(),
    ) as Map<String, dynamic>;
    savedPreferences['image'] = imageName;
    await preferencesFile.writeAsString(jsonEncode(savedPreferences));
    final originalPreferences = await preferencesFile.readAsBytes();
    final discovered = Directory.fromUri(
      temporary.uri.resolve('gezza-dev/Firma%20con%20CIE/'),
    );
    final resolved = await resolvePersistentSupportDirectory(
      windows: true,
      roamingAppData: temporary.path,
      discover: () async {
        await discovered.create(recursive: true);
        fail('Windows must not discover/create the public-name directory');
      },
    );
    final loaded = await FileSettingsStore(
      directory: Directory.fromUri(resolved.uri.resolve('settings/')),
    ).load();
    expect(loaded.languageCode, 'en');
    expect(loaded.themeCode, 'dark');
    final reloadedPreferences = await FilePreferencesStore(
      directory: Directory.fromUri(
        resolved.uri.resolve('signature-preferences/'),
      ),
    ).load();
    expect(reloadedPreferences.format, 'p7m');
    expect(reloadedPreferences.imagePath, image.path);
    expect(await image.readAsBytes(), imageBytes);
    expect(await preferencesFile.readAsBytes(), originalPreferences);
    expect(await settingsFile.readAsBytes(), original);
    expect(await discovered.exists(), isFalse);
    expect(
      await resolvePersistentSupportDirectory(
        windows: false,
        roamingAppData: null,
        discover: () async => discovered,
      ),
      same(discovered),
    );
  });
  test(
    'Windows rejects unavailable support paths without creating a new archive',
    () async {
      for (final path in <String?>[null, '', 'relative-appdata']) {
        await expectLater(
          resolvePersistentSupportDirectory(
            windows: true,
            roamingAppData: path,
            discover: () async => throw StateError('unexpected discovery'),
          ),
          throwsA(isA<FileSystemException>()),
        );
      }
    },
  );
}
