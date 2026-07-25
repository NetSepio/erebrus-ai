import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/catalog_entry.dart';
import '../data/installed_model.dart';
import 'storage_service.dart';

typedef ModelDownloadProgress =
    void Function(String artifactId, int receivedBytes, int totalBytes);

class ModelPackageService {
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

  List<InstalledModel> get installed =>
      List.unmodifiable(_installed.values.toList());

  InstalledModel? byVariantId(String variantId) => _installed[variantId];

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
    final index = await _indexFile;
    if (!await index.exists()) return;
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
    } on Object {
      // A corrupt index never makes an unverified package runnable.
      _installed.clear();
    }
  }

  Future<InstalledModel> downloadVariant(
    ModelVariant variant, {
    ModelDownloadProgress? onProgress,
  }) async {
    _validateVariant(variant);
    final models = await _modelsDirectoryProvider();
    await models.create(recursive: true);
    final finalDirectory = Directory(
      p.join(models.path, _safeName(variant.id)),
    );
    final existing = _installed[variant.id];
    if (existing?.runnable == true && await finalDirectory.exists()) {
      return existing!;
    }

    final staging = Directory(
      p.join(
        models.path,
        '.${_safeName(variant.id)}.${const Uuid().v4()}.part',
      ),
    );
    await staging.create(recursive: true);
    try {
      final files = <InstalledModelFile>[];
      for (final artifact in variant.files.where((file) => file.required)) {
        final destination = File(
          p.join(staging.path, _safeFilename(artifact.filename)),
        );
        await _downloadArtifact(artifact, destination, onProgress: onProgress);
        files.add(await _verifyArtifact(artifact, destination));
      }
      await _writePackageManifest(staging, variant, files);

      if (await finalDirectory.exists()) {
        throw ModelPackageException(
          'variant_already_exists',
          'A non-runnable package already exists for ${variant.id}',
        );
      }
      await staging.rename(finalDirectory.path);
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
      _installed[variant.id] = installed;
      await _saveIndex();
      return installed;
    } on Object {
      if (await staging.exists()) await staging.delete(recursive: true);
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
    return verified;
  }

  Future<void> _downloadArtifact(
    Artifact artifact,
    File destination, {
    ModelDownloadProgress? onProgress,
  }) async {
    final client = _httpClientProvider();
    IOSink? sink;
    try {
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
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(artifact.id, received, expectedTotal);
      }
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
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
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'installed': _installed.values
            .map((record) => record.toJson())
            .toList(),
      }),
      flush: true,
    );
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
