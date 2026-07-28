import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/catalog_entry.dart';
import '../data/installed_model.dart';
import 'storage_service.dart';
import 'power_service.dart';

typedef ModelDownloadProgress =
    void Function(String artifactId, int receivedBytes, int totalBytes);

class ModelPackageService extends ChangeNotifier {
  static final ModelPackageService instance = ModelPackageService();

  ModelPackageService({
    Future<Directory> Function()? modelsDirectoryProvider,
    HttpClient Function()? httpClientProvider,
  }) : _modelsDirectoryProvider =
           modelsDirectoryProvider ?? StorageService.instance.modelsDir,
       _httpClientProvider = httpClientProvider ?? HttpClient.new;

  final Future<Directory> Function() _modelsDirectoryProvider;
  final HttpClient Function() _httpClientProvider;
  final Map<String, InstalledModel> _installed = {};
  final Map<String, InstalledModel> _previous = {};
  final Set<String> _downloading = {};
  final Set<String> _cancelled = {};
  final Map<String, HttpClient> _activeClients = {};
  final Map<String, int> _receivedBytes = {};
  final Map<String, int> _totalBytes = {};

  List<InstalledModel> get installed =>
      List.unmodifiable(_installed.values.toList());
  int get downloadedBytes => _installed.values.fold(
    0,
    (sum, record) =>
        sum + record.files.fold(0, (fileSum, file) => fileSum + file.sizeBytes),
  );

  bool isDownloading(String variantId) => _downloading.contains(variantId);
  int receivedBytesOf(String variantId) => _receivedBytes[variantId] ?? 0;
  int totalBytesOf(String variantId) => _totalBytes[variantId] ?? 0;
  double progressOf(String variantId) {
    final total = totalBytesOf(variantId);
    return total <= 0 ? 0 : receivedBytesOf(variantId) / total;
  }

  InstalledModel? byVariantId(String variantId) => _installed[variantId];

  bool hasUpdate(ModelVariant variant) {
    final installed = _installed[variant.id];
    if (installed == null || !installed.runnable) return false;
    final declared = {
      for (final artifact in variant.files.where((file) => file.required))
        artifact.id: artifact.sha256.toLowerCase(),
    };
    final local = {
      for (final file in installed.files)
        file.artifactId: file.sha256.toLowerCase(),
    };
    return declared.isNotEmpty &&
        declared.values.every((digest) => digest.isNotEmpty) &&
        (declared.length != local.length ||
            declared.entries.any((entry) => local[entry.key] != entry.value));
  }

  bool canRollback(String variantId) => _previous.containsKey(variantId);

  InstalledModel? runnableForModelId(String modelId) => _installed.values
      .where((record) => record.modelId == modelId && record.runnable)
      .firstOrNull;

  bool isModelRunnable(String modelId) => runnableForModelId(modelId) != null;

  List<InstalledModel> runnableVariantsForModelId(String modelId) => _installed
      .values
      .where((record) => record.modelId == modelId && record.runnable)
      .toList(growable: false);

  Future<void> loadIndex() async {
    _installed.clear();
    _previous.clear();
    final index = await _indexFile;
    if (!await index.exists()) {
      notifyListeners();
      return;
    }
    try {
      final json =
          jsonDecode(await index.readAsString()) as Map<String, Object?>;
      final records = json['installed'] as List<Object?>? ?? const [];
      for (final value in records) {
        final record = InstalledModel.fromJson(
          (value as Map<Object?, Object?>).cast<String, Object?>(),
        );
        if (record.variantId.isNotEmpty) _installed[record.variantId] = record;
      }
      final previousRecords = json['previous'] as List<Object?>? ?? const [];
      for (final value in previousRecords) {
        final record = InstalledModel.fromJson(
          (value as Map<Object?, Object?>).cast<String, Object?>(),
        );
        if (record.variantId.isNotEmpty) _previous[record.variantId] = record;
      }
    } on Object {
      // A corrupt index never makes an unverified package runnable.
      _installed.clear();
      _previous.clear();
    } finally {
      notifyListeners();
    }
  }

