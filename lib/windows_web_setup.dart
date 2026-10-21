// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_bridge.dart';

typedef WindowsWebComponentChecker = Future<JsonResult> Function(String reader);

Future<JsonResult> checkWindowsWebComponent(String reader) async {
  if (!Platform.isWindows) return {'ok': true};
  const channel = MethodChannel('cie.id/windows-web-setup');
  try {
    await channel.invokeMethod<bool>('check', {'reader': reader});
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final state = await channel.invokeMapMethod<String, dynamic>('status');
      if (state?['pending'] == true) continue;
      final code = state?['nativeCode'];
      if (code == 0) return {'ok': true, 'nativeCode': 0};
      return {
        'ok': false,
        'nativeCode': code,
        'code': code == 10 ? 'web_component_missing' : 'web_setup_failed',
        'message': switch (code) {
          2 || 10 => 'Il componente per l’accesso ai siti non è disponibile. Esegui il pacchetto di installazione di CIE ID Desktop. Gli abbinamenti e le impostazioni saranno conservati.',
          3 => 'Un altro componente gestisce già questa carta. Nessun componente esistente è stato sostituito.',
          4 || 5 => 'Mantieni la CIE sul lettore selezionato e chiudi le altre applicazioni che la stanno utilizzando. Nessun PIN è stato inviato.',
          6 => 'Il componente Windows manca o non supera il controllo di integrità. Esegui nuovamente il pacchetto di installazione di CIE ID Desktop.',
          9 => 'La configurazione del componente richiede una verifica. I file sono stati conservati per evitare di interrompere componenti già registrati.',
          _ => 'Verifica del componente Windows non riuscita. Esegui nuovamente il pacchetto di installazione di CIE ID Desktop. Nessun PIN è stato inviato.',
        },
      };
    }
  } on PlatformException {
    return {
      'ok': false,
      'code': 'web_setup_failed',
      'message': 'Verifica del componente Windows non riuscita. Esegui nuovamente il pacchetto di installazione di CIE ID Desktop. Nessun PIN è stato inviato.',
    };
  } on MissingPluginException {
    return {
      'ok': false,
      'code': 'web_setup_unavailable',
      'message': 'Il componente Windows manca o non supera il controllo di integrità. Esegui nuovamente il pacchetto di installazione di CIE ID Desktop.',
    };
  }
}
