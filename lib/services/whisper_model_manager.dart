import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage_service.dart';
import 'power_service.dart';

class WhisperModelSpec {
  const WhisperModelSpec({
    required this.id,
    required this.filename,
    required this.downloadUrl,
    required this.revision,
    required this.sizeBytes,
    required this.sha256,
    required this.minimumRamGB,
  });

  final String id;
  final String filename;
  final String downloadUrl;
  final String revision;
  final int sizeBytes;
  final String sha256;
  final double minimumRamGB;
}

class WhisperModelManager extends ChangeNotifier {
  static final WhisperModelManager instance = WhisperModelManager();

  WhisperModelManager({
    Future<Directory> Function()? directoryProvider,
    HttpClient Function()? httpClientProvider,
    this.spec = tiny,
  }) : _directoryProvider =
           directoryProvider ?? StorageService.instance.asrModelsDir,
       _httpClientProvider = httpClientProvider ?? HttpClient.new;

  static const tiny = WhisperModelSpec(
    id: 'whisper-tiny-multilingual',
    filename: 'ggml-tiny.bin',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin',
    revision: '5359861c739e955e79d9a303bcbc70fb988958b1',
    sizeBytes: 77691713,
    sha256: 'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    minimumRamGB: 0.5,
  );

  final Future<Directory> Function() _directoryProvider;
  final HttpClient Function() _httpClientProvider;
  final WhisperModelSpec spec;
  bool _downloading = false;
  int _receivedBytes = 0;
  String _failure = '';
  Future<String?>? _verification;
  String? _activeRevision;
  bool _canRollback = false;

  bool get downloading => _downloading;
  int get receivedBytes => _receivedBytes;
  double get progress => _receivedBytes / spec.sizeBytes;
  String get failure => _failure;
  String? get activeRevision => _activeRevision;
  bool get updateAvailable =>
      _activeRevision != null && _activeRevision != spec.revision;
  bool get canRollback => _canRollback;

  Future<String?> installedPath() => _verification ??= _verifyInstalledPath();

  Future<String?> _verifyInstalledPath() async {
    final directory = await _directoryProvider();
    final file = File(p.join(directory.path, spec.filename));
    final manifest = await _readManifest(directory);
    final active = _slot(manifest, 'active');
    final previous = _slot(manifest, 'previous');
    final expectedSize = active?['size_bytes'] as int? ?? spec.sizeBytes;
    final expectedSha = active?['sha256'] as String? ?? spec.sha256;
    if (!await file.exists() || await file.length() != expectedSize) {
      return null;
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != expectedSha) return null;
    _activeRevision =
        active?['revision'] as String? ??
        (expectedSha == spec.sha256 ? spec.revision : null);
    final previousFile = File('${file.path}.previous');
    _canRollback =
        previous != null &&
        await _matches(
          previousFile,
          previous['size_bytes'] as int? ?? -1,
          previous['sha256'] as String? ?? '',
        );
    return file.path;
  }

