// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showCieLicenses(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _LicenseInformation(),
);

class _LicenseInformation extends StatefulWidget {
  const _LicenseInformation();
  @override
  State<_LicenseInformation> createState() => _LicenseInformationState();
}

class _LicenseInformationState extends State<_LicenseInformation> {
  String? error;
  Future<void> openLicenses() async {
    try {
      // Original license texts stay intact. Present complete readable copies in
      // the user's file viewer, rather than runtime names in the application UI.
      final directory = await Directory.systemTemp.createTemp(
        'cie-id-licenze-',
      );
      final notices = await rootBundle.load('NOTICES.Z');
      final text = utf8.decode(
        gzip.decode(
          notices.buffer.asUint8List(
            notices.offsetInBytes,
            notices.lengthInBytes,
          ),
        ),
      );
      await File('${directory.path}/Licenze-interfaccia.txt')
          .writeAsString(text);
      for (final entry in {
        'Licenza-CIE-ID.txt': 'assets/licenses/prototype-LICENSE.txt',
        'Licenza-middleware.txt': 'assets/licenses/native-LICENSE.txt',
        'Illustrazione-CIE-avvisi.txt': 'assets/licenses/cie-card-NOTICE.txt',
        'Avvisi-componenti-nativi.txt': 'assets/licenses/native-NOTICES.txt',
      }.entries) {
        await File('${directory.path}/${entry.key}')
            .writeAsString(await rootBundle.loadString(entry.value));
      }
      if (!await launchUrl(directory.uri)) {
        throw const FileSystemException('Licenses unavailable');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Impossibile aprire la cartella delle licenze. I testi sono inclusi nei file dell’applicazione.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, "Licenze e riconoscimenti")),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              context,
              "CIE ID include il middleware CIE e componenti di terze parti. Le licenze, le attribuzioni e gli avvisi originali sono conservati integralmente nei file distribuiti con l’applicazione.",
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              "Apri la cartella per consultare i testi completi e le licenze dei singoli componenti.",
            ),
          ),
          AppNotification(
            message: error,
            error: true,
            onDismissed: () {
              if (mounted) setState(() => error = null);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, "Chiudi")),
      ),
      FilledButton(
        onPressed: openLicenses,
        child: Text(tr(context, "Apri cartella delle licenze")),
      ),
    ],
  );
}