  Future<InstalledModel> downloadVariant(
    ModelVariant variant, {
    ModelDownloadProgress? onProgress,
    bool replaceExisting = false,
  }) async {
    _validateVariant(variant);
    if (_downloading.contains(variant.id)) {
      throw ModelPackageException(
        'download_in_progress',
        '${variant.id} is already downloading',
      );
    }
    _downloading.add(variant.id);
    _cancelled.remove(variant.id);
    _receivedBytes[variant.id] = 0;
    _totalBytes[variant.id] = variant.sizeBytes;
    notifyListeners();
    await PowerService.instance.startDownload(variant.modelId);
    Directory? staging;
    Directory? displaced;
    InstalledModel? displacedRecord;
    var activated = false;
    try {
      final models = await _modelsDirectoryProvider();
      await models.create(recursive: true);
      final finalDirectory = Directory(
        p.join(models.path, _safeName(variant.id)),
      );
      final existing = _installed[variant.id];
      displacedRecord = existing;
      if (!replaceExisting &&
          existing?.runnable == true &&
          await finalDirectory.exists()) {
        return existing!;
      }

      staging = Directory(
        p.join(
          models.path,
          '.${_safeName(variant.id)}.${const Uuid().v4()}.part',
        ),
      );
      await staging.create(recursive: true);
      final files = <InstalledModelFile>[];
      final requiredArtifacts = variant.files
          .where((file) => file.required)
          .toList(growable: false);
      final packageBytes = requiredArtifacts.fold<int>(
        0,
        (sum, artifact) => sum + (artifact.sizeBytes ?? 0),
      );
      var completedBytes = 0;
      for (final artifact in requiredArtifacts) {
        final destination = File(
          p.join(staging.path, _safeFilename(artifact.filename)),
        );
        await _downloadArtifact(
          variant.id,
          artifact,
          destination,
          onProgress: (artifactId, received, total) {
            final aggregateReceived = completedBytes + received;
            final aggregateTotal = packageBytes > 0
                ? packageBytes
                : completedBytes + total;
            _receivedBytes[variant.id] = aggregateReceived;
            _totalBytes[variant.id] = aggregateTotal;
            notifyListeners();
            onProgress?.call(artifactId, aggregateReceived, aggregateTotal);
          },
        );
        final verified = await _verifyArtifact(artifact, destination);
        files.add(verified);
        completedBytes += verified.sizeBytes;
      }
      await _writePackageManifest(staging, variant, files);

      if (await finalDirectory.exists() && !replaceExisting) {
        throw ModelPackageException(
          'variant_already_exists',
          'A non-runnable package already exists for ${variant.id}',
        );
      }
      if (await finalDirectory.exists()) {
        displaced = Directory('${finalDirectory.path}.previous');
        if (await displaced.exists()) {
          await displaced.delete(recursive: true);
        }
        await finalDirectory.rename(displaced.path);
      }
      try {
        await staging.rename(finalDirectory.path);
        activated = true;
      } on Object {
        if (displaced != null &&
            await displaced.exists() &&
            !await finalDirectory.exists()) {
          await displaced.rename(finalDirectory.path);
        }
        rethrow;
      }
      final now = DateTime.now().toUtc();
      final installed = InstalledModel(
        modelId: variant.modelId,
        variantId: variant.id,
        format: variant.format,
        backends: variant.compatibleBackends,
        installedAt: now,
        verifiedAt: now,
        files: files,
        runnable: true,
      );
      if (replaceExisting && existing != null) {
        _previous[variant.id] = existing;
      }
      _installed[variant.id] = installed;
      await _saveIndex();
      notifyListeners();
      return installed;
    } on Object {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (replaceExisting && activated && displaced != null) {
        final models = await _modelsDirectoryProvider();
        final active = Directory(p.join(models.path, _safeName(variant.id)));
        if (await active.exists()) await active.delete(recursive: true);
        if (await displaced.exists()) {
          await displaced.rename(active.path);
        }
        if (displacedRecord != null) {
          _installed[variant.id] = displacedRecord;
        }
      }
      rethrow;
    } finally {
      _downloading.remove(variant.id);
      if (_cancelled.remove(variant.id)) {
        _receivedBytes.remove(variant.id);
        _totalBytes.remove(variant.id);
      }
      await PowerService.instance.stopDownload();
      notifyListeners();
    }
  }

