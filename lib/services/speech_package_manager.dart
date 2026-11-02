import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'power_service.dart';
import 'storage_service.dart';

/// Model family a sherpa-onnx speech package runs.
enum SpeechPackageFamily { parakeet, moonshine }

/// One checksum-pinned file inside a [SpeechPackageSpec].
class SpeechPackageFile {
  const SpeechPackageFile({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
  });

  /// File name inside the installed package directory.
  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String sha256;
}

/// A multi-file sherpa-onnx speech model, pinned to immutable revisions.
class SpeechPackageSpec {
  const SpeechPackageSpec({
    required this.id,
    required this.family,
    required this.displayName,
    required this.summary,
    required this.license,
    required this.minimumRamGB,
    required this.files,
    this.languages = const [],
  });

  final String id;
  final SpeechPackageFamily family;
  final String displayName;
  final String summary;
  final String license;
  final double minimumRamGB;
  final List<SpeechPackageFile> files;

  /// ISO 639-1 codes the model recognizes; empty means English only.
  final List<String> languages;

  bool get englishOnly => languages.isEmpty;

  int get sizeBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);

  String get sizeLabel {
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.round()} MB';
  }

  /// Whether this model recognizes [locale] (`auto` or a BCP-47 tag).
  bool supportsLocale(String locale) {
    final language = locale.trim().toLowerCase().split(RegExp('[-_]')).first;
    if (language.isEmpty || language == 'auto') return true;
    return englishOnly ? language == 'en' : languages.contains(language);
  }
}

const _hf = 'https://huggingface.co';
const _vadRevision = 'fba88cd2e921609e7675c3aaf51e0b9b295da4bc';

/// Silero VAD (MIT) splits recordings into utterances before decoding.
const _sileroVad = SpeechPackageFile(
  name: 'silero_vad.onnx',
  downloadUrl: '$_hf/csukuangfj/vad/resolve/$_vadRevision/silero_vad.onnx',
  sizeBytes: 1807522,
  sha256: 'a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28',
);

const _parakeetRepo =
    '$_hf/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/'
    '2bda32ec70b097a55adaa07d9a7173915b43cc78';
const _moonshineTinyRepo =
    '$_hf/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/'
    'bf2b762c076d8ea61e2af0b3851c9564fb77552e';
const _moonshineBaseRepo =
    '$_hf/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/'
    '052b0798ad1bf046a140fdd4efcd9426530fa3f5';

/// Installs, verifies and removes sherpa-onnx speech packages.
///
/// A package is published only after every file matches its pinned size and
/// SHA-256; a partial or corrupt download is never visible to the runtime.
class SpeechPackageManager extends ChangeNotifier {
  SpeechPackageManager({
    required this.spec,
    Future<Directory> Function()? directoryProvider,
    HttpClient Function()? httpClientProvider,
  }) : _directoryProvider =
           directoryProvider ?? StorageService.instance.asrModelsDir,
       _httpClientProvider = httpClientProvider ?? HttpClient.new;

  /// NVIDIA Parakeet TDT 0.6B v3: 25 European languages, punctuation and
  /// casing, auto language detection.
  static const parakeetV3 = SpeechPackageSpec(
    id: 'parakeet-tdt-0.6b-v3-int8',
    family: SpeechPackageFamily.parakeet,
    displayName: 'Parakeet TDT 0.6B v3',
    summary: 'Fast and accurate · 25 European languages',
    license: 'CC-BY-4.0 · NVIDIA',
    minimumRamGB: 3,
    languages: [
      'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr', 'hr', //
      'hu', 'it', 'lt', 'lv', 'mt', 'nl', 'pl', 'pt', 'ro', 'ru', 'sk', //
      'sl', 'sv', 'uk',
    ],
    files: [
      SpeechPackageFile(
        name: 'encoder.int8.onnx',
        downloadUrl: '$_parakeetRepo/encoder.int8.onnx',
        sizeBytes: 652184281,
        sha256:
            'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
      ),
      SpeechPackageFile(
        name: 'decoder.int8.onnx',
        downloadUrl: '$_parakeetRepo/decoder.int8.onnx',
        sizeBytes: 11845275,
        sha256:
            '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
      ),
      SpeechPackageFile(
        name: 'joiner.int8.onnx',
        downloadUrl: '$_parakeetRepo/joiner.int8.onnx',
        sizeBytes: 6355277,
        sha256:
            '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
      ),
      SpeechPackageFile(
        name: 'tokens.txt',
        downloadUrl: '$_parakeetRepo/tokens.txt',
        sizeBytes: 93939,
        sha256:
            'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
      ),
      _sileroVad,
    ],
  );

