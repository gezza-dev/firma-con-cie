// SPDX-License-Identifier: BSD-3-Clause
import 'dart:typed_data';

// Public X.509 dates are presentation metadata, never a substitute for SOD,
// chain, revocation or browser validation. No card or network access occurs.
class CertificateValidity {
  const CertificateValidity(this.notBefore, this.notAfter);
  final DateTime notBefore, notAfter;
  bool expiredAt(DateTime now) => now.toUtc().isAfter(notAfter);
  bool notYetValidAt(DateTime now) => now.toUtc().isBefore(notBefore);

  static CertificateValidity? fromHex(Object? hex) {
    if (hex is! String ||
        hex.isEmpty ||
        hex.length > 16384 ||
        !RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(hex)) {
      return null;
    }
    try {
      final bytes = Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      final outer = _Der(bytes, 0, bytes.length);
      final certificate = outer.read(0x30);
      if (!outer.done) return null;
      final tbs = certificate.read(0x30);
      if (tbs.peek == 0xa0) tbs.read(0xa0);
      tbs.read(0x02); // serial
      tbs.read(0x30); // signature algorithm
      tbs.read(0x30); // issuer
      final validity = tbs.read(0x30);
      final start = validity.time(), end = validity.time();
      if (!validity.done || end.isBefore(start)) return null;
      return CertificateValidity(start, end);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }
}

class _Der {
  _Der(this.bytes, this.position, this.end);
  final Uint8List bytes;
  int position;
  final int end;
  bool get done => position == end;
  int get peek {
    if (position >= end) throw const FormatException();
    return bytes[position];
  }

  _Der read(int tag) {
    if (peek != tag) throw const FormatException();
    position++;
    if (position >= end) throw const FormatException();
    var length = bytes[position++];
    if (length >= 128) {
      final count = length & 127;
      if (count == 0 ||
          count > 2 ||
          position + count > end ||
          bytes[position] == 0) {
        throw const FormatException();
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = length * 256 + bytes[position++];
      }
      if (length < 128) throw const FormatException();
    }
    if (length > end - position) throw const FormatException();
    final value = _Der(bytes, position, position + length);
    position += length;
    return value;
  }

  DateTime time() {
    final tag = peek;
    if (tag != 0x17 && tag != 0x18) throw const FormatException();
    final field = read(tag);
    final text = String.fromCharCodes(bytes.sublist(field.position, field.end));
    final digits = tag == 0x17 ? 12 : 14;
    if (!RegExp('^[0-9]{$digits}Z\$').hasMatch(text)) {
      throw const FormatException();
    }
    var offset = tag == 0x17 ? 2 : 4;
    var year = int.parse(text.substring(0, offset));
    if (tag == 0x17) year += year >= 50 ? 1900 : 2000;
    int next() {
      final n = int.parse(text.substring(offset, offset + 2));
      offset += 2;
      return n;
    }

    final month = next(),
        day = next(),
        hour = next(),
        minute = next(),
        second = next();
    final result = DateTime.utc(year, month, day, hour, minute, second);
    if (year == 0 ||
        result.year != year ||
        result.month != month ||
        result.day != day ||
        result.hour != hour ||
        result.minute != minute ||
        result.second != second) {
      throw const FormatException();
    }
    return result;
  }
}
