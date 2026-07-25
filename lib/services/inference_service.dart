import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/catalog_entry.dart';
import '../data/installed_model.dart';
import 'device_info_service.dart';
import 'inference_contract.dart';
import 'inference_coordinator.dart';
import 'llama_cpp_backend.dart';
import 'model_download_service.dart';
import 'model_package_service.dart';
import 'mlx_backend.dart';

/// Cross-platform GGUF inference backed by llama.cpp.
///
/// The package runs native inference in its own worker isolate. Our vendored
/// patch buffers UTF-8 sequences split across token pieces, which is required
/// for multilingual models on mobile.
class InferenceService extends ChangeNotifier {
  InferenceService._() {
    final platform = DeviceInfoService.detect().platform;
    _mlx = MlxBackend(platform: platform);
    _llamaCpp = LlamaCppBackend(platform: platform);
    _coordinator = InferenceCoordinator([_mlx, _llamaCpp]);
  }

  static final InferenceService instance = InferenceService._();

  late final MlxBackend _mlx;
  late final LlamaCppBackend _llamaCpp;
  late final InferenceCoordinator _coordinator;
  String? _activeModelId;
  bool _generating = false;
  double? _currentTokensPerSecond;
  double? _lastTokensPerSecond;
  bool _lastOutputWasTruncated = false;

  String? get activeModelId => _activeModelId;
  bool get isGenerating => _generating;
  double? get currentTokensPerSecond => _currentTokensPerSecond;
  double? get lastTokensPerSecond => _lastTokensPerSecond;
  bool get lastOutputWasTruncated => _lastOutputWasTruncated;

  Stream<String> generate({
    required String modelId,
    required String prompt,
    String systemPrompt = '',
    int maxOutputTokens = 768,
    double temperature = 0.7,
    double topP = 0.9,
    double repeatPenalty = 1.1,
    List<String> stop = const [],
  }) async* {
    if (modelId.isEmpty) {
      throw const InferenceException('Select a downloaded model first.');
    }
    if (_generating) {
      throw const InferenceException(
        'The local model is already generating a response.',
      );
    }

    final profile = DeviceInfoService.detect();
    final installed = ModelPackageService.instance.runnableVariantsForModelId(
      modelId,
    );
    final legacyPath = await ModelDownloadService.instance.modelPath(modelId);
    if (installed.isEmpty && legacyPath == null) {
      throw InferenceException(
        'Model "$modelId" is not downloaded. Download it from Models first.',
      );
    }

    final mobile = Platform.isAndroid || Platform.isIOS;
    final contextSize = mobile ? 2048 : 8192;
    final outputTokens = mobile
        ? maxOutputTokens.clamp(1, contextSize - 256)
        : maxOutputTokens;

    _activeModelId = modelId;
    _generating = true;
    _currentTokensPerSecond = null;
    _lastOutputWasTruncated = false;
    notifyListeners();
    debugPrint(
      '[Inference] starting $modelId (ctx=$contextSize, max=$outputTokens)',
    );

    try {
      final plans = <InferenceExecutionPlan>[];
      final ordered = [...installed]
        ..sort(
          (left, right) =>
              _backendPriority(left).compareTo(_backendPriority(right)),
        );
      for (final record in ordered) {
        final packagePath = await ModelPackageService.instance.packagePath(
          record.variantId,
        );
        if (packagePath == null) continue;
        final variant = _variantFromInstalled(record, profile.platform);
        for (final backend in _orderedBackends(record)) {
          plans.add(
            InferenceExecutionPlan(
              backend: backend,
              loadRequest: InferenceLoadRequest(
                variant: variant,
                packagePath: packagePath,
                contextSize: contextSize,
                gpuLayerCount: 0,
              ),
            ),
          );
        }
      }
      if (legacyPath != null &&
          !plans.any(
            (plan) =>
                plan.backend == BackendKind.llamaCpp &&
                plan.loadRequest.packagePath == legacyPath,
          )) {
        plans.add(
          InferenceExecutionPlan(
            backend: BackendKind.llamaCpp,
            loadRequest: InferenceLoadRequest(
              variant: _legacyVariant(modelId, legacyPath, profile.platform),
              packagePath: legacyPath,
              contextSize: contextSize,
              gpuLayerCount: 0,
            ),
          ),
        );
      }
      final events = _coordinator.generate(
        plans: plans,
        request: InferenceRequest(
          messages: [
            if (systemPrompt.trim().isNotEmpty)
              InferenceMessage(role: 'system', content: systemPrompt.trim()),
            InferenceMessage(role: 'user', content: prompt),
          ],
          maxOutputTokens: outputTokens,
          sampling: InferenceSampling(
            temperature: temperature,
            topP: topP,
            repeatPenalty: repeatPenalty,
          ),
          stopSequences: stop,
        ),
      );

      var tokenCount = 0;
      await for (final event in events) {
        switch (event) {
          case InferenceLoadCompleted(:final backend, :final loadDuration):
            debugPrint(
              '[Inference] ${backend.catalogName} ready in '
              '${loadDuration.inMilliseconds} ms',
            );
          case InferenceToken(:final text):
            tokenCount++;
            if (text.isNotEmpty) yield text;
          case InferenceMetrics(:final decodeTokensPerSecond):
            if (decodeTokensPerSecond != null) {
              _currentTokensPerSecond = decodeTokensPerSecond;
              notifyListeners();
            }
          case InferenceFailure(:final message):
            throw InferenceException(_friendlyError(message));
          case InferenceCompleted(:final reason):
            _lastTokensPerSecond = _currentTokensPerSecond;
            _lastOutputWasTruncated = reason == InferenceFinishReason.length;
            debugPrint('[Inference] generation completed ($tokenCount tokens)');
        }
      }
    } catch (error) {
      if (error is InferenceException) rethrow;
      throw InferenceException(_friendlyError(error.toString()));
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  Future<void> cancel() => _coordinator.cancel();

  Future<void> unload() async {
    await _coordinator.unload();
    _activeModelId = null;
    notifyListeners();
  }

  static String _friendlyError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('memory') || lower.contains('allocation')) {
      return 'This model does not fit in available memory. Try a smaller or more heavily quantized GGUF model.';
    }
    if (lower.contains('library') || lower.contains('dynamiclibrary')) {
      return 'The llama.cpp runtime is unavailable for this device build. Reinstall the app with the native runtime included.';
    }
    return 'Generation failed: $message';
  }

