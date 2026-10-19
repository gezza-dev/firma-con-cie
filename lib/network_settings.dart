// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';

enum ProxyMode { direct, http, https }

enum AppDiagnosticLevel { off, errors, operations }

class ProxySettings {
  const ProxySettings({
    this.mode = ProxyMode.direct,
    this.host = '',
    this.port = 0,
  });
  final ProxyMode mode;
  final String host;
  final int port;
  void validate() {
    if (mode == ProxyMode.direct) {
      if (host.isNotEmpty || port != 0) {
        throw const FormatException('Connessione diretta non valida');
      }
      return;
    }
    final ipv6 =
        !host.contains('%') &&
        host.startsWith('[') &&
        host.endsWith(']') &&
        InternetAddress.tryParse(host.substring(1, host.length - 1))?.type ==
            InternetAddressType.IPv6;
    final labels = host.split('.');
    final dns =
        host.isNotEmpty &&
        host.length <= 253 &&
        labels.every(
          (l) =>
              l.isNotEmpty &&
              l.length <= 63 &&
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(l),
        );
    if (!(ipv6 || dns) || port < 1 || port > 65535) {
      throw const FormatException(
        'Inserire un nome host o IP senza URL e una porta da 1 a 65535. Per IPv6 usare le parentesi quadre.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'host': host,
    'port': port,
  };
  factory ProxySettings.fromJson(Map data) {
    if (data.keys.toSet().difference({'mode', 'host', 'port'}).isNotEmpty ||
        data['host'] is! String ||
        data['port'] is! int) {
      throw const FormatException('Proxy non valido');
    }
    final value = ProxySettings(
      mode: ProxyMode.values.byName(data['mode'] as String),
      host: data['host'],
      port: data['port'],
    );
    value.validate();
    return value;
  }
}

class SessionNetworkConfig {
  const SessionNetworkConfig({
    this.proxy = const ProxySettings(),
    this.username = '',
    this.password = '',
  });
  final ProxySettings proxy;
  final String username, password;
  bool get hasAuthentication => username.isNotEmpty;
  void validate() {
    proxy.validate();
    bool bad(String s, int maximum) =>
        utf8.encode(s).length > maximum ||
        s.runes.any((c) => c < 32 || c == 127);
    if (bad(username, 256) ||
        bad(password, 1024) ||
        username.contains(':') ||
        (password.isNotEmpty && username.isEmpty) ||
        (proxy.mode == ProxyMode.direct &&
            (username.isNotEmpty || password.isNotEmpty))) {
      throw const FormatException(
        'Credenziali proxy non valide. Il nome utente non deve contenere due punti o caratteri di controllo.',
      );
    }
  }

  // Passed through private stdin pipes, never process arguments or the environment.
  String toWire() {
    validate();
    return 'CIE-NETWORK-1\n${proxy.mode.index}\n${proxy.host}\n${proxy.port}\n$username\n$password\n';
  }
}

class AppSettings {
  const AppSettings({
    this.proxy = const ProxySettings(),
    this.diagnostics = AppDiagnosticLevel.off,
    this.languageCode = 'system',
    this.themeCode = 'system',
  });
  final ProxySettings proxy;
  final AppDiagnosticLevel diagnostics;
  final String languageCode, themeCode;
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'proxy': proxy.toJson(),
    'diagnostics': diagnostics.name,
    'language': languageCode,
    'theme': themeCode,
  };
  factory AppSettings.fromJson(Object? data) {
    if (data is! Map ||
        data['schema'] != 1 ||
        data['proxy'] is! Map ||
        data.keys.toSet().difference({
          'schema',
          'proxy',
          'diagnostics',
          'language',
          'theme',
        }).isNotEmpty ||
        (data['theme'] != null &&
            !['system', 'light', 'dark'].contains(data['theme'])) ||
        (data['language'] != null &&
            !['system', 'it', 'en'].contains(data['language']))) {
      throw const FormatException('Impostazioni non valide');
    }
    return AppSettings(
      languageCode: data['language'] as String? ?? 'system',
      themeCode: data['theme'] as String? ?? 'system',
      proxy: ProxySettings.fromJson(data['proxy']),
      diagnostics: AppDiagnosticLevel.values.byName(
        data['diagnostics'] as String,
      ),
    );
  }
}
