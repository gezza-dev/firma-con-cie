// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'native_bridge.dart';
import 'app_theme.dart';
import 'linux_text_scaling.dart';
import 'verification_view.dart';
import 'pin_management.dart';
import 'pairing_view.dart';
import 'web_access.dart';
import 'signature_appearance.dart';
import 'document_drop_zone.dart';
import 'desktop_page_body.dart';
import 'preferences.dart';
import 'preferences_view.dart';
import 'guide_view.dart';
import 'assistance_view.dart';
import 'app_settings.dart';
import 'settings_view.dart';
import 'diagnostics.dart';
import 'app_flow.dart';
import 'page_header.dart';
import 'information_view.dart';
import 'card_monitor.dart';
import 'enrollment.dart';
import 'windows_web_setup.dart';
import 'web_component_setup.dart';
import 'firefox_setup.dart';
import 'chrome_setup.dart';
import 'enrollment_diagnostics_view.dart';
import 'home_card_status.dart';
import 'paired_card_identity.dart';
import 'signing_document.dart';
import 'document_dialogs.dart';
import 'verification_flow.dart';
export 'verification_flow.dart'
    show VerificationSaveRequest, VerificationSavePicker;
export 'signing_document.dart' show SignedFileRequest, SignedFilePicker;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final item in {
      'CIE middleware e SDK': 'assets/licenses/native-LICENSE.txt',
      'Dipendenze native CIE': 'assets/licenses/native-NOTICES.txt',
      'Firma con CIE': 'assets/licenses/prototype-LICENSE.txt',
      'Illustrazione CIE · IPZS': 'assets/licenses/cie-card-NOTICE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        item.key,
      ], await rootBundle.loadString(item.value));
    }
  });
  runApp(
    CiePrototype(
      service: FfiCieService(BridgePaths.discover()),
      preferences: FilePreferencesStore(),
      settings: FileSettingsStore(),
      webStatusReader: Platform.isWindows
          ? readWindowsWebComponentStatus
          : readWebSystemStatus,
      windowsWebComponentChecker: Platform.isWindows
          ? checkWindowsWebComponent
          : null,
      firefoxSetupService: Platform.isLinux ? LinuxFirefoxSetupService() : null,
      chromeSetupService: Platform.isLinux ? LinuxChromeSetupService() : null,
    ),
  );
}

class CiePrototype extends StatefulWidget {
  const CiePrototype({
    super.key,
    required this.service,
    this.preferences,
    this.settings,
    this.signedFilePicker,
    this.verificationFilePicker,
    this.verificationSavePicker,
    this.webPublisher = publishWebCertificate,
    this.webStatusReader = readWebSystemStatus,
    this.webSettingsOpener = openWebSystemSettings,
    this.webComponentActivator = activateWebComponent,
    this.windowsWebComponentChecker,
    this.firefoxSetupService,
    this.chromeSetupService,
  });
  final PreferencesStore? preferences;
  final SettingsStore? settings;
  final SignedFilePicker? signedFilePicker;
  final Future<String?> Function()? verificationFilePicker;
  final VerificationSavePicker? verificationSavePicker;
  final CieService service;
  final WebPublisher webPublisher;
  final WebStatusReader webStatusReader;
  final WebSettingsOpener webSettingsOpener;
  final WebComponentActivator webComponentActivator;
  final WindowsWebComponentChecker? windowsWebComponentChecker;
  final FirefoxSetupService? firefoxSetupService;
  final ChromeSetupService? chromeSetupService;
  @override
  State<CiePrototype> createState() => _CiePrototypeState();
}

class _CiePrototypeState extends State<CiePrototype> {
  final language = AppLanguageController();
  final appearance = AppThemeController();
  @override
  void initState() {
    super.initState();
    language.addListener(_languageChanged);
    appearance.addListener(_languageChanged);
    unawaited(language.initializeSystemLanguage());
  }

  void _languageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    language.removeListener(_languageChanged);
    language.dispose();
    appearance.removeListener(_languageChanged);
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    controller: language,
    child: AppThemeScope(
      controller: appearance,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Firma con CIE',
        locale: language.locale,
        supportedLocales: CieLocalizations.supportedLocales,
        localizationsDelegates: [
          CieLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: cieTheme(Brightness.light),
        darkTheme: cieTheme(Brightness.dark),
        themeMode: appearance.mode,
        builder: (context, child) => LinuxTextScaling(child: child!),
        home: PrototypeHome(
          service: widget.service,
          preferences: widget.preferences,
          settings: widget.settings,
          signedFilePicker: widget.signedFilePicker,
          verificationFilePicker: widget.verificationFilePicker,
          verificationSavePicker: widget.verificationSavePicker,
          webPublisher: widget.webPublisher,
          webStatusReader: widget.webStatusReader,
          webSettingsOpener: widget.webSettingsOpener,
          webComponentActivator: widget.webComponentActivator,
          windowsWebComponentChecker: widget.windowsWebComponentChecker,
          firefoxSetupService: widget.firefoxSetupService,
          chromeSetupService: widget.chromeSetupService,
        ),
      ),
    ),
  );
}

class PrototypeHome extends StatefulWidget {
  const PrototypeHome({
    super.key,
    required this.service,
    this.preferences,
    this.settings,
    this.signedFilePicker,
    this.verificationFilePicker,
    this.verificationSavePicker,
    this.webPublisher = publishWebCertificate,
    this.webStatusReader = readWebSystemStatus,
    this.webSettingsOpener = openWebSystemSettings,
    this.webComponentActivator = activateWebComponent,
    this.windowsWebComponentChecker,
    this.firefoxSetupService,
    this.chromeSetupService,
  });
  final PreferencesStore? preferences;
  final SettingsStore? settings;
  final SignedFilePicker? signedFilePicker;
  final Future<String?> Function()? verificationFilePicker;
  final VerificationSavePicker? verificationSavePicker;
  final CieService service;
  final WebPublisher webPublisher;
  final WebStatusReader webStatusReader;
  final WebSettingsOpener webSettingsOpener;
  final WebComponentActivator webComponentActivator;
  final WindowsWebComponentChecker? windowsWebComponentChecker;
  final FirefoxSetupService? firefoxSetupService;
  final ChromeSetupService? chromeSetupService;
  @override
  State<PrototypeHome> createState() => _PrototypeHomeState();
}

