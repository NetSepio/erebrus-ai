import 'dart:async';

import 'package:erebrus_mlx/erebrus_mlx.dart';

import '../data/catalog_entry.dart';
import 'inference_contract.dart';

abstract interface class MlxRuntime {
  Future<MlxProbeResult> probe();
  Future<void> loadModel(String modelDirectory);
  Stream<MlxGenerationEvent> generate({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required int maxKvSize,
    required double temperature,
    required double topP,
    required int topK,
    required double minP,
    required double repeatPenalty,
    required int seed,
  });
  Future<void> cancel();
  Future<void> unload();
}

class ErebrusMlxRuntime implements MlxRuntime {
  ErebrusMlxRuntime([ErebrusMlx? plugin]) : _plugin = plugin ?? ErebrusMlx();

  final ErebrusMlx _plugin;

  @override
  Future<void> cancel() => _plugin.cancel();

  @override
  Stream<MlxGenerationEvent> generate({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required int maxKvSize,
    required double temperature,
    required double topP,
    required int topK,
    required double minP,
    required double repeatPenalty,
    required int seed,
  }) => _plugin.generate(
    messages: messages,
    maxTokens: maxTokens,
    maxKvSize: maxKvSize,
    temperature: temperature,
    topP: topP,
    topK: topK,
    minP: minP,
    repeatPenalty: repeatPenalty,
    seed: seed,
  );

  @override
  Future<void> loadModel(String modelDirectory) =>
      _plugin.loadModel(modelDirectory);

  @override
  Future<MlxProbeResult> probe() => _plugin.probe();

  @override
  Future<void> unload() => _plugin.unload();
}

class MlxBackend implements InferenceBackend {
  MlxBackend({required this.platform, MlxRuntime? runtime})
    : _runtime = runtime ?? ErebrusMlxRuntime();

  final String platform;
  final MlxRuntime _runtime;
  String? _loadedVariantId;
  String? _loadedPackagePath;
  int _contextSize = 0;
  bool _generating = false;

  @override
  BackendKind get kind => BackendKind.mlx;

  bool get isLoaded => _loadedVariantId != null;
  String? get loadedVariantId => _loadedVariantId;

  @override
  Future<BackendCapabilities> probe() async {
    if (!_isAppleSiliconPlatform) {
      return BackendCapabilities(
        kind: kind,
        operational: false,
        platforms: [platform],
        formats: const ['mlx'],
        reason: 'MLX requires an Apple-silicon iPhone, iPad, or Mac',
      );
    }
    try {
      final result = await _runtime.probe();
      return BackendCapabilities(
        kind: kind,
        operational: result.available && result.metalAvailable,
        platforms: [result.platform],
        formats: const ['mlx'],
        accelerators: result.metalAvailable ? const ['Metal'] : const [],
        reason: result.reason,
      );
    } on Object catch (error) {
      return BackendCapabilities(
        kind: kind,
        operational: false,
        platforms: [platform],
        formats: const ['mlx'],
        reason: error.toString(),
      );
    }
  }

  @override
  bool supports(ModelVariant variant) =>
      _isAppleSiliconPlatform &&
      variant.format.toLowerCase() == 'mlx' &&
      variant.supportsBackend(kind.catalogName) &&
      variant.supportsPlatform(platform);

