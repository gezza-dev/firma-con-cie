// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/app_updates.dart';
import 'package:cie_flutter_prototype/certificate_validity.dart';
import 'package:cie_flutter_prototype/enrollment.dart';
import 'package:cie_flutter_prototype/information_view.dart';

void main() {
  String release(
    String tag, {
    String? url,
    bool pre = false,
    bool draft = false,
  }) => jsonEncode({
    'tag_name': tag,
    'draft': draft,
    'prerelease': pre,
    'html_url':
        url ?? 'https://github.com/gezza-dev/firma-con-cie/releases/tag/$tag',
  });
  test('updates compare numeric versions and accept only this project release pages', () {
    expect(
      releaseEndpoint.toString(),
      'https://api.github.com/repos/gezza-dev/firma-con-cie/releases/latest',
    );
    final newer = parseRelease(200, release('v1.10.0'), current: '1.9.9');
    expect(newer.version, 'v1.10.0');
    expect(
      newer.page.toString(),
      'https://github.com/gezza-dev/firma-con-cie/releases/tag/v1.10.0',
    );
    expect(
      parseRelease(200, release('v1.10.0'), current: '1.9.9').state,
      UpdateState.available,
    );
    expect(parseRelease(200, release('v1.0.0')).state, UpdateState.current);
    expect(parseRelease(200, release('0.9.9')).state, UpdateState.current);
    for (final bad in [
      release('1.1.0', pre: true),
      release('1.1.0', draft: true),
      release('1.1.0-beta'),
      release('1.1.0', url: 'https://example.invalid/update.exe'),
      release(
        '1.1.0',
        url: 'https://github.com/other/project/releases/tag/1.1.0',
      ),
      // A different repository owned by the same account is still untrusted.
      release(
        '1.1.0',
        url: 'https://github.com/gezza-dev/another-project/releases/tag/1.1.0',
      ),
      release(
        '1.1.0',
        url: 'http://github.com/gezza-dev/firma-con-cie/releases/tag/1.1.0',
      ),
      release(
        '1.1.0',
        url: 'https://github.com/gezza-dev/firma-con-cie/releases/tag/1.1.0?redirect=bad',
      ),
      release(
        '1.1.0',
        url: 'https://github.com/gezza-dev/firma-con-cie/releases/tag/1.1.0#download',
      ),
      release(
        '1.1.0',
        url:
            'https://github.com:8443/gezza-dev/firma-con-cie/releases/tag/1.1.0',
      ),
      release(
        '1.1.0',
        url: 'https://user@github.com/gezza-dev/firma-con-cie/releases/tag/1.1.0',
      ),
      '{}',
      'not json',
      ' ' * 262145,
    ]) {
      expect(parseRelease(200, bad).state, UpdateState.unavailable);
    }
  });
  test('missing private release, rate limit and network errors never mean up to date', () {
    for (final status in [0, 301, 302, 401, 403, 404, 429, 500]) {
      expect(
        parseRelease(status, release('1.0.0')).state,
        UpdateState.unavailable,
      );
    }
  });
  test('certificate dates come from bounded public DER without changing enrollment flags', () {
    final source = File('native/tests/windows_public_certificate_fixture.h')
        .readAsStringSync();
    final hex = RegExp(r'0x([0-9a-fA-F]{2})')
        .allMatches(source)
        .map((m) => m[1])
        .join();
    final validity = CertificateValidity.fromHex(hex)!;
    expect(validity.notBefore.year, 2020);
    expect(validity.notAfter.year, 2100);
    final record = EnrollmentRecord(
      {
        'card': 'TEST',
        'certificateHex': hex,
        'readyForSigning': true,
        'publicDataSaved': true,
        'webProvisioned': true,
      },
      {'available': true},
    );
    expect(record.certificateWarning(DateTime.utc(2030)), isNull);
    expect(record.certificateWarning(DateTime.utc(2101)), contains('scaduto'));
    expect(
      record.certificateWarning(DateTime.utc(2019)),
      contains('non è ancora valido'),
    );
    expect(record.readyForSigning && record.webProvisioned, isTrue);
    for (final bad in [
      null,
      '',
      '300100',
      hex.substring(2),
      '${hex}00',
      '00' * 8193,
      'zz',
    ]) {
      expect(CertificateValidity.fromHex(bad), isNull);
    }
  });
  testWidgets(
    'an inaccessible release is explained without claiming the app is current',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdatesView(
              checker: () async {
                calls++;
                return const AppUpdate(UpdateState.unavailable);
              },
            ),
          ),
        ),
      );
      expect(calls, 0);
      await t.tap(find.text('Verifica aggiornamenti'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Impossibile verificare'), findsOneWidget);
      expect(find.text('La versione installata è aggiornata.'), findsNothing);
    },
  );
}