  Future<void> cancelDownload(String variantId) async {
    if (!_downloading.contains(variantId)) return;
    _cancelled.add(variantId);
    _activeClients.remove(variantId)?.close(force: true);
    notifyListeners();
  }

  Future<InstalledModel> updateVariant(ModelVariant variant) =>
      downloadVariant(variant, replaceExisting: true);

  Future<bool> rollback(String variantId) async {
    final previousRecord = _previous[variantId];
    final activeRecord = _installed[variantId];
    if (previousRecord == null || activeRecord == null) return false;
    final models = await _modelsDirectoryProvider();
    final active = Directory(p.join(models.path, _safeName(variantId)));
    final previous = Directory('${active.path}.previous');
    if (!await active.exists() || !await previous.exists()) return false;
    final temporary = Directory('${active.path}.rollback-part');
    if (await temporary.exists()) await temporary.delete(recursive: true);
    await active.rename(temporary.path);
    try {
      await previous.rename(active.path);
      await temporary.rename(previous.path);
      _installed[variantId] = previousRecord;
      _previous[variantId] = activeRecord;
      await _saveIndex();
      notifyListeners();
      return true;
    } on Object {
      if (!await active.exists() && await temporary.exists()) {
        await temporary.rename(active.path);
      }
      rethrow;
    }
  }

  Future<String?> packagePath(String variantId) async {
    final record = _installed[variantId];
    if (record == null || !record.runnable) return null;
    final models = await _modelsDirectoryProvider();
    final directory = Directory(p.join(models.path, _safeName(variantId)));
    if (!await directory.exists()) return null;
    if (record.format.toLowerCase() == 'gguf') {
      final modelFile = record.files.firstOrNull;
      if (modelFile == null) return null;
      final file = File(p.join(directory.path, modelFile.relativePath));
      return await file.exists() ? file.path : null;
    }
    return directory.path;
  }

  Future<void> markUnrunnable(String variantId, String failureCode) async {
    final record = _installed[variantId];
    if (record == null) return;
    _installed[variantId] = InstalledModel(
      modelId: record.modelId,
      variantId: record.variantId,
      format: record.format,
      backends: record.backends,
      installedAt: record.installedAt,
      verifiedAt: record.verifiedAt,
      files: record.files,
      runnable: false,
      failureCode: failureCode,
    );
    await _saveIndex();
    notifyListeners();
  }

  Future<InstalledModel> verify(ModelVariant variant) async {
    final record = _installed[variant.id];
    if (record == null) {
      throw ModelPackageException(
        'not_installed',
        '${variant.id} is not installed',
      );
    }
    final models = await _modelsDirectoryProvider();
    final directory = Directory(p.join(models.path, _safeName(variant.id)));
    final verifiedFiles = <InstalledModelFile>[];
    for (final artifact in variant.files.where((file) => file.required)) {
      final file = File(
        p.join(directory.path, _safeFilename(artifact.filename)),
      );
      verifiedFiles.add(await _verifyArtifact(artifact, file));
    }
    final verified = InstalledModel(
      modelId: record.modelId,
      variantId: record.variantId,
      format: record.format,
      backends: record.backends,
      installedAt: record.installedAt,
      verifiedAt: DateTime.now().toUtc(),
      files: verifiedFiles,
      runnable: true,
    );
    _installed[variant.id] = verified;
    await _saveIndex();
    notifyListeners();
    return verified;
  }

