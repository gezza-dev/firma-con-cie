// SPDX-License-Identifier: BSD-3-Clause
// Explicit opt-in integration tests. They load the real private runtime, but
// never call detect, observe, enroll, sign, updatePin or any system registration.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cie_flutter_prototype/native_bridge.dart';
import 'package:cie_flutter_prototype/verification_flow.dart';
import 'package:cie_flutter_prototype/verification_view.dart';

void main() {
  const enabled = bool.fromEnvironment('CIE_UX4_RUNTIME_TESTS');
  group('real UX4 document pipeline', () {
    late FfiCieService service;
    setUp(() async {
      service = FfiCieService(BridgePaths.discover());
      expect((await service.load())['ok'], isTrue);
    });
    test('unsigned PDF is distinguished from corrupted PDF bytes', () async {
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      try {
        await controller.select('reports/ux4-fixtures/source.pdf');
        expect(controller.result!['ok'], isTrue);
        expect(controller.result!['signatureCount'], 0);
        expect(controller.extractable, isFalse);
        await controller.select('reports/ux4-fixtures/not-a-pdf.pdf');
        expect(controller.result!['ok'], isFalse);
      } finally {
        controller.cancel();
        await controller.settled;
        controller.dispose();
      }
    });
    test('real PDF signature stays intact without promoting a self-signed test certificate', () async {
      final controller = VerificationController(
        service,
        canExtract: () => true,
      );
      try {
        await controller.select('reports/ux4-fixtures/visible-0.pdf');
        expect(controller.result!['ok'], isTrue);
        final signer = (controller.result!['signers'] as List).first as Map;
        expect(signer['signatureValid'], isTrue);
        expect(certificateOutcome(signer), isNot(CheckOutcome.positive));
      } finally {
        controller.cancel();
        await controller.settled;
        controller.dispose();
      }
    });
    test(
      'CMS extraction exports verified snapshot bytes and rejects detached CMS',
      () async {
        final controller = VerificationController(
          service,
          canExtract: () => true,
        );
        final output = await Directory.systemTemp.createTemp(
          'cie-ux4-integration-',
        );
        try {
          await controller.select('reports/ux4-fixtures/document.pdf.p7m');
          expect(controller.result!['ok'], isTrue);
          expect(controller.extractable, isTrue);
          await controller.extract((_) async => '${output.path}/content.pdf');
          expect(controller.extraction!['ok'], isTrue);
          expect(
            await File('${output.path}/content.pdf').readAsBytes(),
            await File('reports/ux4-fixtures/source.pdf').readAsBytes(),
          );
          await controller.select('reports/ux4-fixtures/detached.p7m');
          expect(controller.extractable, isFalse);
        } finally {
          controller.cancel();
          await controller.settled;
          controller.dispose();
          await output.delete(recursive: true);
        }
      },
    );
  }, skip: !enabled);
}
