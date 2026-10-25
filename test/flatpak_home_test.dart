// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_settings.dart';
import 'package:cie_flutter_prototype/linux_browser_status.dart';
import 'package:cie_flutter_prototype/main.dart';
import 'package:cie_flutter_prototype/web_access.dart';

import 'chrome_setup_test.dart' show FakeChromeSetup;
import 'firefox_setup_test.dart' show FakeFirefoxSetup;
import 'linux_browser_status_test.dart' show LinuxPairedService, pairedStatus;
import 'web_completion_feedback_test.dart' show size;

void main() {
  for (final language in ['it', 'en']) {
    testWidgets(
      'Flatpak Home in $language never inspects or configures browsers',
      (t) async {
        size(t);
        final service = LinuxPairedService();
        final firefox = FakeFirefoxSetup();
        final chrome = FakeChromeSetup();
        await t.pumpWidget(
          CiePrototype(
            flatpak: true,
            service: service,
            settings: MemorySettingsStore()
              ..value = AppSettings(languageCode: language),
            firefoxSetupService: firefox,
            chromeSetupService: chrome,
            webStatusReader: () async => {},
            webPublisher: (_, _) async => fail('No host publication'),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('flatpak-web-notice')),
          findsOneWidget,
        );
        expect(
          t.widget<Text>(find.byKey(pairedStatus)).data,
          language == 'it' ? flatpakWebMessage : 'To configure website access, install the “Website access for Firma con CIE Flatpak” component, then press “Refresh”.',
        );
        expect(find.byType(WebAccessCard), findsNothing);
        expect(firefox.reads, 0);
        expect(chrome.reads, 0);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(firefox.reads, 0);
        expect(chrome.reads, 0);
        expect(firefox.writes + chrome.writes + firefox.permissions, 0);
        expect(
          service.enrollCalls + service.completeCalls + service.signCalls,
          0,
        );
        expect(find.byType(TextField), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
