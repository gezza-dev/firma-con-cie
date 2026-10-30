// SPDX-License-Identifier: BSD-3-Clause
import 'native_bridge.dart';
import 'windows_web_setup.dart';

enum WebComponentAction { appUpdate, installer, activate, systemSettings }

/// A computer-wide notice, driven by the platform's read-only status flags.
/// An absent card or an unobserved identity never implies a setup requirement.
class WebComponentSetupNotice {
  WebComponentSetupNotice._(this.action, this.message, this.label, this.update);

  final WebComponentAction action;
  final String message, label;
  final bool update;

  static WebComponentSetupNotice? fromStatus(JsonResult system) {
    if (system['activationState'] == 'unknown' ||
        system['ok'] == false ||
        system['code'] == 'busy') {
      return null;
    }
    if (system['componentHostOutdated'] == true) {
      return WebComponentSetupNotice._(
        WebComponentAction.appUpdate,
        'È presente un componente più recente. Apri la versione più recente di Firma con CIE. L’abbinamento è conservato.',
        'Informazioni accesso ai siti',
        false,
      );
    }
    if (system['available'] == true) return null;
    final update = system['componentNeedsUpdate'] == true;
    if (system['componentInstallerRequired'] == true) {
      return WebComponentSetupNotice._(
        WebComponentAction.installer,
        system['componentStatusMessage'] as String? ??
            windowsComponentUpdateMessage,
        update ? 'Aggiorna accesso ai siti' : 'Informazioni accesso ai siti',
        update,
      );
    }
    if (system['canActivateComponent'] == true) {
      return WebComponentSetupNotice._(
        WebComponentAction.activate,
        update
            ? 'Il componente per l’accesso ai siti deve essere aggiornato. L’abbinamento è conservato; non occorre reinserire il PIN.'
            : 'Per accedere ai siti, attiva il componente Firma con CIE.',
        update ? 'Aggiorna accesso ai siti' : 'Attiva accesso ai siti',
        update,
      );
    }
    if (system['canOpenSystemSettings'] == true) {
      return WebComponentSetupNotice._(
        WebComponentAction.systemSettings,
        'Per accedere ai siti, abilita il componente nelle Impostazioni di Sistema. L’abbinamento per firmare è conservato.',
        'Apri Impostazioni di Sistema',
        update,
      );
    }
    return null;
  }
}
