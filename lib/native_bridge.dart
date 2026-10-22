// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'long_term_validation.dart';
import 'document_model.dart';
import 'network_settings.dart';
import 'card_observation_process.dart';
export 'document_model.dart';

typedef JsonResult = Map<String, dynamic>;
typedef _NoArgs = Pointer<Utf8> Function();
typedef _Pair = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _OneArg = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Load = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _PdfInfoNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _PdfInfoDart = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _PdfSignNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Int32,
  Double,
  Double,
  Double,
  Double,
);
typedef _PdfSignDart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
  double,
  double,
  double,
  double,
);
typedef _Pin = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _Sign = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

final class NativeNetworkOptions extends Struct {
  @Uint32()
  external int size;
  @Int32()
  external int mode;
  external Pointer<Utf8> host;
  @Int32()
  external int port;
  external Pointer<Utf8> username;
  external Pointer<Utf8> password;
}

typedef _NetworkOne = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<NativeNetworkOptions>,
);
typedef _NetworkProbe = Pointer<Utf8> Function(Pointer<NativeNetworkOptions>);
typedef _NetworkSign = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<NativeNetworkOptions>,
);
typedef _NetworkPdfNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Int32,
  Double,
  Double,
  Double,
  Double,
  Pointer<NativeNetworkOptions>,
);
typedef _NetworkPdfDart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
  double,
  double,
  double,
  double,
  Pointer<NativeNetworkOptions>,
);

abstract interface class NetworkService {
  void setNetwork(SessionNetworkConfig config);
  void blockNetworkConfiguration();
  Future<JsonResult> probeNetwork(SessionNetworkConfig config);
}

class BridgePaths {
  const BridgePaths(this.bridge, this.middleware, this.cardAdapter);
  final String bridge;
  final String middleware;
  final String cardAdapter;
  factory BridgePaths.discover() {
    final override = Platform.environment['CIE_PROTOTYPE_RUNTIME'];
    final executable = File(Platform.resolvedExecutable).parent;
    final bundled = Platform.isMacOS
        ? '${executable.parent.path}/Frameworks/CIEPrototype'
        : '${executable.path}/cie_native';
    final folder =
        override ??
        (Directory(bundled).existsSync()
            ? bundled
            : '${Directory.current.path}/native/runtime/${Platform.operatingSystem}');
    final suffix = Platform.isWindows
        ? '.dll'
        : (Platform.isMacOS ? '.dylib' : '.so');
    final prefix = Platform.isWindows ? '' : 'lib';
    final adapter = '$folder/${prefix}cie_card_adapter$suffix';
    return BridgePaths(
      '$folder/${prefix}cie_bridge$suffix',
      '$folder/${prefix}cie-pkcs11$suffix',
      File(adapter).existsSync() ? adapter : '',
    );
  }
}

abstract interface class CieService {
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  });
  Future<JsonResult> load();
  Future<JsonResult> detect();
  Future<JsonResult> verify(String path);
  Future<JsonResult> pdfInfo(String path, int page);
  Future<JsonResult> extract(String input, String output);
  Future<JsonResult> sign({
    required String reader,
    required String card,
    required String input,
    required String output,
    required String format,
    required String pin,
    PdfAppearance? appearance,
    bool replaceExisting = false,
  });
}

// Prefix retrieval and reconstruction happen exclusively inside the native bridge.
abstract interface class SigningInfoService {
  Future<JsonResult> signingInfo(String path);
}

abstract interface class PairingService {
  Future<JsonResult> pairings();
  Future<JsonResult> pair(String reader, String card, String fullPin);
  Future<JsonResult> unpair(String card);
}

abstract interface class WebAccessService {
  Future<JsonResult> enrollWeb(String reader, String card, String fullPin);
  Future<JsonResult> forgetWeb(String card);
  Future<JsonResult> testWeb(String card);
}

abstract interface class CardObservationService {
  Future<JsonResult> observeCards();
}

abstract interface class CancellableCardObservation {
  Future<void> cancelCardObservation();
}

abstract interface class CertificateNameService {
  Future<JsonResult> certificateName(String certificateHex);
}

abstract interface class EnrollmentService {
  Future<JsonResult> enroll(String reader, String card, String fullPin);
  Future<JsonResult> enrollments();
  Future<JsonResult> completeEnrollment(String card);
  Future<JsonResult> forgetEnrollment(String card);
  Future<JsonResult> webStatus();
}

