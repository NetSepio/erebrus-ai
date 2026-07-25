import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage_service.dart';

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

  bool get downloading => _downloading;
  int get receivedBytes => _receivedBytes;
  double get progress => _receivedBytes / spec.sizeBytes;
  String get failure => _failure;

  Future<String?> installedPath() => _verification ??= _verifyInstalledPath();

  Future<String?> _verifyInstalledPath() async {
    final directory = await _directoryProvider();
    final file = File(p.join(directory.path, spec.filename));
    if (!await file.exists() || await file.length() != spec.sizeBytes) {
      return null;
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != spec.sha256) return null;
    return file.path;
  }

  Future<String> install() async {
    final existing = await installedPath();
    if (existing != null) return existing;
    if (_downloading) throw StateError('Whisper model download is in progress');
    _downloading = true;
    _receivedBytes = 0;
    _failure = '';
    notifyListeners();

    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, spec.filename));
    final staging = File('${destination.path}.part');
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
      if (await destination.exists()) await destination.delete();
      await staging.rename(destination.path);
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
      notifyListeners();
    }
  }
}