  Future<String> install() async {
    if (_downloading) throw StateError('Whisper model download is in progress');
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, spec.filename));
    if (await _matches(destination, spec.sizeBytes, spec.sha256)) {
      _verification = null;
      final verified = await _verifyInstalledPath();
      if (verified != null && _activeRevision == spec.revision) {
        _verification = Future<String?>.value(verified);
        return verified;
      }
    }
    _downloading = true;
    _receivedBytes = 0;
    _failure = '';
    notifyListeners();
    await PowerService.instance.startDownload('Whisper Tiny');

    final staging = File('${destination.path}.part');
    final previous = File('${destination.path}.previous');
    final client = _httpClientProvider();
    IOSink? sink;
    try {
      if (await staging.exists()) await staging.delete();
      final request = await client.getUrl(Uri.parse(spec.downloadUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Whisper model download returned HTTP ${response.statusCode}',
        );
      }
      sink = staging.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        _receivedBytes = _receivedBytes + chunk.length;
        notifyListeners();
      }
      await sink.close();
      sink = null;
      final size = await staging.length();
      if (size != spec.sizeBytes) {
        throw StateError('Whisper model size mismatch: $size');
      }
      final digest = await sha256.bind(staging.openRead()).first;
      if (digest.toString() != spec.sha256) {
        throw StateError('Whisper model checksum verification failed');
      }
      final oldManifest = await _readManifest(directory);
      Map<String, Object?>? oldActive = _slot(oldManifest, 'active');
      var rollbackSlot = _slot(oldManifest, 'previous');
      if (await destination.exists()) {
        final activeValid =
            oldActive != null &&
            await _matches(
              destination,
              oldActive['size_bytes'] as int? ?? -1,
              oldActive['sha256'] as String? ?? '',
            );
        oldActive ??= {
          'revision': 'legacy',
          'size_bytes': await destination.length(),
          'sha256': (await sha256.bind(destination.openRead()).first)
              .toString(),
        };
        if (activeValid || oldManifest == null) {
          if (await previous.exists()) await previous.delete();
          await destination.rename(previous.path);
          rollbackSlot = oldActive;
        } else {
          // Never publish or retain a checksum-invalid active slot.
          await destination.delete();
        }
      }
      await staging.rename(destination.path);
      await _writeManifest(
        directory,
        active: _specJson(spec),
        previous: rollbackSlot,
      );
      _activeRevision = spec.revision;
      _canRollback = rollbackSlot != null;
      _verification = Future<String?>.value(destination.path);
      return destination.path;
    } on Object catch (error) {
      _failure = error.toString();
      if (await staging.exists()) await staging.delete();
      rethrow;
    } finally {
      await sink?.close();
      client.close(force: true);
      _downloading = false;
      await PowerService.instance.stopDownload();
      notifyListeners();
    }
  }

  Future<bool> rollback() async {
    final directory = await _directoryProvider();
    final destination = File(p.join(directory.path, spec.filename));
    final previous = File('${destination.path}.previous');
    final manifest = await _readManifest(directory);
    final activeSlot = _slot(manifest, 'active');
    final previousSlot = _slot(manifest, 'previous');
    if (activeSlot == null ||
        previousSlot == null ||
        !await _matches(
          previous,
          previousSlot['size_bytes'] as int? ?? -1,
          previousSlot['sha256'] as String? ?? '',
        )) {
      return false;
    }
    final temporary = File('${destination.path}.rollback-part');
    if (await temporary.exists()) await temporary.delete();
    await destination.rename(temporary.path);
    try {
      await previous.rename(destination.path);
      await temporary.rename(previous.path);
      await _writeManifest(
        directory,
        active: previousSlot,
        previous: activeSlot,
      );
      _activeRevision = previousSlot['revision'] as String?;
      _canRollback = true;
      _verification = Future<String?>.value(destination.path);
      notifyListeners();
      return true;
    } on Object {
      if (!await destination.exists() && await temporary.exists()) {
        await temporary.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<bool> _matches(File file, int size, String digest) async {
    if (size < 0 ||
        digest.isEmpty ||
        !await file.exists() ||
        await file.length() != size) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() == digest;
  }

  Future<Map<String, Object?>?> _readManifest(Directory directory) async {
    final file = File(p.join(directory.path, '${spec.filename}.slots.json'));
    if (!await file.exists()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map<Object?, Object?>)
          .cast<String, Object?>();
    } on Object {
      return null;
    }
  }

  Future<void> _writeManifest(
    Directory directory, {
    required Map<String, Object?> active,
    required Map<String, Object?>? previous,
  }) async {
    final destination = File(
      p.join(directory.path, '${spec.filename}.slots.json'),
    );
    final staging = File('${destination.path}.part');
    await staging.writeAsString(
      jsonEncode({'schema_version': 1, 'active': active, 'previous': previous}),
      flush: true,
    );
    if (await destination.exists()) await destination.delete();
    await staging.rename(destination.path);
  }

  static Map<String, Object?>? _slot(
    Map<String, Object?>? manifest,
    String name,
  ) => switch (manifest?[name]) {
    final Map<Object?, Object?> value => value.cast<String, Object?>(),
    _ => null,
  };

  static Map<String, Object?> _specJson(WhisperModelSpec spec) => {
    'revision': spec.revision,
    'size_bytes': spec.sizeBytes,
    'sha256': spec.sha256,
  };
}
