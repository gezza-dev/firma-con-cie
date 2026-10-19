// SPDX-License-Identifier: BSD-3-Clause
import 'package:file_selector/file_selector.dart';

import 'desktop_directory.dart';

typedef DocumentOpener = Future<XFile?> Function({
  String? initialDirectory,
  required List<XTypeGroup> acceptedTypeGroups,
});

// Both signing and verification use this same Desktop-first system dialog.
Future<String?> openDocumentDialog({
  bool signed = false,
  String languageCode = 'it',
  DocumentOpener picker = openFile,
}) async {
  final file = await picker(
    initialDirectory: await desktopDirectory(),
    acceptedTypeGroups: [
      if (signed)
        XTypeGroup(
          label: languageCode == 'en'
              ? 'Signed documents'
              : 'Documenti firmati',
          extensions: ['pdf', 'p7m', 'p7s'],
        ),
      XTypeGroup(
        label: languageCode == 'en' ? 'All documents' : 'Tutti i documenti',
      ),
    ],
  );
  return file?.path;
}
