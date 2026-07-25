import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/catalog_entry.dart';
import 'device_info_service.dart';
import 'inference_contract.dart';
import 'inference_coordinator.dart';
import 'llama_cpp_backend.dart';
import 'model_download_service.dart';
import 'model_package_service.dart';

/// Cross-platform GGUF inference backed by llama.cpp.
///
/// The package runs native inference in its own worker isolate. Our vendored
/// patch buffers UTF-8 sequences split across token pieces, which is required
/// for multilingual models on mobile.
class InferenceService extends ChangeNotifier {
  InferenceService._() {
    _llamaCpp = LlamaCppBackend(platform: DeviceInfoService.detect().platform);
    _coordinator = InferenceCoordinator([_llamaCpp]);
  }

  static final InferenceService instance = InferenceService._();

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

    final installed = ModelPackageService.instance.runnableForModelId(modelId);
    final modelPath =
        await ModelDownloadService.instance.modelPath(modelId) ??
        (installed == null
            ? null
            : await ModelPackageService.instance.packagePath(
                installed.variantId,
              ));
    if (modelPath == null) {
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
      final variant = ModelVariant(
        id: installed?.variantId ?? modelId,
        modelId: modelId,
        format: 'gguf',
        quantization: '',
        files: [
          Artifact(
            id: '$modelId-model',
            role: 'model',
            format: 'gguf',
            quantization: '',
            filename: modelPath,
            repositoryId: '',
            downloadUrl: '',
            backend: BackendKind.llamaCpp.catalogName,
          ),
        ],
        platforms: [DeviceInfoService.detect().platform],
        compatibleBackends: [BackendKind.llamaCpp.catalogName],
      );
      final events = _coordinator.generate(
        plans: [
          InferenceExecutionPlan(
            backend: BackendKind.llamaCpp,
            loadRequest: InferenceLoadRequest(
              variant: variant,
              packagePath: modelPath,
              contextSize: contextSize,
              gpuLayerCount: 0,
            ),
          ),
        ],
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
}

class InferenceException implements Exception {
  const InferenceException(this.message);

  final String message;

  @override
  String toString() => message;
}
