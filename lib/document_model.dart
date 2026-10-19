// SPDX-License-Identifier: BSD-3-Clause
const cardholderNameAppearance = 'cie:cardholder-name-v1';

class PdfAppearance {
  const PdfAppearance({
    required this.imagePath,
    required this.page,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final String imagePath;
  final int page;
  final double left, top, width, height;
  bool get valid =>
      imagePath.isNotEmpty &&
      page >= 0 &&
      page < 100000 &&
      [left, top, width, height].every((n) => n.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      width > 0 &&
      height > 0 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;
}

String extractedFileName(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  return name.toLowerCase().endsWith('.p7m')
      ? name.substring(0, name.length - 4)
      : '$name.estratto';
}