  Future<void> _downloadArtifact(
    String variantId,
    Artifact artifact,
    File destination, {
    ModelDownloadProgress? onProgress,
  }) async {
    final client = _httpClientProvider();
    _activeClients[variantId] = client;
    IOSink? sink;
    try {
      if (_cancelled.contains(variantId)) {
        throw const ModelPackageException(
          'download_cancelled',
          'Model download was cancelled',
        );
      }
      final request = await client.getUrl(Uri.parse(artifact.downloadUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ModelPackageException(
          'http_error',
          '${artifact.id}: HTTP ${response.statusCode}',
        );
      }
      final expectedTotal =
          artifact.sizeBytes ?? response.headers.contentLength;
      var received = 0;
      sink = destination.openWrite();
      await for (final chunk in response) {
        if (_cancelled.contains(variantId)) {
          throw const ModelPackageException(
            'download_cancelled',
            'Model download was cancelled',
          );
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(artifact.id, received, expectedTotal);
      }
      await sink.close();
      sink = null;
    } on Object {
      if (_cancelled.contains(variantId)) {
        throw const ModelPackageException(
          'download_cancelled',
          'Model download was cancelled',
        );
      }
      rethrow;
    } finally {
      await sink?.close();
      if (identical(_activeClients[variantId], client)) {
        _activeClients.remove(variantId);
      }
      client.close(force: true);
    }
  }

  Future<InstalledModelFile> _verifyArtifact(
    Artifact artifact,
    File file,
  ) async {
    if (!await file.exists()) {
      throw ModelPackageException(
        'artifact_missing',
        '${artifact.id} was not downloaded',
      );
    }
    if (artifact.sha256.isEmpty) {
      throw ModelPackageException(
        'checksum_missing',
        '${artifact.id} has no SHA-256 checksum',
      );
    }
    final size = await file.length();
    if (artifact.sizeBytes != null && artifact.sizeBytes != size) {
      throw ModelPackageException(
        'size_mismatch',
        '${artifact.id} expected ${artifact.sizeBytes} bytes, received $size',
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    final actual = digest.toString();
    if (actual.toLowerCase() != artifact.sha256.toLowerCase()) {
      throw ModelPackageException(
        'checksum_mismatch',
        '${artifact.id} failed SHA-256 verification',
      );
    }
    return InstalledModelFile(
      artifactId: artifact.id,
      relativePath: _safeFilename(artifact.filename),
      sizeBytes: size,
      sha256: actual,
    );
  }

  Future<void> _writePackageManifest(
    Directory directory,
    ModelVariant variant,
    List<InstalledModelFile> files,
  ) {
    return File(p.join(directory.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'model_id': variant.modelId,
        'variant_id': variant.id,
        'format': variant.format,
        'backends': variant.compatibleBackends,
        'files': files.map((file) => file.toJson()).toList(),
      }),
      flush: true,
    );
  }

  Future<File> get _indexFile async =>
      File(p.join((await _modelsDirectoryProvider()).path, 'installed.json'));

  Future<void> _saveIndex() async {
    final file = await _indexFile;
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.part');
    await staging.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'installed': _installed.values
            .map((record) => record.toJson())
            .toList(),
        'previous': _previous.values.map((record) => record.toJson()).toList(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await staging.rename(file.path);
  }

  static void _validateVariant(ModelVariant variant) {
    if (variant.id.isEmpty || variant.modelId.isEmpty) {
      throw const ModelPackageException(
        'invalid_variant',
        'Model and variant IDs are required',
      );
    }
    final required = variant.files.where((file) => file.required).toList();
    if (required.isEmpty) {
      throw const ModelPackageException(
        'no_artifacts',
        'The variant has no required artifacts',
      );
    }
    for (final artifact in required) {
      if (artifact.id.isEmpty ||
          artifact.filename.isEmpty ||
          artifact.downloadUrl.isEmpty) {
        throw ModelPackageException(
          'invalid_artifact',
          'Required artifact ${artifact.id} is incomplete',
        );
      }
      _safeFilename(artifact.filename);
    }
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

  static String _safeFilename(String value) {
    final name = p.basename(value);
    if (name != value || name == '.' || name == '..') {
      throw ModelPackageException(
        'unsafe_filename',
        'Artifact filename must not contain a path: $value',
      );
    }
    return name;
  }
}

class ModelPackageException implements Exception {
  const ModelPackageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