class FfiCieService
    implements
        CieService,
        SigningInfoService,
        NetworkService,
        PairingService,
        WebAccessService,
        CardObservationService,
        CancellableCardObservation,
        EnrollmentService,
        CertificateNameService {
  FfiCieService(this.paths, {CardObservationProcess? observationProcess})
    : observationProcess =
          observationProcess ??
          CardObservationProcess(
            '${File(paths.bridge).absolute.parent.path}/cie_card_observer${Platform.isWindows ? '.exe' : ''}',
            [
              File(paths.middleware).absolute.path,
              paths.cardAdapter.isEmpty
                  ? ''
                  : File(paths.cardAdapter).absolute.path,
            ],
          );
  final BridgePaths paths;
  final CardObservationProcess observationProcess;
  @override
  Future<void> cancelCardObservation() => observationProcess.cancel();
  SessionNetworkConfig _network = const SessionNetworkConfig();
  bool _networkReady = true;
  @override
  void blockNetworkConfiguration() {
    _networkReady = false;
  }

  @override
  void setNetwork(SessionNetworkConfig config) {
    config.validate();
    _network = config;
    _networkReady = true;
  }

  @override
  Future<JsonResult> probeNetwork(SessionNetworkConfig config) =>
      _run('network_probe', [], overrideNetwork: config);
  bool _busy = false;
  String? _activeOperation;
  Completer<void>? _idle;
  Future<JsonResult> _run(
    String operation,
    List<String> args, {
    SessionNetworkConfig? overrideNetwork,
    bool replaceExisting = false,
  }) async {
    if (!_networkReady &&
        overrideNetwork == null &&
        const {
          'verify',
          'sign',
          'sign_pdf',
          'network_probe',
        }.contains(operation)) {
      return {
        'ok': false,
        'code': 'network_configuration_required',
        'message': 'Le impostazioni di rete non sono leggibili. Salvale o ripristinale dalla pagina Impostazioni prima di continuare.',
      };
    }
    // Document checks have no card prerequisite. Wait only for an already
    // running, bounded public observation/status read; do not retry any operation.
    if (const {'verify', 'extract'}.contains(operation) &&
        _busy &&
        const {'observe', 'web_status'}.contains(_activeOperation)) {
      await _idle?.future;
    }
    if (_busy) {
      return {
        'ok': false,
        'code': 'busy',
        'message': 'Attendere il completamento dell’operazione',
      };
    }
    _busy = true;
    _activeOperation = operation;
    final idle = Completer<void>();
    _idle = idle;
    try {
      // Blocking card/network operations run outside the UI isolate. Dart cannot
      // guarantee erasure of managed strings; PINs are never persisted or logged.
      final config = paths;
      final network = overrideNetwork ?? _network;
      network.validate();
      if (operation == 'observe' || operation == 'detect') {
        return await observationProcess.query(manual: operation == 'detect');
      }
      if (operation == 'verify') {
        return await verifyDocumentSnapshot(
          args.single,
          native: (document) => Isolate.run(
            () =>
                NativeBridge(config)
                    .execute('verify', [document], network: network),
          ),
          archival: (document) =>
              LongTermValidator.fromBridge(config.bridge)
                  .verify(document, network: network),
        );
      }
      return await Isolate.run(
        () => NativeBridge(config).execute(
          operation,
          args,
          network: network,
          replaceExisting: replaceExisting,
        ),
      );
    } catch (_) {
      if (operation == 'change_pin' || operation == 'unblock_pin') {
        return {
          'ok': false,
          'code': 'pin_operation_indeterminate',
          'outcome': 'indeterminate',
          'message': 'Impossibile confermare l’esito della modifica. Il PIN potrebbe essere già cambiato: non ripetere automaticamente l’operazione.',
        };
      }
      return {
        'ok': false,
        'code': 'native_unavailable',
        'message': 'Componente nativo non disponibile. Preparare il runtime per questa piattaforma.',
      };
    } finally {
      _busy = false;
      _activeOperation = null;
      idle.complete();
      if (identical(_idle, idle)) _idle = null;
    }
  }

  @override
  Future<JsonResult> observeCards() => _run('observe', []);
  @override
  Future<JsonResult> enroll(String reader, String card, String fullPin) =>
      _run('enroll', [reader, card, fullPin]);
  @override
  Future<JsonResult> enrollments() => _run('enrollments', []);
  @override
  Future<JsonResult> certificateName(String certificateHex) =>
      _run('certificate_name', [certificateHex]);
  @override
  Future<JsonResult> completeEnrollment(String card) =>
      _run('complete_enrollment', [card]);
  @override
  Future<JsonResult> forgetEnrollment(String card) =>
      _run('forget_enrollment', [card]);
  @override
  Future<JsonResult> webStatus() => _run('web_status', []);
  @override
  Future<JsonResult> pairings() => _run('pairings', []);
  @override
  Future<JsonResult> pair(String reader, String card, String fullPin) =>
      _run('pair', [reader, card, fullPin]);
  @override
  Future<JsonResult> unpair(String card) => _run('unpair', [card]);
  @override
  Future<JsonResult> enrollWeb(String reader, String card, String fullPin) =>
      _run('web_enroll', [reader, card, fullPin]);
  @override
  Future<JsonResult> forgetWeb(String card) => _run('web_forget', [card]);
  @override
  Future<JsonResult> testWeb(String card) => _run('web_test', [card]);

  @override
  Future<JsonResult> load() => _run('load', []);
  @override
  Future<JsonResult> detect() => _run('detect', []);
  @override
  Future<JsonResult> updatePin({
    required String reader,
    required String card,
    required String authentication,
    required String newPin,
    required bool unblock,
  }) => _run(unblock ? 'unblock_pin' : 'change_pin', [
    reader,
    card,
    authentication,
    newPin,
  ]);
  @override
  Future<JsonResult> verify(String path) => _run('verify', [path]);
  @override
  Future<JsonResult> pdfInfo(String path, int page) =>
      _run('pdf_info', [path, '$page']);
  @override
  Future<JsonResult> signingInfo(String path) => _run('signing_info', [path]);
  @override
  Future<JsonResult> extract(String input, String output) =>
      _run('extract', [input, output]);
  @override
  Future<JsonResult> sign({
    required String reader,
    required String card,
    required String input,
    required String output,
    required String format,
    required String pin,
    PdfAppearance? appearance,
    bool replaceExisting = false,
  }) => appearance == null
      ? _run('sign', [
          reader,
          card,
          input,
          output,
          format,
          pin,
        ], replaceExisting: replaceExisting)
      : format != 'pdf' || !appearance.valid
      ? Future.value({
          'ok': false,
          'code': 'invalid_appearance',
          'message': 'Impostazioni della firma PDF non valide',
        })
      : _run('sign_pdf', [
          reader,
          card,
          input,
          output,
          pin,
          appearance.imagePath,
          '${appearance.page}',
          '${appearance.left}',
          '${appearance.top}',
          '${appearance.width}',
          '${appearance.height}',
        ], replaceExisting: replaceExisting);
}

