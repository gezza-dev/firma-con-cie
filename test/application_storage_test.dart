// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

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
    final discovered = Directory.fromUri(
      temporary.uri.resolve('gezza-dev/Firma%20con%20CIE/'),
    );
    final resolved = persistentSupportRoot(discovered, windows: true);
    final loaded = await FileSettingsStore(
      directory: Directory.fromUri(resolved.uri.resolve('settings/')),
    ).load();
    expect(loaded.languageCode, 'en');
    expect(loaded.themeCode, 'dark');
    expect(
      (await FilePreferencesStore(
        directory: Directory.fromUri(
          resolved.uri.resolve('signature-preferences/'),
        ),
      ).load()).format,
      'p7m',
    );
    expect(await settingsFile.readAsBytes(), original);
    expect(await discovered.exists(), isFalse);
    expect(persistentSupportRoot(discovered, windows: false), same(discovered));
  });
}
