// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/catalog.g.dart';

class CieLocalizations {
  CieLocalizations(this.locale);
  final Locale locale;
  static const delegate = _CieLocalizationsDelegate();
  static const supportedLocales = [Locale('it'), Locale('en')];
  static CieLocalizations of(BuildContext context) =>
      Localizations.of<CieLocalizations>(context, CieLocalizations) ??
      CieLocalizations(
        Locale(
          systemLanguageCode(WidgetsBinding.instance.platformDispatcher.locale),
        ),
      );
  String text(String source, [List<Object?> arguments = const []]) {
    final messages = cieMessages[locale.languageCode] ?? cieMessages['en']!;
    var translated = messages[source];
    // Already assembled native/application messages are matched against complete
    // templates only. Captured values are never translated, stored or logged.
    if (translated == null &&
        locale.languageCode == 'en' &&
        arguments.isEmpty) {
      for (final entry in _patterns) {
        final match = entry.$1.firstMatch(source);
        if (match != null) {
          final values = [
            for (var i = 1; i <= match.groupCount; i++) match.group(i) ?? '',
          ];
          // This provider template contains a fixed, allow-listed reason rather
          // than a personal value. Other interpolated values stay untouched.
          if (entry.$2.startsWith('CryptoTokenKit non ha completato') &&
              values.length == 2) {
            values[1] = messages[values[1]] ?? values[1];
          }
          return _format(messages[entry.$2] ?? entry.$2, values);
        }
      }
    }
    return _format(translated ?? source, arguments);
  }

  static String _format(String text, List<Object?> values) =>
      text.replaceAllMapped(RegExp(r'\{p(\d+)\}'), (m) {
        final index = int.parse(m[1]!);
        return index < values.length ? '${values[index] ?? ''}' : m[0]!;
      });
  // Ignore identity formats (names, paths, dates); match the most specific
  // application message before a more general one.
  static final _translatedTemplates =
      cieMessages['it']!.keys
          .where((key) => key.contains('{p') && cieMessages['en']![key] != key)
          .toList()
        ..sort(
          (a, b) => b
              .replaceAll(RegExp(r'\{p\d+\}'), '')
              .length
              .compareTo(a.replaceAll(RegExp(r'\{p\d+\}'), '').length),
        );
  static final _patterns = [
    for (final key in _translatedTemplates)
      (
        RegExp(
          '^${RegExp.escape(key).replaceAllMapped(RegExp(r'\\\{p\d+\\\}'), (_) => '([\\s\\S]*?)')}\$',
        ),
        key,
      ),
  ];
}

String tr(
  BuildContext context,
  String source, [
  List<Object?> arguments = const [],
]) => CieLocalizations.of(context).text(source, arguments);

class _CieLocalizationsDelegate
    extends LocalizationsDelegate<CieLocalizations> {
  const _CieLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['it', 'en'].contains(locale.languageCode);
  @override
  SynchronousFuture<CieLocalizations> load(Locale locale) =>
      SynchronousFuture(CieLocalizations(locale));
  @override
  bool shouldReload(_CieLocalizationsDelegate old) => false;
}

// Only the primary system language is considered. Unsupported/unknown languages
// fall back to English, rather than selecting Italian from a secondary locale.
String systemLanguageCode(Locale? locale) =>
    locale?.languageCode.toLowerCase() == 'it' ? 'it' : 'en';

class AppLanguageController extends ChangeNotifier {
  String _selection = 'system';
  String _systemCode = systemLanguageCode(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  Locale get locale =>
      Locale(_selection == 'system' ? _systemCode : _selection);

  Future<void> initializeSystemLanguage() async {
    // Cocoa may have cached an older app-specific language. Ask the runner for
    // the actual OS preference, independent from this app's saved override.
    try {
      final code = await const MethodChannel('cie.id/application')
          .invokeMethod<String>('systemLanguage');
      _systemCode = code == 'it' ? 'it' : 'en';
    } on MissingPluginException {
      // Windows/Linux use Flutter's primary platform locale.
    } on PlatformException {
      _systemCode = 'en';
    }
    if (!_disposed && _selection == 'system') _apply();
  }

  bool _disposed = false;
  void select(String code) {
    if (!['system', 'it', 'en'].contains(code) || _disposed) return;
    _selection = code;
    _apply();
  }

  void _apply() {
    notifyListeners();
    // Only this application's menus/preferences are changed, never global language.
    const MethodChannel('cie.id/application')
        .invokeMethod<void>('setLanguage', locale.languageCode)
        .catchError((_) {});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppLanguageController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.notifier;
}
