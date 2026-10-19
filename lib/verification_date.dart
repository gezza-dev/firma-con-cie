// SPDX-License-Identifier: BSD-3-Clause
// Certificate/CMS dates are not local wall-clock times. Parse ASN.1 UTC /
// GeneralizedTime and explicit-zone ISO without accepting calendar rollover.
String verificationDate(Object? input) {
  if (input is! String || input.trim().isEmpty) return 'Non disponibile';
  final raw = input.trim();
  var match = RegExp(
    r'^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:[.,]\d+)?(Z|[+-]\d{4})$',
  ).firstMatch(raw);
  match ??= RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(raw);
  if (match == null) return 'Formato data non riconosciuto';
  final parts = List.generate(6, (i) => int.parse(match!.group(i + 1)!));
  var year = parts[0];
  if (match.group(1)!.length == 2) year += year < 50 ? 2000 : 1900;
  final date = DateTime.utc(
    year,
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (date.year != year ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4] ||
      date.second != parts[5]) {
    return 'Formato data non riconosciuto';
  }
  final zone = match.group(7)!.replaceAll(':', '');
  var offset = 0;
  if (zone != 'Z') {
    final hours = int.parse(zone.substring(1, 3)),
        minutes = int.parse(zone.substring(3));
    if (hours > 23 || minutes > 59) return 'Formato data non riconosciuto';
    offset = (hours * 60 + minutes) * (zone.startsWith('-') ? -1 : 1);
  }
  final utc = date.subtract(Duration(minutes: offset));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(utc.day)}/${two(utc.month)}/${utc.year.toString().padLeft(4, '0')} '
      'alle ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} UTC';
}
