// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'application_storage.dart';

import 'signature_image.dart';

class SignaturePreferences {
  const SignaturePreferences({this.format = 'pdf', this.imagePath});
  final String format;
  final String? imagePath;
}

abstract class PreferencesStore {
  Future<SignaturePreferences> load();
  Future<SignaturePreferences> saveFormat(String format);
  Future<SignaturePreferences> importImage(String source);
  Future<SignaturePreferences> removeImage();
  Future<SignaturePreferences> reset();
}

abstract interface class CardImagePreferences {
  Future<String?> cardImage(String card);
  Future<void> saveCardImage(String card, String source);
  Future<void> removeCardImage(String card);
}

class MemoryPreferencesStore implements PreferencesStore, CardImagePreferences {
  final Map<String, String> _cards = {};
  @override
  Future<String?> cardImage(String card) async => _cards[card];
  @override
  Future<void> saveCardImage(String card, String source) async {
    _cards[card] = source;
  }

  @override
  Future<void> removeCardImage(String card) async {
    _cards.remove(card);
  }

  SignaturePreferences value = const SignaturePreferences();
  @override
  Future<SignaturePreferences> load() async => value;
  @override
  Future<SignaturePreferences> saveFormat(String format) async =>
      value = SignaturePreferences(format: format, imagePath: value.imagePath);
  @override
  Future<SignaturePreferences> importImage(String source) async =>
      value = SignaturePreferences(format: value.format, imagePath: source);
  @override
  Future<SignaturePreferences> removeImage() async =>
      value = SignaturePreferences(format: value.format);
  @override
  Future<SignaturePreferences> reset() async =>
      value = const SignaturePreferences();
}

class FilePreferencesStore implements PreferencesStore, CardImagePreferences {
  Future<FilePreferencesStore> _cardStore(
    String card, {
    bool read = true,
  }) async {
    if (card.isEmpty || utf8.encode(card).length > 100) {
      throw const FormatException('CIE non valida');
    }
    // UTF-8 hex encoding makes an injective, platform-independent safe directory name.
    final key = utf8
        .encode(card)
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();
    final cards = Directory('${(await _directory()).path}/cards');
    await cards.create();
    if (await FileSystemEntity.type(cards.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Archivio immagini non valido');
    }
    if (!Platform.isWindows) {
      final status = await Process.run('/bin/chmod', ['700', cards.path]);
      if (status.exitCode != 0) {
        throw const FileSystemException('Archivio immagini non protetto');
      }
    }
    final store = FilePreferencesStore(
      directory: Directory('${cards.path}/$key'),
    );
    if (read) await store.load();
    return store;
  }

  @override
  Future<String?> cardImage(String card) async =>
      (await (await _cardStore(card)).load()).imagePath;
  @override
  Future<void> saveCardImage(String card, String source) async {
    await (await _cardStore(card)).importImage(source);
  }

  @override
  Future<void> removeCardImage(String card) async {
    await (await _cardStore(card, read: false)).reset();
  }

  FilePreferencesStore({Directory? directory}) : _provided = directory;
  final Directory? _provided;
  Directory? _root;
  SignaturePreferences _value = const SignaturePreferences();
  final _imageName = RegExp(r'^image-[a-f0-9]{32}\.png$');
  File _file(Directory directory, String name) =>
      File.fromUri(directory.uri.resolve(name));
  String _basename(String path) => File(path).uri.pathSegments.last;
  Future<Directory> _directory() async {
    if (_root != null) return _root!;
    final configured =
        _provided ??
        Directory(
          '${(await getPersistentApplicationSupportDirectory()).path}/signature-preferences',
        );
    final root = Directory.fromUri(configured.absolute.uri);
    await root.create(recursive: true);
    final entryPath = root.path.replaceFirst(RegExp(r'[/\\]+$'), '');
    if (entryPath.isEmpty || RegExp(r'^[a-zA-Z]:$').hasMatch(entryPath)) {
      throw const FileSystemException('Cartella preferenze non valida');
    }
    if (await FileSystemEntity.type(entryPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Cartella preferenze non valida');
    }
    if (!Platform.isWindows) {
      final status = await Process.run('/bin/chmod', ['700', root.path]);
      if (status.exitCode != 0) {
        throw const FileSystemException('Impossibile proteggere le preferenze');
      }
    }
    return _root = root;
  }

  @override
  Future<SignaturePreferences> load() async {
    final root = await _directory(), file = _file(root, 'preferences.json');
    if (!await file.exists()) return _value = const SignaturePreferences();
    if (await file.length() > 65536) {
      throw const FormatException('Preferenze non valide');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map ||
        data['schema'] != 1 ||
        !['pdf', 'p7m'].contains(data['format'])) {
      throw const FormatException('Preferenze non valide');
    }
    final name = data['image'];
    String? image;
    if (name != null) {
      if (name is! String || !_imageName.hasMatch(name)) {
        throw const FormatException('Immagine predefinita non valida');
      }
      final f = _file(root, name);
      if (await FileSystemEntity.type(f.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await f.length() > 10 * 1024 * 1024) {
        throw const FormatException(
          'Immagine predefinita mancante o non valida',
        );
      }
      image = f.path;
    }
    return _value = SignaturePreferences(
      format: data['format'] as String,
      imagePath: image,
    );
  }

  Future<SignaturePreferences> _commit(SignaturePreferences next) async {
    if (!['pdf', 'p7m'].contains(next.format)) {
      throw const FormatException('Formato non valido');
    }
    final root = await _directory();
    final file = _file(root, 'preferences.json');
    final temporary = File('${file.path}.tmp-${_token()}');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'schema': 1,
          'format': next.format,
          'image': next.imagePath == null ? null : _basename(next.imagePath!),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      _value = next;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return _value;
  }

  String _token() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _deleteOwned(String? path) async {
    if (path == null) return;
    final root = await _directory();
    final name = _basename(path);
    if (File(path).parent.absolute.uri == root.absolute.uri &&
        _imageName.hasMatch(name)) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Future<SignaturePreferences> saveFormat(String format) => _commit(
    SignaturePreferences(format: format, imagePath: _value.imagePath),
  );
  @override
  Future<SignaturePreferences> importImage(String source) async {
    final root = await _directory(),
        next = _file(root, 'image-${_token()}.png');
    final old = _value.imagePath;
    try {
      await normalizeSignatureImage(File(source), next);
      if (next.parent.absolute.uri != root.absolute.uri) {
        throw const FormatException('Destinazione non valida');
      }
      await _commit(
        SignaturePreferences(format: _value.format, imagePath: next.path),
      );
    } catch (_) {
      if (await next.exists()) await next.delete();
      rethrow;
    }
    await _deleteOwned(old);
    return _value;
  }

  @override
  Future<SignaturePreferences> removeImage() async {
    final old = _value.imagePath;
    await _commit(SignaturePreferences(format: _value.format));
    await _deleteOwned(old);
    return _value;
  }

  @override
  Future<SignaturePreferences> reset() async {
    final old = _value.imagePath;
    await _commit(const SignaturePreferences());
    await _deleteOwned(old);
    final root = await _directory();
    await for (final entry in root.list(followLinks: false)) {
      if (_imageName.hasMatch(_basename(entry.path))) {
        await entry.delete();
      }
    }
    return _value;
  }
}
