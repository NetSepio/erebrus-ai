import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/imported_model.dart';
import 'gguf_inspector.dart';
import 'storage_service.dart';

class ImportedModelException implements Exception {
  const ImportedModelException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class ImportedModelService extends ChangeNotifier {
  ImportedModelService({Future<Directory> Function()? importsDirectoryProvider})
    : _importsDirectoryProvider =
          importsDirectoryProvider ?? StorageService.instance.importedModelsDir;

  static final ImportedModelService instance = ImportedModelService();

  final Future<Directory> Function() _importsDirectoryProvider;
  final Map<String, ImportedModel> _models = {};
  final Map<String, FileSystemEntity> _activeReferences = {};
  final GgufInspector _ggufInspector = const GgufInspector();
  bool _importing = false;
  bool _cancelRequested = false;
  int _copiedBytes = 0;
  int _copyTotalBytes = 0;

  List<ImportedModel> get models => List.unmodifiable(_models.values);
  int get storedBytes => _models.values
      .where((model) => !model.reference)
      .fold(0, (total, model) => total + model.sizeBytes);
  bool get isImporting => _importing;
  double get importProgress =>
      _copyTotalBytes <= 0 ? 0 : (_copiedBytes / _copyTotalBytes).clamp(0, 1);
  int get copiedBytes => _copiedBytes;
  int get copyTotalBytes => _copyTotalBytes;

  ImportedModel? byId(String id) => _models[id];
  bool contains(String id) => _models.containsKey(id);

  Future<void> load() async {
    await _releaseReferences();
    _models.clear();
    final index = await _indexFile;
    if (!await index.exists()) {
      notifyListeners();
      return;
    }
    try {
      final payload = jsonDecode(await index.readAsString());
      final records = payload is Map ? payload['models'] : null;
      if (records is List) {
        for (final value in records.whereType<Map>()) {
          final model = ImportedModel.fromJson(value.cast<String, Object?>());
          if (model.id.isEmpty || model.path.isEmpty) continue;
          final resolved = await _resolve(model);
          if (resolved == null) continue;
          _models[model.id] = resolved;
        }
      }
    } on Object catch (error) {
      debugPrint('[Import] could not load model index: $error');
      _models.clear();
    } finally {
      notifyListeners();
    }
  }

  Future<ImportedModelDraft> inspectGguf(String path) =>
      _ggufInspector.inspect(path);

  Future<ImportedModelDraft> inspectMlxDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw const ImportedModelException(
        'missing_directory',
        'The selected MLX directory is missing.',
      );
    }
    final configFile = File(p.join(path, 'config.json'));
    if (!await configFile.exists()) {
      throw const ImportedModelException(
        'missing_config',
        'An MLX package must contain config.json.',
      );
    }
    final tokenizerPresent =
        await File(p.join(path, 'tokenizer.json')).exists() ||
        await File(p.join(path, 'tokenizer_config.json')).exists() ||
        await File(p.join(path, 'tokenizer.model')).exists();
    if (!tokenizerPresent) {
      throw const ImportedModelException(
        'missing_tokenizer',
        'An MLX package must contain tokenizer.json, tokenizer_config.json, or tokenizer.model.',
      );
    }
    final files = await directory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    if (!files.any((file) => file.path.endsWith('.safetensors'))) {
      throw const ImportedModelException(
        'missing_weights',
        'An MLX package must contain SafeTensors model weights.',
      );
    }
    final config = jsonDecode(await configFile.readAsString());
    if (config is! Map) {
      throw const ImportedModelException(
        'invalid_config',
        'The MLX config.json is invalid.',
      );
    }
    var bytes = 0;
    for (final file in files) {
      bytes += await file.length();
    }
    final rawName = config['_name_or_path']?.toString().trim() ?? '';
    final architecture =
        config['model_type']?.toString() ??
        ((config['architectures'] is List &&
                (config['architectures'] as List).isNotEmpty)
            ? (config['architectures'] as List).first.toString()
            : '');
    final quantization = _mlxQuantization(config);
    final rawParameters = config['num_parameters'];
    return ImportedModelDraft(
      sourcePath: path,
      name: rawName.isEmpty ? p.basename(p.normalize(path)) : rawName,
      format: 'mlx',
      sizeBytes: bytes,
      architecture: architecture,
      quantization: quantization,
      parameterB: rawParameters is num
          ? rawParameters.toDouble() / 1000000000
          : 0,
    );
  }

  Future<ImportedModel> import(
    ImportedModelDraft draft, {
    required bool copyIntoApp,
  }) async {
    if (_importing) {
      throw const ImportedModelException(
        'import_in_progress',
        'Another model import is already in progress.',
      );
    }
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw const ImportedModelException(
        'missing_name',
        'Give the imported model a name.',
      );
    }
    if (draft.parameterB < 0 || !draft.parameterB.isFinite) {
      throw const ImportedModelException(
        'invalid_parameters',
        'Parameter count must be zero or greater.',
      );
    }
    if (!copyIntoApp && !Platform.isMacOS) {
      throw const ImportedModelException(
        'reference_unsupported',
        'Referenced imports are supported on macOS only.',
      );
    }
    final normalizedSource = p.normalize(p.absolute(draft.sourcePath));
    if (_models.values.any(
      (model) => p.normalize(p.absolute(model.sourcePath)) == normalizedSource,
    )) {
      throw const ImportedModelException(
        'already_imported',
        'This model location is already imported.',
      );
    }

    final id = 'local-${const Uuid().v4()}';
    String path;
    String? bookmark;
    if (copyIntoApp) {
      _importing = true;
      _cancelRequested = false;
      _copiedBytes = 0;
      _copyTotalBytes = draft.sizeBytes;
      notifyListeners();
      Directory? target;
      try {
        target = Directory(
          p.join((await _importsDirectoryProvider()).path, id),
        );
        await target.create(recursive: true);
        if (draft.format == 'gguf') {
          final source = File(draft.sourcePath);
          path = p.join(target.path, 'model.gguf');
          await _copyFile(source, File(path));
        } else {
          path = p.join(target.path, 'mlx');
          await _copyDirectory(Directory(draft.sourcePath), Directory(path));
        }
      } on Object {
        if (target != null && await target.exists()) {
          await target.delete(recursive: true);
        }
        rethrow;
      } finally {
        _importing = false;
        _cancelRequested = false;
        notifyListeners();
      }
    } else {
      final entity = draft.format == 'mlx'
          ? Directory(draft.sourcePath)
          : File(draft.sourcePath);
      try {
        bookmark = await SecureBookmarks().bookmark(entity);
        final started = await SecureBookmarks()
            .startAccessingSecurityScopedResource(entity);
        if (!started) {
          throw const ImportedModelException(
            'reference_denied',
            'macOS did not grant persistent access to this model.',
          );
        }
        _activeReferences[id] = entity;
        path = entity.absolute.path;
      } on ImportedModelException {
        rethrow;
      } on Object catch (error) {
        throw ImportedModelException(
          'bookmark_failed',
          'Could not retain access to this model: $error',
        );
      }
    }

    final model = ImportedModel(
      id: id,
      name: name,
      format: draft.format,
      path: path,
      sourcePath: normalizedSource,
      sizeBytes: draft.sizeBytes,
      importedAt: DateTime.now().toUtc(),
      architecture: draft.architecture.trim(),
      quantization: draft.quantization.trim(),
      parameterB: draft.parameterB,
      reference: !copyIntoApp,
      bookmark: bookmark,
    );
    _models[id] = model;
    try {
      await _save();
    } on Object {
      _models.remove(id);
      final active = _activeReferences.remove(id);
      if (active != null) {
        try {
          await SecureBookmarks().stopAccessingSecurityScopedResource(active);
        } on Object catch (error) {
          debugPrint('[Import] could not release ${active.path}: $error');
        }
      }
      if (copyIntoApp) {
        final target = Directory(
          p.join((await _importsDirectoryProvider()).path, id),
        );
        if (await target.exists()) await target.delete(recursive: true);
      }
      rethrow;
    }
    notifyListeners();
    return model;
  }

  void cancelImport() {
    if (!_importing) return;
    _cancelRequested = true;
    notifyListeners();
  }

  Future<bool> remove(String id) async {
    final model = _models.remove(id);
    if (model == null) return false;
    try {
      await _save();
    } on Object {
      _models[id] = model;
      rethrow;
    }
    final active = _activeReferences.remove(id);
    if (active != null) {
      try {
        await SecureBookmarks().stopAccessingSecurityScopedResource(active);
      } on Object catch (error) {
        debugPrint('[Import] could not release ${active.path}: $error');
      }
    }
    if (!model.reference) {
      final root = await _importsDirectoryProvider();
      final target = Directory(p.join(root.path, id));
      try {
        if (await target.exists()) await target.delete(recursive: true);
      } on Object {
        _models[id] = model;
        await _save();
        rethrow;
      }
    }
    notifyListeners();
    return true;
  }

  Future<ImportedModel?> _resolve(ImportedModel model) async {
    if (!model.reference) {
      final exists = model.format == 'mlx'
          ? await Directory(model.path).exists()
          : await File(model.path).exists();
      return exists ? model : null;
    }
    if (!Platform.isMacOS || model.bookmark?.isNotEmpty != true) return null;
    try {
      final entity = await SecureBookmarks().resolveBookmark(
        model.bookmark!,
        isDirectory: model.format == 'mlx',
      );
      if (!await entity.exists()) return null;
      final started = await SecureBookmarks()
          .startAccessingSecurityScopedResource(entity);
      if (!started) return null;
      _activeReferences[model.id] = entity;
      return ImportedModel(
        id: model.id,
        name: model.name,
        format: model.format,
        path: entity.path,
        sourcePath: model.sourcePath,
        sizeBytes: model.sizeBytes,
        importedAt: model.importedAt,
        architecture: model.architecture,
        quantization: model.quantization,
        parameterB: model.parameterB,
        reference: true,
        bookmark: model.bookmark,
      );
    } on Object catch (error) {
      debugPrint('[Import] could not restore ${model.name}: $error');
      return null;
    }
  }

  Future<void> _releaseReferences() async {
    if (!Platform.isMacOS) {
      _activeReferences.clear();
      return;
    }
    for (final entity in _activeReferences.values) {
      try {
        await SecureBookmarks().stopAccessingSecurityScopedResource(entity);
      } on Object catch (error) {
        debugPrint('[Import] could not release ${entity.path}: $error');
      }
    }
    _activeReferences.clear();
  }

  Future<File> get _indexFile async =>
      File(p.join((await _importsDirectoryProvider()).path, 'index.json'));

  Future<void> _save() async {
    final file = await _indexFile;
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.part');
    await staging.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'models': _models.values.map((model) => model.toJson()).toList(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await staging.rename(file.path);
  }

  static String _mlxQuantization(Map config) {
    final quantization = config['quantization'];
    if (quantization is Map) {
      final bits = quantization['bits'];
      final group = quantization['group_size'];
      if (bits != null) {
        return group == null ? '${bits}bit' : '${bits}bit g$group';
      }
    }
    final bits = config['quantization_bits'];
    return bits == null ? '' : '${bits}bit';
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      _throwIfCancelled();
      final name = p.basename(entity.path);
      final destination = p.join(target.path, name);
      if (entity is File) {
        await _copyFile(entity, File(destination));
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
      }
    }
  }

  Future<void> _copyFile(File source, File target) async {
    await target.parent.create(recursive: true);
    final output = await target.open(mode: FileMode.write);
    try {
      await for (final chunk in source.openRead()) {
        _throwIfCancelled();
        await output.writeFrom(chunk);
        _copiedBytes += chunk.length;
        notifyListeners();
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const ImportedModelException(
        'import_cancelled',
        'Model import cancelled.',
      );
    }
  }
}