  /// Useful Sensors Moonshine Tiny: smallest English model for phones.
  static const moonshineTiny = SpeechPackageSpec(
    id: 'moonshine-tiny-en-int8',
    family: SpeechPackageFamily.moonshine,
    displayName: 'Moonshine Tiny',
    summary: 'Lightest · English only',
    license: 'MIT · Useful Sensors',
    minimumRamGB: 0.5,
    files: [
      SpeechPackageFile(
        name: 'preprocess.onnx',
        downloadUrl: '$_moonshineTinyRepo/preprocess.onnx',
        sizeBytes: 6800738,
        sha256:
            'f33addce61a143460fe753b5ee5b7db255e5140b5b779c065b94f6c83ff0bf4e',
      ),
      SpeechPackageFile(
        name: 'encode.int8.onnx',
        downloadUrl: '$_moonshineTinyRepo/encode.int8.onnx',
        sizeBytes: 18249187,
        sha256:
            '8774dfba578de027ec6595c2c654a0836434489bc963a0db124a7f181f571acb',
      ),
      SpeechPackageFile(
        name: 'uncached_decode.int8.onnx',
        downloadUrl: '$_moonshineTinyRepo/uncached_decode.int8.onnx',
        sizeBytes: 53216096,
        sha256:
            '216737000dd5881a17aa043f6bbd286add33e4c3b0ae257153e2ec15438bdc41',
      ),
      SpeechPackageFile(
        name: 'cached_decode.int8.onnx',
        downloadUrl: '$_moonshineTinyRepo/cached_decode.int8.onnx',
        sizeBytes: 45264830,
        sha256:
            '2aff28bba6a03d8dcf5c9feac45462629bae37317442299f28115ad09da773f6',
      ),
      SpeechPackageFile(
        name: 'tokens.txt',
        downloadUrl: '$_moonshineTinyRepo/tokens.txt',
        sizeBytes: 436688,
        sha256:
            '1165c2aeb9f72f457a83be2d459a09054f27490acd9b41bd43794dfd25e296ea',
      ),
      _sileroVad,
    ],
  );

  /// Useful Sensors Moonshine Base: more accurate English, still compact.
  static const moonshineBase = SpeechPackageSpec(
    id: 'moonshine-base-en-int8',
    family: SpeechPackageFamily.moonshine,
    displayName: 'Moonshine Base',
    summary: 'More accurate · English only',
    license: 'MIT · Useful Sensors',
    minimumRamGB: 1,
    files: [
      SpeechPackageFile(
        name: 'preprocess.onnx',
        downloadUrl: '$_moonshineBaseRepo/preprocess.onnx',
        sizeBytes: 14077290,
        sha256:
            'ffa630d395c5ccf76f5d4954be5b882df76aaf6491519ec01fd82ea7a3819fb2',
      ),
      SpeechPackageFile(
        name: 'encode.int8.onnx',
        downloadUrl: '$_moonshineBaseRepo/encode.int8.onnx',
        sizeBytes: 50311494,
        sha256:
            '7e38770f776f2e5583a53b052936005df2ba5c833d7e09c2a5fd796b94bf73e2',
      ),
      SpeechPackageFile(
        name: 'uncached_decode.int8.onnx',
        downloadUrl: '$_moonshineBaseRepo/uncached_decode.int8.onnx',
        sizeBytes: 122120451,
        sha256:
            'c01f4b35093bcac20d352d23a75a539e772964579f9d024a90e5e6f09cae9987',
      ),
      SpeechPackageFile(
        name: 'cached_decode.int8.onnx',
        downloadUrl: '$_moonshineBaseRepo/cached_decode.int8.onnx',
        sizeBytes: 99983837,
        sha256:
            '2db74e51cedf64a8b1be3c8192e0bb5e4923af0e90bd9e87f8e8771873f8ea03',
      ),
      SpeechPackageFile(
        name: 'tokens.txt',
        downloadUrl: '$_moonshineBaseRepo/tokens.txt',
        sizeBytes: 436688,
        sha256:
            '1165c2aeb9f72f457a83be2d459a09054f27490acd9b41bd43794dfd25e296ea',
      ),
      _sileroVad,
    ],
  );

  static const moonshineSpecs = [moonshineTiny, moonshineBase];
  static const specs = [parakeetV3, ...moonshineSpecs];

  static final Map<String, SpeechPackageManager> _managers = {};
  static final ValueNotifier<String> selectedMoonshineId = ValueNotifier(
    moonshineTiny.id,
  );
  static const _moonshineSelectionKey = 'moonshine_model_id';

  static SpeechPackageManager forSpec(SpeechPackageSpec spec) =>
      _managers.putIfAbsent(spec.id, () => SpeechPackageManager(spec: spec));

  static SpeechPackageManager get parakeet => forSpec(parakeetV3);