  @override
  Future<void> load(InferenceLoadRequest request) async {
    if (!supports(request.variant)) {
      throw InferenceBackendException(
        code: 'unsupported_variant',
        message: 'MLX does not support ${request.variant.id} on $platform',
      );
    }
    if (_generating) {
      throw const InferenceBackendException(
        code: 'generation_active',
        message: 'Cannot switch MLX models during generation',
      );
    }
    if (_loadedVariantId == request.variant.id &&
        _loadedPackagePath == request.packagePath &&
        _contextSize == request.contextSize) {
      return;
    }
    if (isLoaded) await unload();
    await _runtime.loadModel(request.packagePath);
    _loadedVariantId = request.variant.id;
    _loadedPackagePath = request.packagePath;
    _contextSize = request.contextSize;
  }

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) async* {
    if (!isLoaded) {
      yield const InferenceFailure(
        code: 'model_not_loaded',
        message: 'Load an MLX model before generation',
        retryable: true,
      );
      return;
    }
    if (_generating) {
      yield const InferenceFailure(
        code: 'generation_active',
        message: 'An MLX generation is already active',
        retryable: true,
      );
      return;
    }
    if (request.stopSequences.isNotEmpty || request.tools.isNotEmpty) {
      yield const InferenceFailure(
        code: 'unsupported_request',
        message:
            'This MLX runtime does not yet support custom stop sequences or tools',
        retryable: true,
      );
      return;
    }
    if (request.messages.isEmpty ||
        request.messages.last.role.toLowerCase() != 'user') {
      yield const InferenceFailure(
        code: 'invalid_messages',
        message: 'MLX conversations must end in a user message',
        retryable: false,
      );
      return;
    }

    _generating = true;
    final clock = Stopwatch()..start();
    var emittedToken = false;
    var generatedTokens = 0;
    try {
      final events = _runtime.generate(
        messages: request.messages
            .map(
              (message) => {
                'role': message.role.toLowerCase(),
                'content': message.content,
              },
            )
            .toList(growable: false),
        maxTokens: request.maxOutputTokens,
        maxKvSize: _contextSize,
        temperature: request.sampling.temperature,
        topP: request.sampling.topP,
        topK: request.sampling.topK,
        minP: request.sampling.minP,
        repeatPenalty: request.sampling.repeatPenalty,
        seed: request.sampling.seed,
      );
      await for (final event in events) {
        switch (event.type) {
          case 'started':
            break;
          case 'token':
            if (!emittedToken) {
              emittedToken = true;
              yield InferenceMetrics(timeToFirstToken: clock.elapsed);
            }
            if (event.text.isNotEmpty) yield InferenceToken(event.text);
          case 'completed':
            generatedTokens = event.generatedTokens ?? generatedTokens;
            yield InferenceMetrics(
              promptTokensPerSecond: event.promptTokensPerSecond,
              decodeTokensPerSecond: event.decodeTokensPerSecond,
            );
            yield InferenceCompleted(
              reason: _finishReason(event.finishReason),
              generatedTokens: generatedTokens,
            );
          case 'cancelled':
            yield InferenceCompleted(
              reason: InferenceFinishReason.cancelled,
              generatedTokens: generatedTokens,
            );
          case 'error':
            yield InferenceFailure(
              code: 'generation_failed',
              message: event.message,
              retryable: !emittedToken,
              beforeFirstToken: !emittedToken,
            );
          default:
            yield InferenceFailure(
              code: 'invalid_runtime_event',
              message: 'Unknown MLX event type "${event.type}"',
              retryable: !emittedToken,
              beforeFirstToken: !emittedToken,
            );
        }
      }
    } on Object catch (error) {
      yield InferenceFailure(
        code: 'generation_failed',
        message: error.toString(),
        retryable: !emittedToken,
        beforeFirstToken: !emittedToken,
      );
    } finally {
      _generating = false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_generating) return;
    await _runtime.cancel();
  }

  @override
  Future<void> unload() async {
    await _runtime.unload();
    _loadedVariantId = null;
    _loadedPackagePath = null;
    _contextSize = 0;
    _generating = false;
  }

  bool get _isAppleSiliconPlatform =>
      platform.toLowerCase() == 'macos-arm64' ||
      platform.toLowerCase() == 'ios-arm64';

  static InferenceFinishReason _finishReason(String value) => switch (value) {
    'length' => InferenceFinishReason.length,
    'cancelled' => InferenceFinishReason.cancelled,
    _ => InferenceFinishReason.stop,
  };
}
