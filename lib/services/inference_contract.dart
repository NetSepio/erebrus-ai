import '../data/catalog_entry.dart';

enum BackendKind {
  mlx('mlx'),
  turboQuant('turboquant'),
  llamaCpp('llama.cpp');

  const BackendKind(this.catalogName);

  final String catalogName;
}

enum InferenceFinishReason { stop, length, cancelled, error }

class BackendCapabilities {
  const BackendCapabilities({
    required this.kind,
    required this.operational,
    this.platforms = const [],
    this.formats = const [],
    this.accelerators = const [],
    this.reason = '',
  });

  final BackendKind kind;
  final bool operational;
  final List<String> platforms;
  final List<String> formats;
  final List<String> accelerators;
  final String reason;

  bool supports(ModelVariant variant, String platform) {
    if (!operational || !variant.supportsPlatform(platform)) return false;
    if (platforms.isNotEmpty &&
        !platforms.any(
          (candidate) => candidate.toLowerCase() == platform.toLowerCase(),
        )) {
      return false;
    }
    if (formats.isNotEmpty &&
        !formats.any(
          (format) => format.toLowerCase() == variant.format.toLowerCase(),
        )) {
      return false;
    }
    return variant.supportsBackend(kind.catalogName);
  }
}

class InferenceMessage {
  const InferenceMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class InferenceSampling {
  const InferenceSampling({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.seed = -1,
  });

  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double repeatPenalty;
  final int seed;
}

class InferenceLoadRequest {
  const InferenceLoadRequest({
    required this.variant,
    required this.packagePath,
    required this.contextSize,
    this.gpuLayerCount,
  });

  final ModelVariant variant;
  final String packagePath;
  final int contextSize;
  final int? gpuLayerCount;
}

class InferenceRequest {
  const InferenceRequest({
    required this.messages,
    this.sampling = const InferenceSampling(),
    this.maxOutputTokens = 768,
    this.stopSequences = const [],
    this.tools = const [],
  });

  final List<InferenceMessage> messages;
  final InferenceSampling sampling;
  final int maxOutputTokens;
  final List<String> stopSequences;
  final List<Map<String, Object?>> tools;
}

sealed class InferenceEvent {
  const InferenceEvent();
}

class InferenceLoadCompleted extends InferenceEvent {
  const InferenceLoadCompleted({
    required this.backend,
    required this.loadDuration,
  });

  final BackendKind backend;
  final Duration loadDuration;
}

class InferenceToken extends InferenceEvent {
  const InferenceToken(this.text);

  final String text;
}

class InferenceMetrics extends InferenceEvent {
  const InferenceMetrics({
    this.timeToFirstToken,
    this.promptTokensPerSecond,
    this.decodeTokensPerSecond,
    this.peakMemoryBytes,
  });

  final Duration? timeToFirstToken;
  final double? promptTokensPerSecond;
  final double? decodeTokensPerSecond;
  final int? peakMemoryBytes;
}

class InferenceCompleted extends InferenceEvent {
  const InferenceCompleted({
    required this.reason,
    required this.generatedTokens,
  });

  final InferenceFinishReason reason;
  final int generatedTokens;
}

class InferenceFailure extends InferenceEvent {
  const InferenceFailure({
    required this.code,
    required this.message,
    required this.retryable,
    this.beforeFirstToken = true,
  });

  final String code;
  final String message;
  final bool retryable;
  final bool beforeFirstToken;
}

abstract interface class InferenceBackend {
  BackendKind get kind;

  Future<BackendCapabilities> probe();
  bool supports(ModelVariant variant);
  Future<void> load(InferenceLoadRequest request);
  Stream<InferenceEvent> generate(InferenceRequest request);
  Future<void> cancel();
  Future<void> unload();
}

class InferenceBackendException implements Exception {
  const InferenceBackendException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
