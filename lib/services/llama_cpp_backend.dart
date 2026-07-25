import 'dart:async';

import 'package:lib_llama_cpp/lib_llama_cpp.dart';

import '../data/catalog_entry.dart';
import 'inference_contract.dart';

class LlamaCppBackend implements InferenceBackend {
  LlamaCppBackend({this._engine = const LibLlamaCpp(), required this.platform});

  final LlamaEngine _engine;
  final String platform;

  StreamController<LlamaCommand>? _commands;
  StreamSubscription<LlamaResponse>? _responses;
  Completer<void>? _loadCompleter;
  Completer<void>? _unloadCompleter;
  StreamController<InferenceEvent>? _generation;
  Stopwatch? _generationClock;
  Stopwatch? _decodeClock;
  String? _loadedVariantId;
  String? _loadedPackagePath;
  int? _loadedContextSize;
  int _generatedTokens = 0;
  int _maximumOutputTokens = 0;

  @override
  BackendKind get kind => BackendKind.llamaCpp;

  bool get isLoaded => _loadedVariantId != null;
  String? get loadedVariantId => _loadedVariantId;

  @override
  Future<BackendCapabilities> probe() async => BackendCapabilities(
    kind: kind,
    operational: true,
    platforms: [platform],
    formats: const ['gguf'],
    accelerators: const ['CPU'],
    reason: 'Packaged llama.cpp runtime; model loads are verified on demand',
  );

  @override
  bool supports(ModelVariant variant) =>
      variant.format.toLowerCase() == 'gguf' &&
      variant.supportsBackend(kind.catalogName) &&
      variant.supportsPlatform(platform);

