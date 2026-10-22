// SPDX-License-Identifier: BSD-3-Clause
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_bridge.dart';

typedef WindowsWebComponentChecker = Future<JsonResult> Function(String reader);

const windowsComponentUpdateMessage =
    'Il componente per l’accesso ai siti deve essere aggiornato. Esegui il pacchetto di installazione di Firma con CIE. Abbinamenti e impostazioni saranno conservati.';

Future<JsonResult> readWindowsWebComponentStatus() async {
  if (!Platform.isWindows) return {};
  const channel = MethodChannel('cie.id/windows-web-setup');
  int? code;
  try {
    await channel.invokeMethod<bool>('checkPackage');
    for (var attempt = 0; attempt < 160; attempt++) {
      final state = await channel.invokeMapMethod<String, dynamic>(
        'packageStatus',
      );
      if (state?['pending'] != true) {
        code = state?['nativeCode'] as int?;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } on PlatformException {
    // An unverified component must not be presented as current.
  } on MissingPluginException {
    // A missing runner/helper requires a complete application package.
  }
  final update = [6, 9, 10, 11].contains(code);
  return {
    'available': code == 0,
    'componentVersionMatches': code == 0,
    'componentNeedsUpdate': update,
    'componentInstallerRequired': code != 0,
    'componentStatusCode': ?code,
    if (code != 0)
      'componentStatusMessage': update
          ? windowsComponentUpdateMessage
          : code == 3
          ? 'La configurazione del componente per l’accesso ai siti è in conflitto con un altro componente. Gli abbinamenti e le impostazioni sono conservati.'
          : 'Non è stato possibile verificare la versione del componente per l’accesso ai siti. Gli abbinamenti e le impostazioni sono conservati. Riapri l’app per ripetere il controllo.',
  };
}

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
          2 || 10 => 'Il componente per l’accesso ai siti non è disponibile. Esegui il pacchetto di installazione di Firma con CIE. Gli abbinamenti e le impostazioni saranno conservati.',
          3 => 'Un altro componente gestisce già questa carta. Nessun componente esistente è stato sostituito.',
          4 || 5 => 'Mantieni la CIE sul lettore selezionato e chiudi le altre applicazioni che la stanno utilizzando. Nessun PIN è stato inviato.',
          6 => 'Il componente Windows manca o non supera il controllo di integrità. Esegui nuovamente il pacchetto di installazione di Firma con CIE.',
          9 => 'La configurazione del componente richiede una verifica. I file sono stati conservati per evitare di interrompere componenti già registrati.',
          _ => 'Verifica del componente Windows non riuscita. Esegui nuovamente il pacchetto di installazione di Firma con CIE. Nessun PIN è stato inviato.',
        },
      };
    }
  } on PlatformException {
    return {
      'ok': false,
      'code': 'web_setup_failed',
      'message': 'Verifica del componente Windows non riuscita. Esegui nuovamente il pacchetto di installazione di Firma con CIE. Nessun PIN è stato inviato.',
    };
  } on MissingPluginException {
    return {
      'ok': false,
      'code': 'web_setup_unavailable',
      'message': 'Il componente Windows manca o non supera il controllo di integrità. Esegui nuovamente il pacchetto di installazione di Firma con CIE.',
    };
  }
}
