// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/foundation.dart';

enum AppDestination {
  home('Home'),
  sign('Firma Elettronica'),
  verify('Verifica Firma'),
  changePin('Cambia PIN'),
  unblock('Sblocca Carta'),
  guide('Guida'),
  assistance('Assistenza'),
  information('Informazioni'),
  settings('Impostazioni');

  const AppDestination(this.label);
  final String label;
}

// Shared navigation/operation contract; no card or platform operations here.
class AppFlowController extends ChangeNotifier {
  AppDestination destination = AppDestination.home;
  final List<AppDestination> _history = [];
  bool busy = false;
  String progress = '';
  bool get canGoBack => !busy && _history.isNotEmpty;

  bool navigate(AppDestination next) {
    if (busy || next == destination) return false;
    _history.add(destination);
    destination = next;
    notifyListeners();
    return true;
  }

  bool back() {
    if (!canGoBack) return false;
    destination = _history.removeLast();
    notifyListeners();
    return true;
  }
}

// These models own document-dependent state. Views never reuse results for a
// changed input/card. Sensitive controllers and temporary files stay scoped to
// the active view/operation, rather than being retained in navigation history.
class SignFlowState {
  String input = '', output = '', format = 'pdf';
  Map<String, dynamic>? result;
  void selectDocument(String path, String nextFormat, String destination) {
    input = path;
    format = nextFormat;
    output = destination;
    result = null;
  }

  void changeCard() {
    result = null;
  }

  void conclude() {
    input = '';
    output = '';
    result = null;
  }
}