class _PrototypeHomeState extends State<PrototypeHome>
    with WidgetsBindingObserver {
  final diagnostics = DiagnosticRecorder();
  late final service = DiagnosticCieService(widget.service, diagnostics);
  late final SettingsStore settingsStore =
      widget.settings ?? MemorySettingsStore();
  AppSettings settings = const AppSettings();
  SessionNetworkConfig network = const SessionNetworkConfig();
  JsonResult? capabilities;
  bool settingsLoaded = false, settingsValid = true;
  Future<void> _saveSettings(
    AppSettings value,
    SessionNetworkConfig config,
  ) async {
    config.validate();
    await settingsStore.save(value);
    service.setNetwork(config);
    diagnostics.level = value.diagnostics;
    if (value.diagnostics == AppDiagnosticLevel.off) diagnostics.clear();
    if (mounted) {
      setState(() {
        settings = value;
        network = config;
        AppLanguageScope.of(context)?.select(value.languageCode);
        AppThemeScope.of(context)?.select(value.themeCode);
        settingsValid = true;
      });
    }
  }

  bool appearanceSaving = false;
  Future<void> _changeAppearance({
    String? languageCode,
    String? themeCode,
  }) async {
    if (appearanceSaving || busy) return;
    setState(() => appearanceSaving = true);
    final next = AppSettings(
      proxy: settings.proxy,
      diagnostics: settings.diagnostics,
      languageCode: languageCode ?? settings.languageCode,
      themeCode: themeCode ?? settings.themeCode,
    );
    try {
      // UI preferences never wait for reader observation or reconfigure services.
      await settingsStore.save(next);
      if (!mounted) return;
      setState(() => settings = next);
      AppLanguageScope.of(context)?.select(next.languageCode);
      AppThemeScope.of(context)?.select(next.themeCode);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = {
            'ok': false,
            'message': 'Impossibile salvare le preferenze dell’interfaccia.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => appearanceSaving = false);
    }
  }

  void _settingsBusy(bool value) {
    if (mounted) {
      setState(() {
        busy = value;
        progress = value ? 'Aggiornamento impostazioni…' : '';
      });
      unawaited(_coordinateMonitor());
    }
  }

  Future<void> _browserSetupBusy(bool value) async {
    if (!mounted) return;
    setState(() {
      busy = value;
      progress = value ? 'Configurazione accesso ai siti…' : '';
    });
    await _coordinateMonitor();
  }

  CardMonitor? monitor;
  late final enrollment = EnrollmentController(
    service,
    publisher: widget.webPublisher,
    systemStatus: widget.webStatusReader,
  );
  bool unified = false, modalInteraction = false, observationSuspended = false;
  String? homeMessage;
  int notificationRevision = 0;
  bool exiting = false;
  Future<void> _coordinateMonitor() async {
    await monitor?.setPaused(
      exiting || busy || modalInteraction || observationSuspended || !ready,
    );
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    exiting = true;
    await monitor?.setPaused(true);
    if (widget.service is CancellableCardObservation) {
      await (widget.service as CancellableCardObservation)
          .cancelCardObservation();
    }
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Desktop focus loss/minimization must not stop public card detection.
    // Suspend only when the OS suspends/detaches the app, or during operations.
    observationSuspended =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeWebStatus());
    } else {
      unawaited(_coordinateMonitor());
    }
  }

  bool refreshingWebStatus = false, waitingForWebSettings = false;
  void _updateWebSettingsMessage() {
    if (waitingForWebSettings &&
        enrollment.system['canOpenSystemSettings'] != true) {
      waitingForWebSettings = false;
      homeMessage = enrollment.message;
    }
  }

  Future<void> _resumeWebStatus() async {
    if (refreshingWebStatus || busy || modalInteraction || !unified) {
      unawaited(_coordinateMonitor());
      return;
    }
    refreshingWebStatus = true;
    try {
      await monitor?.setPaused(true);
      await enrollment.refreshSystem();
      if (mounted) setState(_updateWebSettingsMessage);
    } catch (_) {
      // Preserve enrollment and last state on a transient status read failure.
    } finally {
      refreshingWebStatus = false;
      unawaited(_coordinateMonitor());
    }
  }

  void _monitorChanged() {
    final observed = monitor;
    if (observed == null || !mounted) return;
    final updated = observed.readers;
    final usable = updated.where((r) => r['isCie'] == true).toList();
    JsonResult? next;
    if (selected != null) {
      for (final card in usable) {
        if (card['name'] == selected!['name'] &&
            card['cardId'] == selected!['cardId']) {
          next = card;
        }
      }
    }
    if (next == null && usable.length == 1) next = usable.single;
    // Insertion/removal never navigates or clears the selected document.
    final changed =
        selected?['name'] != next?['name'] ||
        selected?['cardId'] != next?['cardId'] ||
        selected?['eventCounter'] != next?['eventCounter'];
    setState(() {
      readers = updated;
      cardsChecked = observed.checked;
      if (!changed) {
        selected = next;
        if (next?['occupied'] == true) pin.clear();
      }
    });
    if (changed) {
      unawaited(
        _changeCard(next).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  final flow = AppFlowController();
  final signFlow = SignFlowState();
  late final verifyFlow = VerificationController(
    service,
    canExtract: () => canExtract,
  );
  void _verificationChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_coordinateMonitor());
  }

  int get page => flow.destination.index;
  bool get busy => flow.busy || verifyFlow.running;
  set busy(bool value) => flow.busy = value;
  String get progress => flow.busy
      ? flow.progress
      : verifyFlow.exporting
      ? 'Estrazione del documento…'
      : verifyFlow.checking
      ? 'Verifica del documento e controllo della revoca…'
      : verifyFlow.running
      ? 'Chiusura del controllo precedente…'
      : '';
  set progress(String value) => flow.progress = value;
  String get input => signFlow.input;
  set input(String value) => signFlow.input = value;
  String get output => signFlow.output;
  set output(String value) => signFlow.output = value;
  String get format => signFlow.format;
  set format(String value) => signFlow.format = value;
  String get verifyPath => verifyFlow.path;
  JsonResult? get signature => signFlow.result;
  set signature(JsonResult? value) => signFlow.result = value;
  JsonResult? get verification => verifyFlow.result;
  JsonResult? get extraction => verifyFlow.extraction;
  bool ready = false, canSign = false;
  bool canChangePin = false, canUnblockPin = false;
  bool canPair = false, usePartialPin = false;
  List<String> pairedCards = [];
  bool pairingsReadable = false;
  bool canAppearance = false, canExtract = false, canCosign = false;
  late final PreferencesStore preferenceStore =
      widget.preferences ?? MemoryPreferencesStore();
  SignaturePreferences preferences = const SignaturePreferences();
  bool preferencesLoaded = false;
  PreparedPdfSignature? preparedPdf;
  SigningDocument? signingDocument;
  SigningStep signingStep = SigningStep.document;
  String? signingCard;
  bool? signingUnpaired;
  bool signingPdf = false, signingCosign = false, graphicSignature = true;
  bool migrateGlobalImage = false, fullPinFallback = false;
  int existingSignatures = 0;
  SigningStep get currentSigningStep =>
      signingUnpaired == null && pairedCards.isNotEmpty
      ? SigningStep.card
      : signingStep;
  JsonResult? get signingTarget {
    if (signingUnpaired != false) return selected;
    final matches = readers
        .where((r) => r['isCie'] == true && r['cardId'] == signingCard)
        .toList();
    if (matches.length == 1) return matches.single;
    if (selected?['cardId'] == signingCard &&
        matches.any((r) => r['name'] == selected?['name'])) {
      return selected;
    }
    return null;
  }

  bool get signingPartial =>
      signingUnpaired == false &&
      !fullPinFallback &&
      pairingsReadable &&
      pairedCards.contains(signingCard);
  String? _pairedName(String? id) {
    final name = unified ? enrollment.records[id]?.name : null;
    return name?.trim().isNotEmpty == true ? name : null;
  }

  String get signingCardLabel =>
      _pairedName(signingCard ?? selected?['cardId'] as String?) ?? 'Carta CIE';
  bool get signingCanBack =>
      !busy &&
      !modalInteraction &&
      currentSigningStep != SigningStep.result &&
      (currentSigningStep != SigningStep.document || pairedCards.isNotEmpty) &&
      currentSigningStep != SigningStep.card;
  void _signingBack() {
    if (!signingCanBack) return;
    setState(() {
      pin.clear();
      error = null;
      signingStep = switch (currentSigningStep) {
        SigningStep.pin =>
          format == 'pdf' && graphicSignature && canAppearance
              ? SigningStep.appearance
              : SigningStep.format,
        SigningStep.appearance => SigningStep.format,
        SigningStep.format => SigningStep.document,
        _ => SigningStep.card,
      };
      if (signingStep == SigningStep.card) signingUnpaired = null;
    });
  }

  Future<void> _chooseSigningCard(String? id) async {
    pin.clear();
    final changed = signingCard != id || signingUnpaired != (id == null);
    if (changed) await _removeAppearance();
    if (!mounted) return;
    setState(() {
      signingCard = id;
      signingUnpaired = id == null;
      fullPinFallback = false;
      signingStep = input.isEmpty ? SigningStep.document : SigningStep.format;
      graphicSignature = true;
      migrateGlobalImage = false;
    });
  }

  JsonResult? error;
  List<JsonResult> readers = [];
  JsonResult? selected;
  final pin = TextEditingController();
  bool testDocument = false;
  bool cardsChecked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    verifyFlow.addListener(_verificationChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    monitor?.dispose();
    verifyFlow.removeListener(_verificationChanged);
    verifyFlow.dispose();
    if (!busy) {
      unawaited(preparedPdf?.dispose() ?? Future.value());
      unawaited(signingDocument?.dispose() ?? Future.value());
    }
    pin.clear();
    pin.dispose();
    flow.dispose();
    super.dispose();
  }

  void _navigate(AppDestination destination) {
    if (modalInteraction || verifyFlow.exporting) return;
    if (!flow.navigate(destination)) return;
    if (destination != AppDestination.verify && verifyFlow.checking) {
      verifyFlow.cancel();
    }
    setState(() {
      pin.clear();
      error = null;
    });
  }

  void _goBack() {
    if (modalInteraction || verifyFlow.exporting) return;
    if (page == AppDestination.sign.index && signingCanBack) {
      _signingBack();
      return;
    }
  }

  Future<void> _changeCard(JsonResult? next) async {
    final changed =
        selected?['cardId'] != next?['cardId'] ||
        selected?['name'] != next?['name'];
    selected = next;
    pin.clear();
    usePartialPin = false;
    if (changed &&
        signingUnpaired != false &&
        signingStep != SigningStep.result) {
      final previous = preparedPdf;
      preparedPdf = null;
      signFlow.changeCard();
      await previous?.dispose();
    }
  }

  Future<void> _concludeSigning() async {
    if (busy) return;
    final previous = preparedPdf;
    final document = signingDocument;
    setState(() {
      pin.clear();
      preparedPdf = null;
      signingDocument = null;
      signingStep = SigningStep.document;
      graphicSignature = true;
      migrateGlobalImage = false;
      signFlow.conclude();
      testDocument = false;
      error = null;
    });
    await previous?.dispose();
    await document?.dispose();
  }

  void _concludeVerification() {
    if (flow.busy || verifyFlow.exporting) return;
    pin.clear();
    verifyFlow.cancel();
    setState(() => error = null);
  }

  Future<void> _chooseVerificationDocument() async {
    if (flow.busy || modalInteraction || verifyFlow.exporting) return;
    modalInteraction = true;
    unawaited(_coordinateMonitor());
    String? path;
    try {
      path =
          await (widget.verificationFilePicker?.call() ?? _pick(signed: true));
    } finally {
      modalInteraction = false;
      unawaited(_coordinateMonitor());
    }
    if (path != null && mounted) await _startVerification(path);
  }

  Future<void> _startVerification(String path) async {
    if (flow.busy || verifyFlow.exporting || !ready) return;
    pin.clear();
    setState(() => error = null);
    await verifyFlow.select(path);
  }

  Future<void> _operation(String label, Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      notificationRevision++;
      busy = true;
      progress = label;
      error = null;
    });
    await _coordinateMonitor();
    try {
      await action();
    } catch (_) {
      if (mounted) {
        error = {
          'ok': false,
          'code': 'operation_failed',
          'message': 'Operazione non completata',
        };
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = '';
        });
        unawaited(_coordinateMonitor());
      } else {
        await preparedPdf?.dispose();
        await signingDocument?.dispose();
      }
    }
  }

  Future<void> _load() => _operation('Caricamento del middleware…', () async {
    if (!settingsLoaded) {
      try {
        settings = await settingsStore.load();
        if (mounted) {
          AppLanguageScope.of(context)?.select(settings.languageCode);
          AppThemeScope.of(context)?.select(settings.themeCode);
        }
        network = SessionNetworkConfig(proxy: settings.proxy);
        service.setNetwork(network);
        diagnostics.level = settings.diagnostics;
      } catch (_) {
        settingsValid = false;
        service.blockNetworkConfiguration();
        error = {
          'ok': false,
          'code': 'network_configuration_required',
          'message': 'Impostazioni non leggibili. Le nuove verifiche e firme richiedono di salvare o ripristinare la configurazione in Impostazioni.',
        };
      }
      settingsLoaded = true;
    }
    if (!preferencesLoaded) {
      try {
        preferences = await preferenceStore.load();
        format = preferences.format;
      } catch (_) {
        error = {
          'ok': false,
          'message': 'Preferenze non leggibili: vengono usati i valori iniziali. Puoi ripristinarle dalla pagina Impostazioni.',
        };
      }
      preferencesLoaded = true;
    }
    final loaded = await service.load();
    capabilities = loaded;
    if (!mounted) return;
    ready = loaded['ok'] == true;
    canSign = ready && loaded['canSign'] == true;
    canPair = ready && loaded['canPair'] == true;
    unified = ready && loaded['enrollmentVersion'] == 2;
    canChangePin = ready && loaded['canChangePin'] == true;
    canUnblockPin = ready && loaded['canUnblockPin'] == true;
    canAppearance = ready && loaded['canSignPdfAppearance'] == true;
    canCosign = ready && loaded['canCosign'] == true;
    canExtract = ready && loaded['canExtract'] == true;
    if (!ready) {
      error = loaded;
      return;
    }
    if (canPair) await _refreshPairings();
    // Start after runtime load. Observation has its own PC/SC context, performs
    // only idle identification, and never blocks verification/startup navigation.
    if (loaded['canObserveCards'] == true && monitor == null) {
      monitor = CardMonitor(
        service,
        afterChange: () async {
          if (unified) {
            await enrollment.refreshSystem();
            if (mounted) _updateWebSettingsMessage();
          }
        },
      )..addListener(_monitorChanged);
    }
  });
  Future<void> _readCards() async {
    pin.clear();
    usePartialPin = false;
    final detected = await service.detect();
    if (!mounted) return;
    if (detected['ok'] != true) {
      cardsChecked = false;
      error = detected;
      readers = [];
      await _changeCard(null);
      return;
    }
    cardsChecked = true;
    readers = (detected['readers'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final usable = readers.where((r) => r['isCie'] == true).toList();
    await _changeCard(usable.isEmpty ? null : usable.first);
  }

  bool get selectedPaired =>
      pairingsReadable &&
      selected != null &&
      pairedCards.contains(selected!['cardId']);
  Future<void> _refreshPairings() async {
    if (unified) {
      await enrollment.refresh();
      if (!mounted) return;
      pairingsReadable = enrollment.readable;
      pairedCards = enrollment.records.values
          .where((r) => r.readyForSigning)
          .map((r) => r.id)
          .toList();
      pin.clear();
      usePartialPin = false;
      return;
    }
    final result = await service.pairings();
    if (!mounted) return;
    pairingsReadable = result['ok'] == true;
    pairedCards = pairingsReadable
        ? List<String>.from(result['cards'] as List? ?? [])
        : [];
    usePartialPin = false;
    pin.clear();
    if (!pairingsReadable) error = result;
  }

  Future<void> _pairCard(JsonResult card) async {
    if (unified) {
      await _enrollCard(card);
      return;
    }
    String? secret = await showDialog<String>(
      context: context,
      builder: (context) => PairCardDialog(card: card['cardId'] as String),
    );
    if (secret == null || !mounted) {
      return;
    }
    final value = secret;
    secret = null;
    await _operation(
      'Abbinamento: una sola autenticazione con la CIE…',
      () async {
        final result = await service.pair(
          card['name'] as String,
          card['cardId'] as String,
          value,
        );
        if (!mounted) return;
        await _refreshPairings();
        if (result['ok'] != true) error = result;
      },
    );
  }

  Future<void> _enrollCard(JsonResult card) async {
    if (busy || modalInteraction) return;
    if (card['occupied'] == true) {
      setState(
        () => homeMessage =
            'Carta in uso: attendi che l’altra applicazione abbia terminato.',
      );
      return;
    }
    modalInteraction = true;
    await _coordinateMonitor();
    String? secret;
    try {
      await enrollment.refresh();
      if (!mounted) return;
      if (!enrollment.readable) {
        setState(() => homeMessage = enrollment.message);
        return;
      }
      final system = await widget.webStatusReader();
      final native = await service.webStatus();
      if (!mounted) return;
      // Elevation finishes before the PIN dialog. No PIN or user credential is
      // retained or passed to the elevated process, including on recovery.
      if (!await _ensureWindowsWebComponent(
        card['name'] as String,
        signingOnly: true,
      )) {
        return;
      }
      final activated = await service.webStatus();
      final activatedSystem = await widget.webStatusReader();
      if (!mounted) return;
      secret = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PairCardDialog(
          card: card['cardId'] as String,
          unified: true,
          componentAvailable:
              (activatedSystem['available'] ??
                  activated['available'] ??
                  system['available'] ??
                  native['available']) ==
              true,
        ),
      );
      if (secret == null || !mounted) return;
      await _operation('Abbinamento e preparazione accesso ai siti…', () async {
        final result = await enrollment.enroll(
          card['name'] as String,
          card['cardId'] as String,
          secret!,
        );
        secret = null;
        await _refreshPairings();
        if (!mounted) return;
        homeMessage =
            enrollment.message ??
            (result['ok'] == true
                ? 'CIE abbinata. Puoi firmare documenti. Lo stato dell’accesso ai siti è disponibile nella Home.'
                : 'Abbinamento non completato. Nessun tentativo automatico.');
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => homeMessage =
              'Abbinamento non completato. Nessun tentativo automatico.',
        );
      }
    } finally {
      secret = null;
      modalInteraction = false;
      unawaited(_coordinateMonitor());
    }
  }

  Future<void> _activateWebComponent({bool update = false}) async {
    if (busy || modalInteraction) return;
    modalInteraction = true;
    await _coordinateMonitor();
    bool? confirmed;
    try {
      if (!mounted) return;
      confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            tr(
              context,
              update ? 'Aggiorna accesso ai siti' : 'Attiva accesso ai siti',
            ),
          ),
          content: Text(
            tr(
              context,
              update
                  ? 'Verrà registrato il componente incluso in questa versione di Firma con CIE. L’abbinamento e il certificato pubblico sono conservati; non viene richiesto il PIN. Le altre estensioni non vengono modificate.'
                  : 'Verrà riattivato soltanto il componente Firma con CIE di questa applicazione. L’abbinamento è conservato e non viene richiesto il PIN. Le altre estensioni non vengono modificate.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'Annulla')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, update ? 'Aggiorna' : 'Attiva')),
            ),
          ],
        ),
      );
    } finally {
      modalInteraction = false;
      if (confirmed != true) unawaited(_coordinateMonitor());
    }
    if (confirmed != true || !mounted) return;
    await _operation('Attivazione accesso ai siti…', () async {
      JsonResult result;
      try {
        result = await widget.webComponentActivator();
      } catch (_) {
        result = {'ok': false};
      }
      await enrollment.refreshSystem();
      if (result['ok'] == true && enrollment.system['available'] == true) {
        homeMessage =
            enrollment.message ??
            (update
                ? 'Componente aggiornato. L’abbinamento è conservato. Prima del prossimo accesso, rimuovi e riappoggia la CIE e riapri il browser per terminare la sessione precedente.'
                : enrollment.records.isEmpty
                ? 'Componente Firma con CIE attivato.'
                : enrollment.records.values.every(
                    (record) => record.webProvisioned,
                  )
                ? 'Accesso ai siti attivato. Apri il sito nel browser. Non occorre ripetere l’abbinamento.'
                : 'Componente Firma con CIE attivato. Premi Completa accesso ai siti per terminare senza reinserire il PIN.');
      } else {
        homeMessage = 'Attivazione non completata. L’abbinamento è conservato e puoi continuare a firmare. Puoi riprovare su tua iniziativa; non occorre reinserire il PIN.';
      }
    });
  }

  Future<void> _openWebSettings() async {
    if (busy || modalInteraction) return;
    bool opened;
    try {
      opened = await widget.webSettingsOpener();
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    waitingForWebSettings = opened;
    setState(
      () => homeMessage = opened
          ? 'In Impostazioni di Sistema apri Generali → Elementi login ed estensioni e abilita il componente Firma con CIE per le smart card. Torna poi nell’app: non occorre ripetere il PIN.'
          : 'Non è stato possibile aprire le Impostazioni di Sistema. Aprile dal menu Apple e cerca le estensioni per smart card. L’abbinamento è conservato; non occorre ripetere il PIN.',
    );
  }

  Future<void> _completeEnrollment(EnrollmentRecord record) async {
    if (busy || modalInteraction) return;
    if (widget.windowsWebComponentChecker != null &&
        record.hasPublicData &&
        record.readyForSigning) {
      final matching = readers
          .where((r) => r['isCie'] == true && r['cardId'] == record.id)
          .toList();
      if (matching.length != 1) {
        await _showWebCompletionStatus(
          'Appoggia questa CIE al lettore per attivare il componente Windows. Non occorre ripetere il PIN.',
        );
        return;
      }
      modalInteraction = true;
      await _coordinateMonitor();
      try {
        if (!await _ensureWindowsWebComponent(
          matching.single['name'] as String,
          signingOnly: false,
        )) {
          return;
        }
      } finally {
        modalInteraction = false;
        unawaited(_coordinateMonitor());
      }
    }
    if (record.hasPublicData &&
        record.readyForSigning &&
        record.webProvisioned &&
        !record.componentAvailable &&
        widget.windowsWebComponentChecker == null) {
      await _showWebCompletionStatus(
        EnrollmentRecord.componentActivationMessage,
      );
      return;
    }
    if (!record.hasPublicData || !record.readyForSigning) {
      final matching = readers
          .where((r) => r['isCie'] == true && r['cardId'] == record.id)
          .toList();
      if (matching.length == 1) {
        await _enrollCard(matching.single);
      } else {
        setState(
          () => homeMessage = 'Appoggia questa CIE al lettore per completare l’abbinamento con il PIN completo, una sola volta.',
        );
      }
      return;
    }
    await _operation(
      'Completamento della configurazione, senza PIN…',
      () async {
        await enrollment.complete(record.id);
        await _refreshPairings();
        homeMessage =
            enrollment.message ??
            'Configurazione aggiornata. Controlla lo stato della CIE.';
      },
    );
  }

  Future<bool> _ensureWindowsWebComponent(
    String reader, {
    required bool signingOnly,
  }) async {
    final checker = widget.windowsWebComponentChecker;
    if (checker == null) return true;
    JsonResult result = {'ok': false};
    await _operation(
      'Verifica del componente per l’accesso ai siti…',
      () async {
        result = await checker(reader);
      },
    );
    if (!mounted) return false;
    if (result['ok'] == true) return true;
    final message =
        result['message'] as String? ??
        'Il componente per l’accesso ai siti non è disponibile. Esegui il pacchetto di installazione di Firma con CIE. Gli abbinamenti e le impostazioni saranno conservati.';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr(context, 'Accesso ai siti con CIE')),
            content: Text(tr(context, message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr(context, signingOnly ? 'Annulla' : 'Chiudi')),
              ),
              if (signingOnly)
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr(context, 'Continua solo per firmare')),
                ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showWebCompletionStatus(String message) async {
    modalInteraction = true;
    await _coordinateMonitor();
    if (!mounted) return;
    try {
      await showAppNotification(
        context,
        message: message,
        title: 'Accesso ai siti con CIE',
        buttonLabel: 'Chiudi',
      );
    } finally {
      modalInteraction = false;
      unawaited(_coordinateMonitor());
    }
  }

  Future<void> _unpair(String card) async {
    if (busy || modalInteraction) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          unified
              ? (card.isEmpty
                    ? 'Rimuovi tutte le CIE da questo computer'
                    : 'Rimuovi CIE da questo computer')
              : card.isEmpty
              ? tr(context, "Rimuovi tutti gli abbinamenti")
              : tr(context, "Disabbina CIE"),
        ),
        content: Text(
          unified
              ? tr(
                  context,
                  "Verranno rimossi gli abbinamenti e la configurazione per l’accesso ai siti gestiti solo da questa applicazione. La carta, il PIN e gli altri componenti non saranno modificati.",
                )
              : card.isEmpty
              ? tr(
                  context,
                  "Rimuovere tutte le CIE abbinate esclusivamente a questa applicazione?",
                )
              : tr(
                  context,
                  "Rimuovere l’abbinamento di {p0} da questa applicazione? La carta e gli abbinamenti dell’app originale non vengono modificati.",
                  [_pairedName(card) ?? tr(context, 'questa CIE')],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, "Annulla")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, "Rimuovi")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _operation('Rimozione dell’abbinamento locale…', () async {
      if (unified) {
        homeMessage = null;
        final ids = card.isEmpty ? enrollment.records.keys.toList() : [card];
        for (final id in ids) {
          final r = await enrollment.remove(id);
          if (r['ok'] != true) {
            homeMessage = enrollment.message;
            break;
          }
          if (preferenceStore is CardImagePreferences) {
            await (preferenceStore as CardImagePreferences).removeCardImage(id);
          }
        }
        await _refreshPairings();
        homeMessage ??= card.isEmpty
            ? 'Rimozione delle CIE completata.'
            : 'CIE rimossa da questo computer.';
        return;
      }
      if (preferenceStore is CardImagePreferences) {
        for (final id in card.isEmpty ? pairedCards : [card]) {
          await (preferenceStore as CardImagePreferences).removeCardImage(id);
        }
      }
      final result = await service.unpair(card);
      if (!mounted) return;
      await _refreshPairings();
      if (result['ok'] != true) error = result;
    });
  }

  Future<void> _detect() =>
      _operation('Lettura dei dati pubblici della carta…', _readCards);
  Future<String?> _pick({bool signed = false}) => openDocumentDialog(
    signed: signed,
    languageCode: CieLocalizations.of(context).locale.languageCode,
  );

  Future<void> _chooseInput() async {
    if (busy || modalInteraction) return;
    modalInteraction = true;
    await _coordinateMonitor();
    String? path;
    try {
      path = await _pick();
    } finally {
      modalInteraction = false;
      unawaited(_coordinateMonitor());
    }
    if (path != null && mounted) await _acceptInput(path);
  }

  Future<void> _acceptInput(String path, {bool example = false}) =>
      _operation('Caricamento documento…', () async {
        pin.clear();
        SigningDocument? next;
        try {
          next = await SigningDocument.capture(path);
          final info = await service.signingInfo(next.path);
          if (info['ok'] != true) {
            error = info;
            return;
          }
          if (path.toLowerCase().endsWith('.p7m') &&
              (info['cosignSupported'] != true || !canCosign)) {
            error = {
              'ok': false,
              'message': 'Il P7M non è idoneo ad aggiungere una firma: le firme esistenti devono essere integre e il contenuto deve essere supportato.',
            };
            return;
          }
          if (!mounted) return;
          final old = signingDocument, preview = preparedPdf;
          signingDocument = next;
          next = null;
          preparedPdf = null;
          signingPdf = info['pdfSupported'] == true;
          signingCosign = info['cosignSupported'] == true && canCosign;
          existingSignatures = info['signatureCount'] as int? ?? 0;
          signFlow.selectDocument(
            path,
            signingCosign
                ? 'cosign'
                : signingPdf
                ? preferences.format
                : 'p7m',
            '',
          );
          signingUnpaired ??= true;
          signingStep = SigningStep.format;
          graphicSignature = true;
          migrateGlobalImage = false;
          testDocument = example;
          await old?.dispose();
          await preview?.dispose();
        } on FormatException catch (e) {
          error = {'ok': false, 'message': e.message};
        } finally {
          await next?.dispose();
        }
      });
  Future<void> _drop(List<String> paths, {required bool verify}) async {
    if ((verify ? flow.busy || verifyFlow.exporting : busy)) return;
    if (paths.length != 1) {
      setState(
        () => error = {
          'ok': false,
          'message': 'Trascinare un solo documento alla volta.',
        },
      );
      return;
    }
    if (!verify) {
      await _acceptInput(paths.single);
      return;
    }
    await _startVerification(paths.single);
  }

  Future<void> _configureAppearance() =>
      _operation('Preparazione anteprima PDF…', () async {
        pin.clear();
        try {
          final defaultImage = migrateGlobalImage
              ? preferences.imagePath
              : signingUnpaired == false &&
                    preferenceStore is CardImagePreferences
              ? await (preferenceStore as CardImagePreferences).cardImage(
                  signingCard!,
                )
              : null;
          if (!mounted) return;
          final next = await configurePdfAppearance(
            context,
            service,
            signingDocument!.path,
            defaultImagePath: defaultImage,
            cardholderName: _pairedName(
              signingCard ?? selected?['cardId'] as String?,
            ),
            initialAppearance: preparedPdf?.appearance,
          );
          if (next == null) return;
          if (!mounted) {
            await next.dispose();
            return;
          }
          // A per-CIE custom image is owned by its store; the global image is
          // copied only on explicit migration and is never removed here.
          try {
            if (signingUnpaired == false &&
                preferenceStore is CardImagePreferences) {
              final images = preferenceStore as CardImagePreferences;
              if (next.appearance.imagePath == cardholderNameAppearance) {
                await images.removeCardImage(signingCard!);
              } else {
                await images.saveCardImage(
                  signingCard!,
                  next.appearance.imagePath,
                );
              }
            }
          } catch (_) {
            await next.dispose();
            rethrow;
          }
          final previous = preparedPdf;
          preparedPdf = next;
          await previous?.dispose();
          signature = null;
        } on FormatException catch (e) {
          error = {'ok': false, 'message': e.message};
        }
      });
  Future<void> _removeAppearance() async {
    if (busy) return;
    pin.clear();
    final previous = preparedPdf;
    setState(() {
      preparedPdf = null;
      signature = null;
    });
    await previous?.dispose();
  }

  Future<void> _extract() => verifyFlow.extract((request) async {
    if (widget.verificationSavePicker != null) {
      return widget.verificationSavePicker!(request);
    }
    final location = await getSaveLocation(
      suggestedName: request.suggestedName,
    );
    return location?.path;
  });

  Future<void> _useExample() async {
    final bytes = await rootBundle.load('assets/prova.pdf');
    final directory = await Directory.systemTemp.createTemp(
      'cie-flutter-prototype-',
    );
    final document = File('${directory.path}/prova.pdf');
    await document.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    if (!mounted) return;
    signingUnpaired ??= true;
    _navigate(AppDestination.sign);
    try {
      await _acceptInput(document.path, example: true);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _recordTest(JsonResult result, String type) async {
    // Only the bundled synthetic document can generate this diagnostic record.
    // No PIN, card identifiers, names, file paths or document content are saved.
    if (!testDocument || service is! FfiCieService) return;
    final root = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA']
        : Platform.isMacOS
        ? '${Platform.environment['HOME']}/Library/Application Support'
        : Platform.environment['XDG_STATE_HOME'] ??
              '${Platform.environment['HOME']}/.local/state';
    if (root == null) return;
    try {
      final folder = Directory('$root/CIE Flutter Prototype');
      await folder.create(recursive: true);
      final report = File('${folder.path}/last-signature-$type.json');
      final verified = result['verification'] as Map?;
      final signers = (verified?['signers'] as List? ?? []).cast<Map>();
      await report.writeAsString(
        jsonEncode({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'format': type,
          'signed': result['ok'] == true,
          'errorCode': result['code'],
          'nativeCode': result['nativeCode'],
          'signatureCount': verified?['signatureCount'],
          'signatures': signers
              .map(
                (s) => {
                  'signatureValid': s['signatureValid'],
                  'certificateWithinValidity': s['certificateWithinValidity'],
                  'revocationStatus': s['revocationStatus'],
                  'trustChainStatus': s['trustChainStatus'],
                  'trustChainValidated': s['trustChainValidated'],
                  'chainRevocationStatus': s['chainRevocationStatus'],
                },
              )
              .toList(),
        }),
      );
    } catch (_) {
      /* Diagnostics must not change the outcome of a signature. */
    }
  }

  Future<String?> _pickSignedFile(SignedFileRequest request) async {
    if (widget.signedFilePicker != null) {
      return widget.signedFilePicker!(request);
    }
    final location = await getSaveLocation(
      suggestedName: Platform.isMacOS && request.extension == 'p7m'
          ? request.suggestedName
          : '${request.suggestedName}.${request.extension}',
      acceptedTypeGroups: [
        XTypeGroup(
          label: request.extension == 'pdf' ? 'PDF firmato' : 'CAdES',
          extensions: [request.extension],
        ),
      ],
    );
    return location?.path;
  }

  Future<void> _sign() async {
    if (busy || currentSigningStep != SigningStep.pin) return;
    if (format == 'pdf' &&
        graphicSignature &&
        canAppearance &&
        preparedPdf == null) {
      pin.clear();
      setState(() {
        signingStep = SigningStep.appearance;
        error = {
          'ok': false,
          'message': 'Prepara nuovamente la firma grafica per la CIE scelta.',
        };
      });
      return;
    }
    final target = signingTarget;
    final partial = signingPartial;
    if (target == null || target['occupied'] == true) {
      pin.clear();
      setState(
        () => error = {
          'ok': false,
          'message': target == null
              ? 'Appoggia la CIE scelta al lettore prima di firmare.'
              : 'Carta in uso: attendi che l’altra applicazione abbia terminato.',
        },
      );
      return;
    }
    if (!(partial ? RegExp(r'^\d{4}$') : RegExp(r'^\d{8}$')).hasMatch(
          pin.text,
        ) ||
        signingDocument == null) {
      pin.clear();
      setState(
        () => error = {
          'ok': false,
          'message':
              'Inserisci ${partial ? 'le ultime quattro' : 'tutte le otto'} cifre del PIN.',
        },
      );
      return;
    }
    // Freeze every operation parameter before the save dialog. Navigation,
    // observation and draft editing are disabled until the operation ends.
    var secret = pin.text;
    pin.clear();
    final reader = target['name'] as String, card = target['cardId'] as String;
    final source = preparedPdf?.pdfPath ?? signingDocument!.path;
    final appearance = format == 'pdf' && graphicSignature && canAppearance
        ? preparedPdf?.appearance
        : null;
    final kind = format;
    final name = input.replaceAll('\\', '/').split('/').last;
    final base = kind == 'cosign' && name.toLowerCase().endsWith('.p7m')
        ? name.substring(0, name.length - 4)
        : name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    await _operation('Scegli dove salvare il file firmato…', () async {
      try {
        final destination = await _pickSignedFile(
          SignedFileRequest(
            '$base-${kind == 'cosign' ? 'cofirmato' : 'firmato'}',
            kind == 'pdf' ? 'pdf' : 'p7m',
          ),
        );
        if (destination == null || !mounted) return;
        // NSSavePanel / IFileSaveDialog has already obtained replacement
        // confirmation. Never accept a directory or a symbolic link.
        final destinationType = await FileSystemEntity.type(
          destination,
          followLinks: false,
        );
        if (destinationType != FileSystemEntityType.notFound &&
            destinationType != FileSystemEntityType.file) {
          error = {
            'ok': false,
            'message':
                'Scegli un file normale, non una cartella o un collegamento.',
          };
          return;
        }
        final extension = kind == 'pdf' ? '.pdf' : '.p7m';
        if (!destination.toLowerCase().endsWith(extension)) {
          error = {
            'ok': false,
            'message': 'Salva il documento con estensione $extension.',
          };
          return;
        }
        setState(
          () => progress = 'Firma in corso: mantieni la CIE sul lettore…',
        );
        final result = await service.sign(
          reader: reader,
          card: card,
          input: source,
          output: destination,
          format: kind,
          pin: secret,
          replaceExisting: destinationType == FileSystemEntityType.file,
          appearance: appearance,
        );
        secret = '';
        await _recordTest(result, kind);
        if (mounted) {
          signature = result;
          if (result['ok'] == true) {
            output = destination;
            signingStep = SigningStep.result;
          } else {
            error = result;
          }
        }
      } finally {
        secret = '';
      }
    });
  }

  Widget _notification() {
    final shownHome = homeMessage;
    final shownError = error;
    return AppNotification(
      key: const ValueKey('application-notification'),
      message:
          shownHome ??
          shownError?['message'] as String? ??
          (shownError == null ? null : 'Operazione non completata'),
      event: (shownHome ?? shownError, notificationRevision),
      title: shownHome == null && shownError != null
          ? 'Operazione non completata'
          : 'Firma con CIE',
      error: shownHome == null && shownError != null,
      enabled: !busy && !modalInteraction,
      details: shownError == null
          ? null
          : [
              if (shownError['code'] != null) '${shownError['code']}',
              if (shownError['nativeCode'] != null)
                tr(context, 'Codice nativo: {p0}', [shownError['nativeCode']]),
            ].join('\n'),
      onDismissed: shownHome == null
          ? null
          : () {
              if (mounted && homeMessage == shownHome) {
                setState(() {
                  homeMessage = null;
                  if (identical(error, shownError)) error = null;
                });
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _goBack();
    },
    child: AppNotificationScope(
      onVisibilityChanged: (visible) {
        if (!mounted) return;
        modalInteraction = visible;
        unawaited(_coordinateMonitor());
      },
      child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              scrollable: true,
              extended: MediaQuery.sizeOf(context).width > 930,
              selectedIndex: page,
              onDestinationSelected: flow.busy || verifyFlow.exporting
                  ? null
                  : (value) => _navigate(AppDestination.values[value]),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CieCardIllustration(width: 64),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.contactless_outlined),
                  label: Text(tr(context, "Home")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.draw_outlined),
                  label: Text(tr(context, "Firma Elettronica")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  label: Text(tr(context, "Verifica Firma")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.password_outlined),
                  label: Text(tr(context, "Cambia PIN")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.lock_open_outlined),
                  label: Text(tr(context, "Sblocca Carta")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: Text(tr(context, "Guida")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.support_agent_outlined),
                  label: Text(tr(context, "Assistenza")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.info_outline),
                  label: Text(tr(context, "Informazioni")),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: Text(tr(context, "Impostazioni")),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ApplicationPageHeader(
                    destination: AppDestination.values[page],
                    showBack: page == AppDestination.sign.index,
                    onBack: page == AppDestination.sign.index && signingCanBack
                        ? _goBack
                        : null,
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(tr(context, progress)),
                    ),
                  Expanded(
                    child: DesktopPageBody(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _notification(),
                          if (page == 0) ..._cardPage(context),
                          if (page == 1) ..._signPage(context),
                          if (page == 2) ..._verifyPage(context),
                          if (page == 5) const GuideView(),
                          if (page == 6) const AssistanceView(),
                          if (page == AppDestination.information.index)
                            InformationView(ready: ready),
                          if (page == AppDestination.settings.index)
                            SettingsView(
                              value: settings,
                              network: network,
                              onSave: _saveSettings,
                              onProbe: service.probeNetwork,
                              diagnostics: diagnostics,
                              capabilities: capabilities,
                              webDiagnostics: unified
                                  ? enrollment.records.values
                                        .map((r) => r.diagnosticFlags)
                                        .toList()
                                  : null,
                              enrollmentReadable: unified
                                  ? enrollment.readable
                                  : null,
                              diagnosticDetails: unified
                                  ? EnrollmentDiagnosticsView(
                                      records: enrollment.records.values
                                          .toList(),
                                      readable: enrollment.readable,
                                      busy: busy,
                                      onRefresh: () => _operation(
                                        'Aggiornamento stato delle CIE…',
                                        _refreshPairings,
                                      ),
                                    )
                                  : null,
                              onBusy: _settingsBusy,
                              configurationValid: settingsValid,
                              interactionBusy: busy,
                              preferences: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      'language-${settings.languageCode}',
                                    ),
                                    initialValue: settings.languageCode,
                                    decoration: InputDecoration(
                                      labelText: tr(
                                        context,
                                        "Lingua dell’applicazione",
                                      ),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'system',
                                        child: Text(
                                          tr(context, 'Segui il sistema'),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'it',
                                        child: Text(tr(context, "Italiano")),
                                      ),
                                      DropdownMenuItem(
                                        value: 'en',
                                        child: Text(tr(context, "English")),
                                      ),
                                    ],
                                    onChanged: busy || appearanceSaving
                                        ? null
                                        : (code) {
                                            if (code != null) {
                                              _changeAppearance(
                                                languageCode: code,
                                              );
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      'theme-${settings.themeCode}',
                                    ),
                                    initialValue: settings.themeCode,
                                    decoration: InputDecoration(
                                      labelText: tr(
                                        context,
                                        'Tema dell’applicazione',
                                      ),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'system',
                                        child: Text(
                                          tr(context, 'Segui il sistema'),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'light',
                                        child: Text(tr(context, 'Chiaro')),
                                      ),
                                      DropdownMenuItem(
                                        value: 'dark',
                                        child: Text(tr(context, 'Scuro')),
                                      ),
                                    ],
                                    onChanged: busy || appearanceSaving
                                        ? null
                                        : (code) {
                                            if (code != null) {
                                              _changeAppearance(
                                                themeCode: code,
                                              );
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 24),
                                  PreferencesView(
                                    store: preferenceStore,
                                    value: preferences,
                                    onChanged: (value) =>
                                        setState(() => preferences = value),
                                    onBusy: (value) {
                                      if (mounted) {
                                        setState(() {
                                          busy = value;
                                          progress = value
                                              ? 'Salvataggio preferenze…'
                                              : '';
                                        });
                                        unawaited(_coordinateMonitor());
                                      }
                                    },
                                  ),
                                  if (Platform.isLinux) ...[
                                    const SizedBox(height: 24),
                                    FirefoxSetupCard(
                                      busy: busy,
                                      service: widget.firefoxSetupService,
                                      onBusy: _browserSetupBusy,
                                    ),
                                    const SizedBox(height: 16),
                                    ChromeSetupCard(
                                      busy: busy,
                                      service: widget.chromeSetupService,
                                      onBusy: _browserSetupBusy,
                                    ),
                                  ],
                                ],
                              ),
                              advanced: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ExpansionTile(
                                    title: Text(
                                      tr(context, "Strumenti di collaudo"),
                                    ),
                                    children: [
                                      TextButton.icon(
                                        onPressed: busy ? null : _useExample,
                                        icon: const Icon(
                                          Icons.science_outlined,
                                        ),
                                        label: Text(
                                          tr(context, "Usa documento di prova"),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (unified && selected != null)
                                    ExpansionTile(
                                      title: Text(
                                        tr(
                                          context,
                                          "Prove avanzate accesso ai siti",
                                        ),
                                      ),
                                      children: [
                                        WebAccessCard(
                                          linuxFirefox: Platform.isLinux,
                                          key: ValueKey(
                                            'advanced-web-${selected!['cardId']}',
                                          ),
                                          service: service,
                                          reader: selected!['name'] as String,
                                          card: selected!['cardId'] as String,
                                          enabled:
                                              capabilities?['canConfigureWeb'] ==
                                              true,
                                          busy: busy,
                                          publisher: widget.webPublisher,
                                          onBusy: (value) async {
                                            if (mounted) {
                                              setState(() {
                                                busy = value;
                                                progress = value
                                                    ? 'Prova componente di sistema…'
                                                    : '';
                                              });
                                              await _coordinateMonitor();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          if (page == 3 || page == 4)
                            PinManagementPage(
                              key: ValueKey(page),
                              service: service,
                              unblock: page == 4,
                              busy: busy,
                              available: page == 4
                                  ? canUnblockPin
                                  : canChangePin,
                              selected: selected == null
                                  ? null
                                  : {
                                      ...selected!,
                                      'fullName': _pairedName(
                                        selected!['cardId'] as String?,
                                      ),
                                    },
                              onRun: _operation,
                              onDetect: _detect,
                              onPairingsChanged: _refreshPairings,
                              automaticDetection: unified,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  WebComponentSetupNotice? get _webComponentNotice =>
      WebComponentSetupNotice.fromStatus(enrollment.system);

  List<Widget> _webComponentSetupCards(BuildContext context) {
    final notice = _webComponentNotice;
    if (notice == null) return [];
    return [
      Card(
        key: const ValueKey('web-component-setup-home'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'Accesso ai siti con CIE'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(tr(context, notice.message)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy || modalInteraction
                    ? null
                    : () => switch (notice.action) {
                        WebComponentAction.activate => _activateWebComponent(
                          update: notice.update,
                        ),
                        WebComponentAction.systemSettings => _openWebSettings(),
                        WebComponentAction.appUpdate ||
                        WebComponentAction.installer =>
                          _showWebCompletionStatus(notice.message),
                      },
                icon: const Icon(Icons.settings_outlined),
                label: Text(tr(context, notice.label)),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _cardPage(BuildContext context) => unified
      ? _unifiedHome(context)
      : [
          ..._webComponentSetupCards(context),
          if (Platform.isLinux && widget.firefoxSetupService != null)
            FirefoxSetupHomeCard(
              service: widget.firefoxSetupService!,
              busy: busy,
              onBusy: _browserSetupBusy,
            ),
          if (Platform.isLinux && widget.chromeSetupService != null)
            ChromeSetupHomeCard(
              service: widget.chromeSetupService!,
              busy: busy,
              onBusy: _browserSetupBusy,
            ),
          _heading(
            context,
            pairedCards.isEmpty ? 'Abbina la tua CIE' : 'Le tue CIE',
            'Collega il lettore e appoggia la CIE. Il rilevamento non richiede il PIN.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy || !ready ? null : _detect,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, "Rileva carta")),
              ),
              if (!ready)
                OutlinedButton(
                  onPressed: busy ? null : _load,
                  child: Text(tr(context, "Riprova caricamento")),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (readers.isEmpty && ready && !busy)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  cardsChecked
                      ? tr(context, "Nessun lettore collegato.")
                      : tr(
                          context,
                          "Premi «Rileva carta» per leggere i lettori e la CIE. La verifica dei documenti non richiede la carta.",
                        ),
                ),
              ),
            ),
          for (final reader in readers)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reader['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reader['isCie'] == true
                          ? tr(context, "CIE presente nel lettore")
                          : reader['present'] == true
                          ? tr(
                              context,
                              "Carta presente; identificazione CIE non disponibile o non riuscita",
                            )
                          : tr(context, "Nessuna carta presente"),
                    ),
                    if (reader['isCie'] == true) ...[
                      Text(
                        _pairedName(reader['cardId'] as String?) ??
                            tr(context, "Carta CIE"),
                      ),
                      if (canPair)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => _pairCard(
                                    Map<String, dynamic>.from(reader),
                                  ),
                            child: Text(
                              pairedCards.contains(reader['cardId'])
                                  ? tr(
                                      context,
                                      "Ripeti abbinamento con PIN completo",
                                    )
                                  : tr(context, "Abbina CIE"),
                            ),
                          ),
                        ),
                      WebAccessCard(
                        linuxFirefox: Platform.isLinux,
                        key: ValueKey(
                          'web-${reader['name']}-${reader['cardId']}',
                        ),
                        service: service,
                        reader: reader['name'] as String,
                        card: reader['cardId'] as String,
                        enabled: capabilities?['canConfigureWeb'] == true,
                        busy: busy,
                        onBusy: (value) {
                          if (mounted) {
                            setState(() {
                              busy = value;
                              progress = value
                                  ? 'Configurazione accesso ai siti…'
                                  : '';
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            tr(
              context,
              "Gli abbinamenti appartengono solo a questa applicazione e a questo utente. Il PIN completo e le ultime quattro cifre non sono salvati. La configurazione per l’accesso ai siti è separata e richiede l’attivazione del componente di sistema.",
            ),
          ),
          if (canPair) ...[
            const SizedBox(height: 18),
            Text(
              tr(context, "CIE abbinate"),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => _operation(
                      'Lettura archivio protetto…',
                      _refreshPairings,
                    ),
              child: Text(tr(context, "Aggiorna abbinamenti")),
            ),
            if (pairingsReadable && pairedCards.isEmpty)
              Text(tr(context, "Nessuna CIE abbinata a questa applicazione.")),
            if (!pairingsReadable)
              Text(
                tr(
                  context,
                  "Archivio protetto non leggibile. Il PIN parziale non è disponibile.",
                ),
              ),
            for (final id in pairedCards)
              ListTile(
                title: Text(_pairedName(id) ?? tr(context, "Carta abbinata")),
                trailing: TextButton(
                  onPressed: busy ? null : () => _unpair(id),
                  child: Text(tr(context, "Disabbina")),
                ),
              ),
            if (pairedCards.isNotEmpty)
              TextButton(
                onPressed: busy ? null : () => _unpair(''),
                child: Text(tr(context, "Rimuovi tutti gli abbinamenti")),
              ),
          ],
        ];
  bool _readerMatchesPairedCard(JsonResult reader, String id) {
    if (reader['present'] != true || reader['isCie'] != true) return false;
    // Idle discovery exposes the public service identifier. It already binds
    // each saved printed card number to that exact CIE; do not read a protected
    // certificate or request a PIN merely to update the card thumbnails.
    if (reader['cardId'] == id) return true;
    final number = (reader['cardNumber'] as String? ?? '').trim().toUpperCase();
    return number.isNotEmpty &&
        number == enrollment.records[id]?.cardNumber.trim().toUpperCase();
  }

  bool _pairedCardPresent(String id) =>
      cardsChecked &&
      monitor?.code == null &&
      readers.any((reader) => _readerMatchesPairedCard(reader, id));

  bool _homeCanPair(JsonResult reader) =>
      cardsChecked &&
      monitor?.code == null &&
      reader['present'] == true &&
      reader['isCie'] == true &&
      reader['occupied'] != true &&
      reader['cardId'] is String &&
      (reader['cardId'] as String).isNotEmpty &&
      !enrollment.records.values.any(
        (record) => _readerMatchesPairedCard(reader, record.id),
      );

  Widget _homePairButton(
    BuildContext context,
    JsonResult? card, {
    bool multiple = false,
  }) {
    final another = enrollment.records.isNotEmpty;
    final caption = tr(context, another ? 'Abbina un’altra CIE' : 'Abbina CIE');
    return FilledButton.icon(
      key: multiple
          ? ValueKey('pair-card-${card!['cardId']}')
          : ValueKey(another ? 'add-another-card' : 'pair-card'),
      onPressed:
          !busy &&
              !modalInteraction &&
              ready &&
              enrollment.readable &&
              card != null &&
              _homeCanPair(card)
          ? () => _pairCard(card)
          : null,
      icon: const Icon(Icons.add_card),
      label: Text(
        multiple
            ? tr(context, '{p0} · {p1}', [caption, card!['name']])
            : caption,
      ),
    );
  }

  List<Widget> _unifiedHome(BuildContext context) {
    final candidates = readers.where(_homeCanPair).toList();
    return [
      ..._webComponentSetupCards(context),
      if (Platform.isLinux && widget.firefoxSetupService != null)
        FirefoxSetupHomeCard(
          service: widget.firefoxSetupService!,
          busy: busy,
          onBusy: _browserSetupBusy,
        ),
      if (Platform.isLinux && widget.chromeSetupService != null)
        ChromeSetupHomeCard(
          service: widget.chromeSetupService!,
          busy: busy,
          onBusy: _browserSetupBusy,
        ),
      _heading(
        context,
        enrollment.records.isEmpty ? 'Abbina la tua CIE' : 'Le tue CIE',
        'Collega il lettore e appoggia la CIE. Il riconoscimento è automatico e non richiede il PIN.',
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            22 + 144 * CieCardIllustration.artworkLeftFraction,
            22,
            22,
            22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  context,
                  homeCardStatus(
                    readers: readers,
                    checked: cardsChecked,
                    error: monitor?.code,
                  ),
                ),
              ),
              if (candidates.length <= 1) ...[
                const SizedBox(height: 14),
                _homePairButton(
                  context,
                  candidates.isEmpty ? null : candidates.single,
                ),
              ],
              if (candidates.length > 1)
                for (final card in candidates) ...[
                  const SizedBox(height: 14),
                  _homePairButton(context, card, multiple: true),
                ],
            ],
          ),
        ),
      ),
      if (!pairingsReadable)
        Text(
          tr(
            context,
            "Archivio protetto non leggibile. Gli abbinamenti esistenti sono conservati; il PIN parziale non è disponibile.",
          ),
        ),
      for (final record in enrollment.records.values)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PairedCardIdentity(
                  key: ValueKey('paired-card-identity-${record.id}'),
                  name: record.name,
                  number: record.cardNumber,
                  present: _pairedCardPresent(record.id),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 144 * CieCardIllustration.artworkLeftFraction,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, record.status)),
                      if (_webComponentNotice == null ||
                          record.removalPending ||
                          !record.hasPublicData)
                        Text(tr(context, record.webStatus)),
                      if (record.certificateValidity case final validity?)
                        Text(
                          tr(context, 'Scadenza del certificato CIE: {p0}', [
                            MaterialLocalizations.of(context)
                                .formatShortDate(validity.notAfter.toLocal()),
                          ]),
                        ),
                      if (record.certificateWarning(DateTime.now())
                          case final warning?)
                        Text(
                          tr(context, warning),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (_webComponentNotice != null &&
                              !record.removalPending &&
                              !record.needsAppUpdate &&
                              (!record.readyForSigning ||
                                  !record.hasPublicData))
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _completeEnrollment(record),
                              child: Text(tr(context, 'Completa abbinamento')),
                            ),
                          if (_webComponentNotice == null &&
                              !record.removalPending &&
                              !record.needsAppUpdate &&
                              (!record.readyForSigning ||
                                  !record.hasPublicData ||
                                  !record.webProvisioned ||
                                  !record.componentAvailable))
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => record.needsComponentInstaller
                                        ? _showWebCompletionStatus(
                                            record.webStatus,
                                          )
                                        : record.needsComponentActivation &&
                                              record.readyForSigning &&
                                              record.hasPublicData
                                        ? _activateWebComponent(
                                            update: record.needsComponentUpdate,
                                          )
                                        : record.needsSystemSettings &&
                                              record.readyForSigning &&
                                              record.hasPublicData
                                        ? _openWebSettings()
                                        : _completeEnrollment(record),
                              child: Text(
                                record.needsComponentInstaller
                                    ? tr(
                                        context,
                                        record.needsComponentUpdate
                                            ? 'Aggiorna accesso ai siti'
                                            : 'Informazioni accesso ai siti',
                                      )
                                    : record.needsComponentActivation &&
                                          record.readyForSigning &&
                                          record.hasPublicData
                                    ? tr(
                                        context,
                                        record.needsComponentUpdate
                                            ? 'Aggiorna accesso ai siti'
                                            : 'Attiva accesso ai siti',
                                      )
                                    : record.needsSystemSettings &&
                                          record.readyForSigning &&
                                          record.hasPublicData
                                    ? tr(
                                        context,
                                        'Apri Impostazioni di Sistema',
                                      )
                                    : record.hasPublicData &&
                                          record.readyForSigning &&
                                          record.webProvisioned &&
                                          !record.componentAvailable
                                    ? tr(
                                        context,
                                        widget.windowsWebComponentChecker !=
                                                null
                                            ? 'Completa accesso ai siti'
                                            : 'Informazioni accesso ai siti',
                                      )
                                    : record.hasPublicData &&
                                          record.readyForSigning
                                    ? tr(context, "Completa accesso ai siti")
                                    : tr(context, "Completa abbinamento"),
                              ),
                            ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: busy ? null : () => _unpair(record.id),
                            child: Text(
                              tr(
                                context,
                                record.removalPending
                                    ? "Riprova rimozione"
                                    : "Rimuovi CIE",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (enrollment.records.isNotEmpty)
        TextButton(
          onPressed: busy ? null : () => _unpair(''),
          child: Text(tr(context, "Rimuovi tutte le CIE")),
        ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          "L’abbinamento consente di firmare con le ultime quattro cifre del PIN e predispone l’accesso ai siti. Per accedere ai siti, il browser richiede tutte le otto cifre del PIN nella finestra protetta del sistema.",
        ),
      ),
    ];
  }

  List<Widget> _signPage(BuildContext context) {
    final step = currentSigningStep;
    final target = signingTarget;
    final pairedMode = signingUnpaired == false;
    final occupied = target?['occupied'] == true;
    return [
      _heading(
        context,
        'Firma Elettronica',
        'Scegli il documento e il tipo di firma, poi inserisci il PIN.',
      ),
      const SizedBox(height: 20),
      if (!canSign)
        Text(
          tr(
            context,
            "Adattatore di firma non disponibile per questa piattaforma.",
          ),
        ),
      if (busy) ...[
        const SizedBox(height: 24),
        Text(tr(context, "Attendi il completamento dell’operazione.")),
      ] else ...[
        if (step != SigningStep.result)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final item in {
                  SigningStep.card: 'CIE',
                  SigningStep.document: 'Documento',
                  SigningStep.format: 'Tipo di firma',
                  if (format == 'pdf' && graphicSignature && canAppearance)
                    SigningStep.appearance: 'Firma grafica',
                  SigningStep.pin: 'PIN e salvataggio',
                }.entries) ...[
                  if (item.key != SigningStep.card)
                    const Icon(Icons.play_arrow, size: 20),
                  Chip(
                    label: Text(tr(context, item.value)),
                    avatar: item.key == step
                        ? const Icon(Icons.edit, size: 16)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        if (step == SigningStep.card) ...[
          Text(
            tr(
              context,
              "Seleziona la CIE con cui firmare tra quelle in elenco",
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final id in pairedCards)
            Card(
              child: ListTile(
                leading: CieCardIllustration(
                  width: 72,
                  inColor: _pairedCardPresent(id),
                ),
                key: ValueKey('signing-card-$id'),
                title: Text(_pairedName(id) ?? tr(context, "Carta abbinata")),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enrollment.records[id]?.cardNumber.isNotEmpty == true
                          ? tr(context, "Numero carta: {p0}", [
                              enrollment.records[id]!.cardNumber,
                            ])
                          : tr(context, "Numero carta non disponibile"),
                    ),
                    Text(tr(context, "PIN di 4 cifre")),
                  ],
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseSigningCard(id),
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _chooseSigningCard(null),
            child: Text(tr(context, "Firma con CIE non presente in elenco")),
          ),
          const SizedBox(height: 24),
          Text(
            tr(
              context,
              "Puoi preparare il documento prima di appoggiare la CIE al lettore. Senza abbinamento userai il PIN completo.",
            ),
          ),
        ],
        if (step == SigningStep.document) ...[
          if (pairedMode)
            Text(tr(context, "CIE selezionata: {p0}", [signingCardLabel])),
          DocumentDropZone(
            enabled: canSign && ready,
            onPaths: (paths) => _drop(paths, verify: false),
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(Icons.upload_file_outlined, size: 64),
                  const SizedBox(height: 20),
                  Text(tr(context, "Trascina qui il documento da firmare")),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: canSign && ready ? _chooseInput : null,
                    child: Text(tr(context, "Seleziona un documento")),
                  ),
                  if (input.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(input),
                    TextButton(
                      onPressed: () =>
                          setState(() => signingStep = SigningStep.format),
                      child: Text(tr(context, "Continua con questo documento")),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (step == SigningStep.format) ...[
          SelectableText(input),
          const SizedBox(height: 20),
          if (signingCosign) ...[
            Text(
              tr(context, "Aggiungi una firma"),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              tr(
                context,
                "Il P7M contiene {p0} firme integre. La tua firma sarà aggiunta allo stesso contenuto, conservando le firme esistenti.",
                [existingSignatures],
              ),
            ),
          ] else ...[
            RadioGroup<String>(
              groupValue: format,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  format = value;
                  pin.clear();
                  signature = null;
                });
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'pdf',
                    enabled: signingPdf,
                    title: Text(tr(context, "Firma PAdES · PDF")),
                    subtitle: Text(
                      signingPdf
                          ? tr(
                              context,
                              "Il documento rimane un PDF. Puoi aggiungere una firma grafica.",
                            )
                          : tr(
                              context,
                              "Disponibile solo per PDF supportati e non protetti da password.",
                            ),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'p7m',
                    title: Text(tr(context, "Firma CAdES · P7M")),
                    subtitle: Text(
                      tr(
                        context,
                        "Crea un file .p7m contenente il documento e la firma.",
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (format == 'pdf' && canAppearance)
              CheckboxListTile(
                value: graphicSignature,
                onChanged: (v) => setState(() {
                  graphicSignature = v ?? false;
                  pin.clear();
                }),
                title: Text(tr(context, "Aggiungi firma grafica")),
                subtitle: Text(
                  tr(
                    context,
                    "Nome e Cognome vengono letti direttamente dalla CIE.",
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() {
              pin.clear();
              error = null;
              signingStep = format == 'pdf' && graphicSignature && canAppearance
                  ? SigningStep.appearance
                  : SigningStep.pin;
            }),
            child: Text(
              signingCosign
                  ? tr(context, "Aggiungi una firma")
                  : tr(context, "Prosegui"),
            ),
          ),
        ],
        if (step == SigningStep.appearance) ...[
          Text(
            tr(context, "Posiziona la firma nel PDF"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            tr(
              context,
              "Scegli la pagina, trascina il riquadro e regola le dimensioni nell’anteprima. Il Nome e Cognome finali sono letti dalla CIE durante la firma.",
            ),
          ),
          if (!pairedMode)
            Text(
              tr(
                context,
                "La firma grafica senza abbinamento è una funzione aggiuntiva di questa applicazione.",
              ),
            ),
          if (preferences.imagePath != null && preparedPdf == null)
            CheckboxListTile(
              value: migrateGlobalImage,
              onChanged: (v) => setState(() => migrateGlobalImage = v ?? false),
              title: Text(
                tr(context, "Usa l’immagine delle preferenze precedenti"),
              ),
              subtitle: Text(
                pairedMode
                    ? tr(
                        context,
                        "Una copia verrà associata soltanto alla CIE scelta.",
                      )
                    : tr(
                        context,
                        "L’immagine originale delle preferenze viene conservata.",
                      ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _configureAppearance,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              preparedPdf == null
                  ? tr(context, "Anteprima e personalizzazione")
                  : tr(context, "Aggiorna firma grafica"),
            ),
          ),
          if (preparedPdf != null) ...[
            Text(
              tr(context, "Firma grafica pronta · pagina {p0}", [
                preparedPdf!.appearance.page + 1,
              ]),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() {
                pin.clear();
                signingStep = SigningStep.pin;
              }),
              child: Text(tr(context, "Prosegui")),
            ),
          ],
        ],
        if (step == SigningStep.pin) ...[
          SelectableText(input),
          const SizedBox(height: 12),
          Text(
            format == 'pdf'
                ? tr(context, "Firma PAdES · PDF{p0}", [
                    graphicSignature ? tr(context, ' con firma grafica') : '',
                  ])
                : format == 'cosign'
                ? tr(context, "Aggiungi una firma al P7M")
                : tr(context, "Firma CAdES · P7M"),
          ),
          if (pairedMode)
            Text(tr(context, "CIE selezionata: {p0}", [signingCardLabel])),
          if (target == null)
            Text(
              pairedMode
                  ? tr(
                      context,
                      "Appoggia la CIE scelta al lettore prima di firmare.",
                    )
                  : tr(
                      context,
                      "Appoggia la CIE al lettore; verrà riconosciuta automaticamente.",
                    ),
            ),
          if (occupied)
            Text(
              tr(
                context,
                "Carta in uso: attendi che l’altra applicazione abbia terminato.",
              ),
            ),
          if (!pairedMode &&
              readers.where((r) => r['isCie'] == true).length > 1)
            DropdownButton<String>(
              hint: Text(tr(context, "Scegli il lettore con la CIE")),
              value: selected?['name'] as String?,
              isExpanded: true,
              items: readers
                  .where((r) => r['isCie'] == true)
                  .map(
                    (r) => DropdownMenuItem<String>(
                      value: r['name'] as String,
                      child: Text(
                        tr(context, "{p0} · {p1}", [
                          _pairedName(r['cardId'] as String?) ??
                              tr(context, 'Carta CIE'),
                          r['name'],
                        ]),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (name) async {
                await _changeCard(readers.firstWhere((r) => r['name'] == name));
                if (mounted) setState(() {});
              },
            ),
          const SizedBox(height: 20),
          if (pairedMode && !signingPartial && !fullPinFallback) ...[
            Text(
              tr(
                context,
                "L’abbinamento non è disponibile nell’archivio protetto. Puoi scegliere esplicitamente il PIN completo, senza tentativi automatici.",
              ),
            ),
            OutlinedButton(
              onPressed: () => setState(() {
                pin.clear();
                fullPinFallback = true;
              }),
              child: Text(tr(context, "Usa PIN completo")),
            ),
          ] else ...[
            TextField(
              controller: pin,
              enabled: canSign && target != null && !occupied,
              obscureText: true,
              enableIMEPersonalizedLearning: false,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              maxLength: signingPartial ? 4 : 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: signingPartial
                    ? tr(context, "Ultime 4 cifre del PIN")
                    : tr(context, "PIN completo · 8 cifre"),
                helperMaxLines: 3,
                helperText: tr(
                  context,
                  "Premi Firma e scegli dove salvare il documento. Annullando il salvataggio il PIN viene cancellato e la firma non viene avviata.",
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: !ready || !canSign || target == null || occupied
                  ? null
                  : _sign,
              icon: const Icon(Icons.draw_outlined),
              label: Text(tr(context, "Firma")),
            ),
            if (pairedMode && signingPartial && error != null)
              TextButton(
                onPressed: () => setState(() {
                  pin.clear();
                  fullPinFallback = true;
                  error = null;
                }),
                child: Text(tr(context, "Usa PIN completo")),
              ),
          ],
        ],
        if (step == SigningStep.result && signature?['ok'] == true) ...[
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            tr(context, "File firmato con successo"),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SelectableText(output),
          const SizedBox(height: 12),
          Text(signedResultSummary(signature!['verification'])),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _concludeSigning,
            child: Text(tr(context, "Concludi")),
          ),
          if (signature!['verification'] is Map)
            ExpansionTile(
              title: Text(tr(context, "Dettagli della verifica")),
              children: [
                VerificationView(
                  result: Map<String, dynamic>.from(
                    signature!['verification'] as Map,
                  ),
                ),
              ],
            ),
        ],
        if (step != SigningStep.result &&
            step != SigningStep.card &&
            input.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextButton(
              onPressed: _concludeSigning,
              child: Text(tr(context, "Annulla")),
            ),
          ),
      ],
    ];
  }

  List<Widget> _verifyPage(BuildContext context) => [
    _heading(
      context,
      'Verifica Firma',
      'La verifica dei documenti non richiede lettore, carta o PIN.',
    ),
    const SizedBox(height: 20),
    if (verifyPath.isEmpty || verifyFlow.checking) ...[
      DocumentDropZone(
        enabled: ready && !flow.busy && !verifyFlow.exporting,
        onPaths: (paths) => _drop(paths, verify: true),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.fact_check_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                tr(
                  context,
                  "Trascina qui un documento PDF o P7M da verificare",
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: ready && !flow.busy && !verifyFlow.exporting
                    ? _chooseVerificationDocument
                    : null,
                child: Text(
                  verifyFlow.checking
                      ? tr(context, "Scegli un altro documento")
                      : tr(context, "Seleziona un documento"),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    if (verifyPath.isNotEmpty) ...[
      const SizedBox(height: 16),
      SelectableText(verifyPath),
    ],
    if (verifyFlow.checking) ...[
      const SizedBox(height: 16),
      Text(
        tr(
          context,
          "Verifica in corso. I controlli online possono richiedere qualche istante.",
        ),
      ),
      TextButton(
        onPressed: _concludeVerification,
        child: Text(tr(context, "Annulla verifica")),
      ),
    ],
    if (!verifyFlow.checking && verification != null) ...[
      const SizedBox(height: 20),
      VerificationView(key: ValueKey(verification), result: verification!),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed: verifyFlow.exporting ? null : _concludeVerification,
            child: Text(tr(context, "Concludi")),
          ),
          OutlinedButton.icon(
            onPressed: verifyFlow.running || flow.busy
                ? null
                : () => _startVerification(verifyPath),
            icon: const Icon(Icons.refresh),
            label: Text(tr(context, "Ripeti verifica")),
          ),
          OutlinedButton(
            onPressed: flow.busy || verifyFlow.exporting
                ? null
                : _chooseVerificationDocument,
            child: Text(tr(context, "Scegli un altro documento")),
          ),
          if (verifyFlow.extractable)
            OutlinedButton.icon(
              onPressed: verifyFlow.running || flow.busy ? null : _extract,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(tr(context, "Estrai documento")),
            ),
        ],
      ),
      if (verifyFlow.extractable) ...[
        const SizedBox(height: 12),
        Text(
          tr(
            context,
            "L’estrazione del contenuto non sostituisce la verifica della firma.",
          ),
        ),
      ],
    ],
    AppNotification(
      event: extraction,
      message: extraction == null
          ? null
          : extraction!['ok'] == true
          ? 'Documento estratto e salvato.'
          : verificationProblemMessage(extraction!, extraction: true),
      error: extraction?['ok'] == false,
      details: extraction?['ok'] == true
          ? (extraction?['output'] as String?)
          : [
              if (extraction?['message'] is String)
                tr(context, extraction!['message'] as String),
              if (extraction?['code'] != null) '${extraction!['code']}',
              if (extraction?['nativeCode'] != null)
                tr(context, 'Codice nativo: {p0}', [extraction!['nativeCode']]),
            ].join('\n'),
      enabled: !verifyFlow.exporting,
    ),
  ];
  Widget _heading(BuildContext context, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page == AppDestination.home.index) ...[
            Text(
              tr(context, title),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
          ],
          Text(tr(context, subtitle)),
        ],
      );
}
