// SPDX-License-Identifier: BSD-3-Clause
import 'package:cie_flutter_prototype/document_drop_zone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duplicate paths identify one document and preserve filename spaces',
    () {
      expect(droppedDocumentPaths(['/tmp/a .pdf ', '', '/tmp/a .pdf ']), [
        '/tmp/a .pdf ',
      ]);
    },
  );
  test('URI list recovery handles CRLF, comments, escaping and duplicates', () {
    expect(
      droppedDocumentPaths(
        [],
        rawText:
            '# URI list\r\nfile:///tmp/a%20b.pdf\r\n'
            'file:///tmp/a%20b.pdf\r\n',
      ),
      ['/tmp/a b.pdf'],
    );
  });
  test('STRING recovery accepts an explicit absolute local path', () {
    expect(droppedDocumentPaths([], rawText: '/tmp/documento.pdf'), [
      '/tmp/documento.pdf',
    ]);
  });
  test('portal keys and missing payload never become local filenames', () {
    expect(droppedDocumentPaths([], rawText: 'synthetic-portal-key'), isEmpty);
    expect(droppedDocumentPaths([]), isEmpty);
  });
  test('remote or malformed raw URIs never become local documents', () {
    expect(
      droppedDocumentPaths(
        [],
        rawText:
            'file://server/share/a.pdf\nhttps://example.invalid/a.pdf\n'
            'file://[invalid',
      ),
      isEmpty,
    );
  });
  test('different paths stay distinct even with the same filename', () {
    expect(droppedDocumentPaths(['/tmp/a.pdf', '/other/a.pdf']), [
      '/tmp/a.pdf',
      '/other/a.pdf',
    ]);
  });
}