  static int _backendPriority(InstalledModel model) =>
      model.backends.any((backend) => backend.toLowerCase() == 'mlx') ? 0 : 1;

  static List<BackendKind> _orderedBackends(InstalledModel model) {
    final result = <BackendKind>[];
    for (final kind in const [BackendKind.mlx, BackendKind.llamaCpp]) {
      if (model.backends.any(
        (backend) => backend.toLowerCase() == kind.catalogName.toLowerCase(),
      )) {
        result.add(kind);
      }
    }
    return result;
  }

  static ModelVariant _variantFromInstalled(
    InstalledModel model,
    String platform,
  ) => ModelVariant(
    id: model.variantId,
    modelId: model.modelId,
    format: model.format,
    quantization: '',
    files: model.files
        .map(
          (file) => Artifact(
            id: file.artifactId,
            role: 'model',
            format: model.format,
            quantization: '',
            filename: file.relativePath,
            repositoryId: '',
            downloadUrl: '',
            backend: model.backends.firstOrNull ?? '',
          ),
        )
        .toList(growable: false),
    platforms: [platform],
    compatibleBackends: model.backends,
  );

  static ModelVariant _legacyVariant(
    String modelId,
    String path,
    String platform,
  ) => ModelVariant(
    id: modelId,
    modelId: modelId,
    format: 'gguf',
    quantization: '',
    files: [
      Artifact(
        id: '$modelId-model',
        role: 'model',
        format: 'gguf',
        quantization: '',
        filename: path,
        repositoryId: '',
        downloadUrl: '',
        backend: BackendKind.llamaCpp.catalogName,
      ),
    ],
    platforms: [platform],
    compatibleBackends: [BackendKind.llamaCpp.catalogName],
  );
}

class InferenceException implements Exception {
  const InferenceException(this.message);

  final String message;

  @override
  String toString() => message;
}