// Also used by headless smoke tests: no Flutter dependency in this file.
class NativeBridge {
  NativeBridge(this.paths) {
    // MinGW runtimes are private, adjacent to the bridge. Load these exact paths
    // before the bridge rather than adding writable directories to DLL search.
    if (Platform.isWindows) {
      final directory = File(paths.bridge).parent.path;
      for (final name in [
        'libwinpthread-1.dll',
        'libgcc_s_seh-1.dll',
        'libstdc++-6.dll',
      ]) {
        final file = File('$directory/$name');
        if (file.existsSync()) {
          _dependencies.add(DynamicLibrary.open(file.path));
        }
      }
    }
    _library = DynamicLibrary.open(paths.bridge);
    final abi = _library.lookupFunction<Uint32 Function(), int Function()>(
      'cie_bridge_abi_version',
    )();
    if (abi != 1) throw StateError('ABI del ponte non supportata');
    _free = _library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('cie_bridge_free');
  }
  final BridgePaths paths;
  late final DynamicLibrary _library;
  final List<DynamicLibrary> _dependencies = [];
  late final void Function(Pointer<Utf8>) _free;
  JsonResult _decode(Pointer<Utf8> pointer) {
    if (pointer == nullptr) throw StateError('Memoria nativa insufficiente');
    try {
      final bytes = pointer.cast<Uint8>();
      int length = 0;
      const maximum = 16 * 1024 * 1024;
      while (length < maximum && bytes[length] != 0) {
        length++;
      }
      if (length == maximum) throw StateError('Risposta nativa troppo lunga');
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes.asTypedList(length), allowMalformed: true))
            as Map,
      );
    } finally {
      _free(pointer);
    }
  }

  JsonResult execute(
    String operation,
    List<String> args, {
    SessionNetworkConfig network = const SessionNetworkConfig(),
    bool replaceExisting = false,
  }) {
    network.validate();
    final module = paths.middleware.toNativeUtf8();
    final adapter = paths.cardAdapter.toNativeUtf8();
    try {
      final loaded = _decode(
        _library.lookupFunction<_Load, _Load>('cie_bridge_load')(
          module,
          adapter,
        ),
      );
      if (operation == 'load' || loaded['ok'] != true) return loaded;
    } finally {
      calloc.free(module);
      calloc.free(adapter);
    }
    if (operation == 'observe') {
      if (!_library.providesSymbol('cie_bridge_observe')) {
        return {'ok': false, 'code': 'observation_unavailable'};
      }
      return _decode(
        _library.lookupFunction<_NoArgs, _NoArgs>('cie_bridge_observe')(),
      );
    }
    if (operation == 'detect') {
      return _decode(
        _library.lookupFunction<_NoArgs, _NoArgs>('cie_bridge_detect')(),
      );
    }
    final pointers = args.map((s) => s.toNativeUtf8()).toList();
    final n = calloc<NativeNetworkOptions>();
    final host = network.proxy.host.toNativeUtf8(),
        user = network.username.toNativeUtf8(),
        password = network.password.toNativeUtf8();
    n.ref
      ..size = sizeOf<NativeNetworkOptions>()
      ..mode = network.proxy.mode.index
      ..host = host
      ..port = network.proxy.port
      ..username = user
      ..password = password;
    try {
      final needsNetwork = const {
        'verify',
        'sign',
        'sign_pdf',
        'network_probe',
      }.contains(operation);
      final networkAvailable = _library.providesSymbol(
        'cie_bridge_verify_network',
      );
      if (needsNetwork &&
          !networkAvailable &&
          (network.proxy.mode != ProxyMode.direct ||
              operation == 'network_probe')) {
        return {
          'ok': false,
          'code': 'network_unavailable',
          'message': 'Aggiornare il runtime per applicare la configurazione proxy. Nessuna connessione diretta alternativa è stata eseguita.',
        };
      }
      if (const {
        'enroll',
        'enrollments',
        'certificate_name',
        'complete_enrollment',
        'forget_enrollment',
        'web_status',
        'pair',
        'pairings',
        'unpair',
        'web_enroll',
        'web_forget',
        'web_test',
      }.contains(operation)) {
        final symbol = 'cie_bridge_$operation';
        if (!_library.providesSymbol(symbol)) {
          return {
            'ok': false,
            'code': operation.startsWith('web_')
                ? 'web_unavailable'
                : 'pairing_unavailable',
            'message': operation.startsWith('web_')
                ? 'Aggiornare il runtime per configurare l’accesso ai siti.'
                : 'Aggiornare il runtime per gestire gli abbinamenti.',
          };
        }
        if (operation == 'pairings' ||
            operation == 'enrollments' ||
            operation == 'web_status') {
          return _decode(_library.lookupFunction<_NoArgs, _NoArgs>(symbol)());
        }
        if (operation == 'certificate_name' ||
            operation == 'complete_enrollment' ||
            operation == 'forget_enrollment' ||
            operation == 'unpair' ||
            operation == 'web_forget' ||
            operation == 'web_test') {
          return _decode(
            _library.lookupFunction<_OneArg, _OneArg>(symbol)(pointers.single),
          );
        }
        return _decode(
          _library.lookupFunction<_Pair, _Pair>(symbol)(
            pointers[0],
            pointers[1],
            pointers[2],
          ),
        );
      }
      if (operation == 'network_probe') {
        return _decode(
          _library.lookupFunction<_NetworkProbe, _NetworkProbe>(
            'cie_bridge_network_probe',
          )(n),
        );
      }
      if (networkAvailable && operation == 'verify') {
        return _decode(
          _library.lookupFunction<_NetworkOne, _NetworkOne>(
            'cie_bridge_verify_network',
          )(pointers.single, n),
        );
      }
      if ((operation == 'sign' && args[5].length == 4 ||
              operation == 'sign_pdf' && args[4].length == 4) &&
          (!_library.providesSymbol('cie_bridge_sign_paired_network') ||
              !networkAvailable)) {
        return {
          'ok': false,
          'code': 'pairing_unavailable',
          'message': 'PIN parziale non disponibile in questo runtime. Nessun tentativo sulla carta.',
        };
      }
      final replacementSuffix = replaceExisting ? '_replace' : '';
      if (replaceExisting &&
          (operation == 'sign' || operation == 'sign_pdf') &&
          (!networkAvailable ||
              !_library.providesSymbol('cie_bridge_sign_network_replace'))) {
        return {
          'ok': false,
          'code': 'replacement_unavailable',
          'message': 'Aggiorna il componente di firma per sostituire un file esistente. Nessun PIN inviato alla carta.',
        };
      }
      if (networkAvailable && operation == 'sign') {
        return _decode(
          _library.lookupFunction<_NetworkSign, _NetworkSign>(
            args[5].length == 4
                ? 'cie_bridge_sign_paired_network$replacementSuffix'
                : 'cie_bridge_sign_network$replacementSuffix',
          )(
            pointers[0],
            pointers[1],
            pointers[2],
            pointers[3],
            pointers[4],
            pointers[5],
            n,
          ),
        );
      }
      if (networkAvailable && operation == 'sign_pdf') {
        return _decode(
          _library.lookupFunction<_NetworkPdfNative, _NetworkPdfDart>(
            args[4].length == 4
                ? 'cie_bridge_sign_pdf_paired_network$replacementSuffix'
                : 'cie_bridge_sign_pdf_network$replacementSuffix',
          )(
            pointers[0],
            pointers[1],
            pointers[2],
            pointers[3],
            pointers[4],
            pointers[5],
            int.parse(args[6]),
            double.parse(args[7]),
            double.parse(args[8]),
            double.parse(args[9]),
            double.parse(args[10]),
            n,
          ),
        );
      }
      if (operation == 'signing_info') {
        return _decode(
          _library.lookupFunction<_OneArg, _OneArg>('cie_bridge_signing_info')(
            pointers[0],
          ),
        );
      }
      if (operation == 'pdf_info') {
        return _decode(
          _library.lookupFunction<_PdfInfoNative, _PdfInfoDart>(
            'cie_bridge_pdf_info',
          )(pointers[0], int.parse(args[1])),
        );
      }
      if (operation == 'extract') {
        return _decode(
          _library.lookupFunction<_Load, _Load>('cie_bridge_extract')(
            pointers[0],
            pointers[1],
          ),
        );
      }
      if (operation == 'sign_pdf') {
        return _decode(
          _library.lookupFunction<_PdfSignNative, _PdfSignDart>(
            'cie_bridge_sign_pdf',
          )(
            pointers[0],
            pointers[1],
            pointers[2],
            pointers[3],
            pointers[4],
            pointers[5],
            int.parse(args[6]),
            double.parse(args[7]),
            double.parse(args[8]),
            double.parse(args[9]),
            double.parse(args[10]),
          ),
        );
      }
      if (operation == 'verify') {
        return _decode(
          _library.lookupFunction<_OneArg, _OneArg>('cie_bridge_verify')(
            pointers.single,
          ),
        );
      }
      if (operation == 'sign' && pointers.length == 6) {
        return _decode(
          _library.lookupFunction<_Sign, _Sign>('cie_bridge_sign')(
            pointers[0],
            pointers[1],
            pointers[2],
            pointers[3],
            pointers[4],
            pointers[5],
          ),
        );
      }
      if ((operation == 'change_pin' || operation == 'unblock_pin') &&
          pointers.length == 4) {
        return _decode(
          _library.lookupFunction<_Pin, _Pin>('cie_bridge_$operation')(
            pointers[0],
            pointers[1],
            pointers[2],
            pointers[3],
          ),
        );
      }
      throw ArgumentError('Operazione sconosciuta');
    } finally {
      if ((operation == 'enroll' ||
              operation == 'pair' ||
              operation == 'web_enroll') &&
          pointers.length == 3) {
        final length = utf8.encode(args[2]).length;
        pointers[2].cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
      }
      if ((operation == 'change_pin' || operation == 'unblock_pin') &&
          pointers.length == 4) {
        for (final i in [2, 3]) {
          final size = utf8.encode(args[i]).length;
          pointers[i].cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
        }
      }
      if (operation == 'sign' && pointers.length == 6) {
        final length = utf8.encode(args[5]).length;
        pointers[5].cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
      }
      if (operation == 'sign_pdf' && pointers.length == 11) {
        final length = utf8.encode(args[4]).length;
        pointers[4].cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
      }
      for (final item in [
        (user, network.username),
        (password, network.password),
      ]) {
        final length = utf8.encode(item.$2).length;
        item.$1.cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
      }
      calloc.free(host);
      calloc.free(user);
      calloc.free(password);
      calloc.free(n);
      for (final pointer in pointers) {
        calloc.free(pointer);
      }
    }
  }
}