  @override
  Future<void> load(InferenceLoadRequest request) async {
    if (!supports(request.variant)) {
      throw InferenceBackendException(
        code: 'unsupported_variant',
        message: 'llama.cpp does not support ${request.variant.id}',
      );
    }
    if (_generation != null) {
      throw const InferenceBackendException(
        code: 'generation_active',
        message: 'Cannot switch models while generation is active',
      );
    }
    if (_loadedVariantId == request.variant.id &&
        _loadedPackagePath == request.packagePath &&
        _loadedContextSize == request.contextSize) {
      return;
    }
    if (_responses != null) await unload();

    final commands = StreamController<LlamaCommand>();
    _commands = commands;
    _loadCompleter = Completer<void>();
    _responses = _engine
        .transform(commands.stream)
        .listen(
          _handleResponse,
          onError: _handleRuntimeError,
          onDone: _handleRuntimeDone,
          cancelOnError: false,
        );
    commands.add(
      LlamaLoadModelCommand(
        modelPath: request.packagePath,
        contextSize: request.contextSize,
        gpuLayerCount: request.gpuLayerCount ?? 0,
      ),
    );
    await _loadCompleter!.future;
    _loadedVariantId = request.variant.id;
    _loadedPackagePath = request.packagePath;
    _loadedContextSize = request.contextSize;
  }

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) {
    if (!isLoaded || _commands == null) {
      return Stream.value(
        const InferenceFailure(
          code: 'model_not_loaded',
          message: 'Load a llama.cpp model before generation',
          retryable: true,
        ),
      );
    }
    if (_generation != null) {
      return Stream.value(
        const InferenceFailure(
          code: 'generation_active',
          message: 'A generation is already active',
          retryable: true,
        ),
      );
    }

    final output = StreamController<InferenceEvent>();
    _generation = output;
    _generationClock = Stopwatch()..start();
    _decodeClock = null;
    _generatedTokens = 0;
    _maximumOutputTokens = request.maxOutputTokens;
    _commands!.add(
      LlamaGenerateMessagesCommand(
        messages: request.messages
            .map(
              (message) =>
                  LlamaMessage(role: message.role, content: message.content),
            )
            .toList(growable: false),
        maxTokens: request.maxOutputTokens,
        temperature: request.sampling.temperature,
        topP: request.sampling.topP,
        repeatPenalty: request.sampling.repeatPenalty,
        stop: request.stopSequences,
      ),
    );
    return output.stream;
  }

  @override
  Future<void> cancel() async {
    final output = _generation;
    if (output == null) return;
    output.add(
      InferenceCompleted(
        reason: InferenceFinishReason.cancelled,
        generatedTokens: _generatedTokens,
      ),
    );
    _generation = null;
    unawaited(output.close());

    // The vendored actor processes native generation synchronously. Cancelling
    // its response subscription terminates that worker safely; the next request
    // reloads the retained model rather than risking interleaved output.
    await _shutdownRuntime();
  }

  @override
  Future<void> unload() async {
    if (_generation != null) await cancel();
    if (_commands == null || _responses == null) {
      _clearLoadedState();
      return;
    }
    _unloadCompleter = Completer<void>();
    _commands!.add(const LlamaDisposeCommand());
    await _unloadCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () async {
        await _shutdownRuntime();
      },
    );
    await _shutdownRuntime();
  }

  void _handleResponse(LlamaResponse response) {
    switch (response) {
      case LlamaReadyResponse():
        break;
      case LlamaStateChangedResponse(:final state):
        if (state.isModelLoaded) {
          _complete(_loadCompleter);
        } else {
          _complete(_unloadCompleter);
          _clearLoadedState();
        }
      case LlamaTokenResponse(:final text):
        final output = _generation;
        if (output == null) return;
        _generatedTokens++;
        if (_generatedTokens == 1) {
          final firstToken = _generationClock?.elapsed;
          _decodeClock = Stopwatch()..start();
          output.add(InferenceMetrics(timeToFirstToken: firstToken));
        } else {
          final elapsed = _decodeClock?.elapsedMicroseconds ?? 0;
          if (elapsed > 0) {
            output.add(
              InferenceMetrics(
                decodeTokensPerSecond:
                    (_generatedTokens - 1) /
                    (elapsed / Duration.microsecondsPerSecond),
              ),
            );
          }
        }
        output.add(InferenceToken(text));
      case LlamaDoneResponse():
        final output = _generation;
        if (output != null) {
          output.add(
            InferenceCompleted(
              reason: _generatedTokens >= _maximumOutputTokens
                  ? InferenceFinishReason.length
                  : InferenceFinishReason.stop,
              generatedTokens: _generatedTokens,
            ),
          );
          unawaited(output.close());
          _generation = null;
        }
        _complete(_unloadCompleter);
      case LlamaErrorResponse(:final message):
        _handleBackendFailure(message);
      case LlamaToolCallResponse():
        _handleBackendFailure('Tool calls are not yet supported by llama.cpp');
    }
  }

  void _handleBackendFailure(String message) {
    final load = _loadCompleter;
    if (load != null && !load.isCompleted) {
      load.completeError(
        InferenceBackendException(code: 'model_load_failed', message: message),
      );
      return;
    }
    final output = _generation;
    if (output != null) {
      output.add(
        InferenceFailure(
          code: 'generation_failed',
          message: message,
          retryable: _generatedTokens == 0,
          beforeFirstToken: _generatedTokens == 0,
        ),
      );
      unawaited(output.close());
      _generation = null;
    }
  }

  void _handleRuntimeError(Object error, StackTrace stackTrace) {
    _handleBackendFailure(error.toString());
    _completeError(_loadCompleter, error, stackTrace);
    _completeError(_unloadCompleter, error, stackTrace);
    unawaited(_shutdownRuntime());
  }

  void _handleRuntimeDone() {
    if (_generation != null) {
      _handleBackendFailure('llama.cpp runtime stopped unexpectedly');
    }
    _completeError(
      _loadCompleter,
      const InferenceBackendException(
        code: 'runtime_stopped',
        message: 'llama.cpp runtime stopped before loading completed',
      ),
      StackTrace.current,
    );
    _complete(_unloadCompleter);
    _commands = null;
    _responses = null;
    _clearLoadedState();
  }

  Future<void> _shutdownRuntime() async {
    final commands = _commands;
    final responses = _responses;
    _commands = null;
    _responses = null;
    await responses?.cancel();
    await commands?.close();
    _clearLoadedState();
  }

  void _clearLoadedState() {
    _loadedVariantId = null;
    _loadedPackagePath = null;
    _loadedContextSize = null;
    _generationClock = null;
    _decodeClock = null;
  }

  static void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  static void _completeError(
    Completer<void>? completer,
    Object error,
    StackTrace stackTrace,
  ) {
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}

class InferenceBackendException implements Exception {
  const InferenceBackendException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
