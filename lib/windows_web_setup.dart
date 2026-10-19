// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_bridge.dart';

typedef WindowsWebInstaller = Future<JsonResult> Function(String reader);

Future<JsonResult> installWindowsWebComponent(String reader) async {
  if (!Platform.isWindows) return {'ok': true};
  const channel = MethodChannel('cie.id/windows-web-setup');
  try {
    await channel.invokeMethod<bool>('install', {'reader': reader});
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final state = await channel.invokeMapMethod<String, dynamic>('status');
      if (state?['pending'] == true) continue;
      final code = state?['nativeCode'];
      if (code == 0) return {'ok': true, 'nativeCode': 0};
      return {
        'ok': false,
        'nativeCode': code,
        'code': code == 1223 ? 'web_setup_cancelled' : 'web_setup_failed',
        'message': switch (code) {
          1223 => 'Installazione annullata nella richiesta di autorizzazione di Windows. Gli abbinamenti esistenti sono conservati.',
          2 => 'Windows non ha concesso i privilegi amministrativi necessari per attivare l’accesso ai siti.',
          3 => 'Un altro componente gestisce già questa carta. L’installazione è stata interrotta senza sostituire i componenti esistenti.',
          4 || 5 => 'Mantieni la CIE sul lettore selezionato e chiudi le altre applicazioni che la stanno utilizzando. Nessun PIN è stato inviato.',
          6 => 'Il pacchetto del componente Windows manca o non supera il controllo di integrità. Usa una copia completa dell’applicazione.',
          9 => 'La configurazione del componente richiede una verifica. I file sono stati conservati per evitare di interrompere componenti già registrati.',
          _ => 'Installazione del componente Windows non completata. Nessun PIN è stato inviato e non viene eseguito un nuovo tentativo automatico.',
        },
      };
    }
  } on PlatformException {
    return {
      'ok': false,
      'code': 'web_setup_failed',
      'message': 'Installazione del componente Windows non completata. Nessun PIN è stato inviato e non viene eseguito un nuovo tentativo automatico.',
    };
  } on MissingPluginException {
    return {
      'ok': false,
      'code': 'web_setup_unavailable',
      'message': 'Il pacchetto del componente Windows manca o non supera il controllo di integrità. Usa una copia completa dell’applicazione.',
    };
  }
}
