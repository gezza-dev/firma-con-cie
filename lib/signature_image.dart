// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<ui.Image> decodeSignatureImage(File file) async {
  if (await file.length() > 10 * 1024 * 1024) {
    throw const FormatException('Immagine troppo grande (massimo 10 MiB).');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await file.readAsBytes(),
  );
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width > 8192 ||
        descriptor.height > 8192 ||
        descriptor.width * descriptor.height > 16 * 1024 * 1024) {
      throw const FormatException(
        'Immagine troppo grande: scegliere al massimo 16 megapixel.',
      );
    }
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<void> writeSignaturePng(ui.Image image, File file) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw const FormatException('Impossibile preparare l’immagine.');
  }
  await file.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
}

String signatureUtcOffsetLabel(Duration offset) {
  final minutes = offset.inMinutes;
  if (minutes == 0) return 'UTC';
  final absolute = minutes.abs();
  final remainder = absolute % 60;
  return 'UTC${minutes < 0 ? '-' : '+'}${absolute ~/ 60}'
      '${remainder == 0 ? '' : ':${remainder.toString().padLeft(2, '0')}'}';
}

String signatureDateLabel(DateTime value) {
  final local = value.toLocal();
  String n(int x) => x.toString().padLeft(2, '0');
  return '${n(local.day)}/${n(local.month)}/${local.year} '
      '${n(local.hour)}:${n(local.minute)}:${n(local.second)} '
      '${signatureUtcOffsetLabel(local.timeZoneOffset)}';
}

const signatureCaptionColor = Color(0xFF64B5F6);
const signatureSignerCaption = 'Firmato digitalmente da/Signed by:';
const signatureDateCaption = 'In Data/On Date:';

TextSpan signatureTextSpan({
  String? fullName,
  required DateTime signingDate,
  double fontSize = 60,
}) {
  final name = fullName?.isNotEmpty == true
      ? fullName!
      : 'Titolare da leggere dalla CIE';
  final caption = TextStyle(
    color: signatureCaptionColor,
    fontSize: fontSize * .6,
  );
  return TextSpan(
    style: TextStyle(color: Colors.black, fontSize: fontSize, height: 1.25),
    children: [
      TextSpan(text: '$signatureSignerCaption\n', style: caption),
      TextSpan(text: '$name\n'),
      TextSpan(text: '$signatureDateCaption\n', style: caption),
      TextSpan(
        text: signatureDateLabel(signingDate),
        style: TextStyle(fontSize: fontSize * .85),
      ),
    ],
  );
}

Future<void> writeDefaultSignatureImage(
  File file, {
  String? fullName,
  DateTime? signingDate,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final date = signingDate ?? DateTime.now();
  final painter = TextPainter(
    text: signatureTextSpan(fullName: fullName, signingDate: date),
    textDirection: TextDirection.ltr,
  )..layout();
  if (painter.width > 850) {
    painter.text = signatureTextSpan(
      fullName: fullName,
      signingDate: date,
      fontSize: 60 * 850 / painter.width,
    );
    painter.layout();
  }
  painter.paint(canvas, const Offset(12, 12));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (painter.width + 24).ceil(),
    (painter.height + 24).ceil(),
  );
  try {
    await writeSignaturePng(image, file);
  } finally {
    image.dispose();
    picture.dispose();
    painter.dispose();
  }
}

Future<void> normalizeSignatureImage(File source, File destination) async {
  final image = await decodeSignatureImage(source);
  try {
    await writeSignaturePng(image, destination);
  } finally {
    image.dispose();
  }
}