  static SpeechPackageSpec get selectedMoonshineSpec =>
      moonshineSpecs
          .where((spec) => spec.id == selectedMoonshineId.value)
          .firstOrNull ??
      moonshineTiny;

  /// The manager for the Moonshine size chosen in Voice settings.
  static SpeechPackageManager get moonshine => forSpec(selectedMoonshineSpec);

  static Future<void> loadSelection() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_moonshineSelectionKey);
      if (moonshineSpecs.any((spec) => spec.id == stored)) {
        selectedMoonshineId.value = stored!;
      }
    } on Object catch (error) {
      debugPrint('[Speech] Moonshine selection load failed: $error');
    }
  }

  static Future<void> selectMoonshine(String id) async {
    if (!moonshineSpecs.any((spec) => spec.id == id)) return;
    selectedMoonshineId.value = id;
    await (await SharedPreferences.getInstance()).setString(
      _moonshineSelectionKey,
      id,
    );
  }

  final SpeechPackageSpec spec;
  final Future<Directory> Function() _directoryProvider;
  final HttpClient Function() _httpClientProvider;
  bool _downloading = false;
  int _receivedBytes = 0;
  String _failure = '';
  Future<String?>? _verification;
  HttpClient? _activeClient;
  bool _cancelRequested = false;

  bool get downloading => _downloading;
  int get receivedBytes => _receivedBytes;
  double get progress => _receivedBytes / spec.sizeBytes;
  String get failure => _failure;

  /// The verified package directory, or null when it is not installed.
  Future<String?> installedPath() => _verification ??= _verifyInstalled();

  Future<Directory> _packageDirectory() async =>
      Directory(p.join((await _directoryProvider()).path, spec.id));

  Future<String?> _verifyInstalled() async {
    final directory = await _packageDirectory();
    for (final file in spec.files) {
      if (!await _matches(File(p.join(directory.path, file.name)), file)) {
        return null;
      }
    }
    return directory.path;
  }

  Future<String> install() async {
    if (_downloading) throw StateError('Speech model download is in progress');
    _verification = null;
    final existing = await installedPath();
    if (existing != null) return existing;

    final root = await _directoryProvider();
    await root.create(recursive: true);
    final destination = await _packageDirectory();
    final staging = Directory('${destination.path}.part');
    _downloading = true;
    _receivedBytes = 0;
    _failure = '';
    _cancelRequested = false;
    notifyListeners();
    await PowerService.instance.startDownload(spec.displayName);
    final client = _httpClientProvider();
    _activeClient = client;
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      for (final file in spec.files) {
        await _download(client, file, File(p.join(staging.path, file.name)));
      }
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(destination.path);
      _verification = Future<String?>.value(destination.path);
      return destination.path;
    } on Object catch (error) {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (_cancelRequested) {
        _failure = '';
        throw const SpeechPackageDownloadCancelled();
      }
      _failure = error.toString();
      rethrow;
    } finally {
      client.close(force: true);
      _activeClient = null;
      _downloading = false;
      await PowerService.instance.stopDownload();
      notifyListeners();
    }
  }

  Future<void> _download(
    HttpClient client,
    SpeechPackageFile file,
    File target,
  ) async {
    final request = await client.getUrl(Uri.parse(file.downloadUrl));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '${file.name} download returned HTTP ${response.statusCode}',
      );
    }
    final sink = target.openWrite();
    var written = 0;
    try {
      await for (final chunk in response) {
        if (_cancelRequested) throw const SpeechPackageDownloadCancelled();
        written += chunk.length;
        if (written > file.sizeBytes) {
          throw StateError('${file.name} is larger than its pinned size');
        }
        sink.add(chunk);
        _receivedBytes += chunk.length;
        notifyListeners();
      }
    } finally {
      await sink.close();
    }
    if (_cancelRequested) throw const SpeechPackageDownloadCancelled();
    if (!await _matches(target, file)) {
      throw StateError('${file.name} checksum verification failed');
    }
  }

  /// Removes the package from disk.
  Future<void> delete() async {
    if (_downloading) cancelDownload();
    final directory = await _packageDirectory();
    for (final path in [directory.path, '${directory.path}.part']) {
      final entry = Directory(path);
      if (await entry.exists()) await entry.delete(recursive: true);
    }
    _verification = null;
    notifyListeners();
  }

  void cancelDownload() {
    if (!_downloading) return;
    _cancelRequested = true;
    _activeClient?.close(force: true);
  }

  static Future<bool> _matches(File file, SpeechPackageFile expected) async {
    if (!await file.exists() || await file.length() != expected.sizeBytes) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        expected.sha256;
  }
}

class SpeechPackageDownloadCancelled implements Exception {
  const SpeechPackageDownloadCancelled();

  @override
  String toString() => 'Speech model download cancelled';
}
