import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';

import 'model_download_service.dart';

/// Cross-platform GGUF inference backed by llama.cpp.
///
/// The package runs native inference in its own worker isolate. Our vendored
/// patch buffers UTF-8 sequences split across token pieces, which is required
/// for multilingual models on mobile.
class InferenceService extends ChangeNotifier {
  InferenceService._();

  static final InferenceService instance = InferenceService._();

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

    final modelPath = await ModelDownloadService.instance.modelPath(modelId);
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
      final commands = Stream<LlamaCommand>.fromIterable([
        LlamaLoadModelCommand(
          modelPath: modelPath,
          contextSize: contextSize,
          gpuLayerCount: 0,
        ),
        LlamaGenerateMessagesCommand(
          messages: [
            if (systemPrompt.trim().isNotEmpty)
              LlamaMessage(role: 'system', content: systemPrompt.trim()),
            LlamaMessage(role: 'user', content: prompt),
          ],
          maxTokens: outputTokens,
          temperature: temperature,
          topP: topP,
          repeatPenalty: repeatPenalty,
          stop: stop,
        ),
        const LlamaDisposeCommand(),
      ]);

      var tokenCount = 0;
      Stopwatch? tokenClock;
      await for (final response in const LibLlamaCpp().transform(commands)) {
        switch (response) {
          case LlamaReadyResponse():
            debugPrint('[Inference] native runtime ready');
          case LlamaStateChangedResponse(:final state):
            debugPrint(
              state.isModelLoaded
                  ? '[Inference] model loaded'
                  : '[Inference] model unloaded',
            );
          case LlamaTokenResponse(:final text):
            tokenCount++;
            if (tokenCount == 1) {
              tokenClock = Stopwatch()..start();
              debugPrint('[Inference] first token received');
            } else if (tokenClock!.elapsedMicroseconds > 0) {
              // Completion throughput excludes model loading and prompt eval.
              _currentTokensPerSecond =
                  (tokenCount - 1) /
                  (tokenClock.elapsedMicroseconds /
                      Duration.microsecondsPerSecond);
              notifyListeners();
            }
            if (text.isNotEmpty) yield text;
          case LlamaErrorResponse(:final message):
            throw InferenceException(_friendlyError(message));
          case LlamaDoneResponse():
            _lastTokensPerSecond = _currentTokensPerSecond;
            _lastOutputWasTruncated = tokenCount >= outputTokens;
            debugPrint('[Inference] generation completed ($tokenCount tokens)');
          case LlamaToolCallResponse():
            // Plain local chats do not submit tools.
            break;
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
