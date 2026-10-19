// SPDX-License-Identifier: BSD-3-Clause
import 'native_bridge.dart';

String homeCardStatus({
  required List<JsonResult> readers,
  required bool checked,
  String? error,
}) {
  if (error != null) {
    return 'Rilevamento temporaneamente non disponibile. Verifica il collegamento del lettore.';
  }
  if (!checked) return 'Ricerca del lettore…';
  if (readers.isEmpty) return 'Collega il lettore.';
  if (readers.any((r) => r['isCie'] == true)) {
    return 'CIE presente nel lettore.';
  }
  final occupied = readers.any(
    (r) => r['occupied'] == true || r['identificationCode'] == -3,
  );
  if (occupied) {
    return 'Carta in uso: attendi che l’altra applicazione abbia terminato.';
  }
  // SCARD_W_UNPOWERED_CARD / SCARD_W_RESET_CARD. Missing Web identity,
  // absent card, unknown errors and PIN failures are not evidence for this advice.
  if (readers.any((r) {
    final code = r['nativeCode'];
    return code is int &&
        const {0x80100067, 0x80100068}.contains(code & 0xffffffff);
  })) {
    return 'La connessione con la carta è stata interrotta. Rimuovi la CIE dal lettore e riappoggiala.';
  }
  if (readers.every((r) => r['present'] != true)) {
    return 'Appoggia la CIE al lettore.';
  }
  return 'Carta non riconosciuta. Verifica che sia una CIE e che sia appoggiata correttamente.';
}
