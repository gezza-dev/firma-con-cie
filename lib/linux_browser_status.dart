// SPDX-License-Identifier: BSD-3-Clause
import 'enrollment.dart';
import 'native_bridge.dart';

const flatpakWebMessage =
    'Per configurare l’accesso ai siti, installa il componente «Accesso ai siti per Firma con CIE Flatpak», poi premi «Rileggi».';

/// Uses only the inspections already performed by the Home setup cards.
/// A configured profile confirms registration, never a successful website login.
class LinuxBrowserConfiguration {
  const LinuxBrowserConfiguration({this.firefox, this.chrome});
  final JsonResult? firefox, chrome;

  List<String> get enabledBrowsers {
    final raw = firefox?['profiles'];
    final profiles = firefox?['ok'] == true && raw is List
        ? raw.whereType<Map>()
        : <Map>[];
    return [
      if (profiles.any(
        (p) => p['target'] == 'firefox' && p['state'] == 'configured',
      ))
        'Firefox',
      if (firefox?['snapPermission'] == 'connected' &&
          profiles.any(
            (p) => p['target'] == 'snap' && p['state'] == 'configured',
          ))
        'Firefox Snap',
      if (chrome?['ok'] == true &&
          chrome?['detected'] == true &&
          chrome?['state'] == 'configured')
        'Google Chrome',
    ];
  }

  bool get _unknown {
    if (firefox?['ok'] != true || chrome?['ok'] != true) return true;
    final profiles = firefox?['profiles'];
    if (profiles is! List ||
        profiles.any(
          (p) =>
              p is! Map ||
              !{
                'configured',
                'needs_setup',
                'profile_uninitialized',
              }.contains(p['state']) ||
              !{'firefox', 'snap'}.contains(p['target']),
        )) {
      return true;
    }
    if (profiles.any(
          (p) => p['target'] == 'snap' && p['state'] != 'profile_uninitialized',
        ) &&
        !{'connected', 'disconnected'}.contains(firefox?['snapPermission'])) {
      return true;
    }
    return !{
      'configured',
      'needs_setup',
      'database_uninitialized',
      'not_installed',
    }.contains(chrome?['state']);
  }

  String get message {
    final browsers = enabledBrowsers;
    if (browsers.isNotEmpty) {
      return 'Accesso ai siti con CIE configurato. Apri il sito nei seguenti browser: ${browsers.join(', ')}.';
    }
    if (firefox == null || chrome == null) {
      return 'Verifica della configurazione dei browser in corso…';
    }
    if (_unknown) {
      return 'Impossibile verificare la configurazione dei browser. Controlla gli avvisi in cima alla Home.';
    }
    return 'Accesso ai siti da configurare. Usa i riquadri in cima alla Home per configurare Firefox o Chrome.';
  }
}

String linuxPairedWebStatus(
  EnrollmentRecord record,
  LinuxBrowserConfiguration configuration,
) =>
    record.readyForSigning &&
        record.hasPublicData &&
        record.webProvisioned &&
        record.componentAvailable &&
        record.needsBrowserRegistration &&
        !record.needsAppUpdate &&
        record.system['componentStatusMessage'] is! String
    ? configuration.message
    : record.webStatus;
