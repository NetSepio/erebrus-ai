import 'erebrus_mlx_platform_interface.dart';

class MlxProbeResult {
  const MlxProbeResult({
    required this.available,
    required this.metalAvailable,
    required this.platform,
    required this.minimumOperatingSystem,
    this.reason = '',
  });

  factory MlxProbeResult.fromMap(Map<Object?, Object?> map) => MlxProbeResult(
    available: map['available'] == true,
    metalAvailable: map['metal_available'] == true,
    platform: map['platform']?.toString() ?? '',
    minimumOperatingSystem: map['minimum_os']?.toString() ?? '',
    reason: map['reason']?.toString() ?? '',
  );

  final bool available;
  final bool metalAvailable;
  final String platform;
  final String minimumOperatingSystem;
  final String reason;
}

class MlxGenerationEvent {
  const MlxGenerationEvent({
    required this.type,
    this.text = '',
    this.message = '',
    this.generatedTokens,
    this.promptTokensPerSecond,
    this.decodeTokensPerSecond,
    this.finishReason = '',
  });

  factory MlxGenerationEvent.fromMap(Map<Object?, Object?> map) =>
      MlxGenerationEvent(
        type: map['type']?.toString() ?? 'unknown',
        text: map['text']?.toString() ?? '',
        message: map['message']?.toString() ?? '',
        generatedTokens: map['generated_tokens'] as int?,
        promptTokensPerSecond: (map['prompt_tokens_per_second'] as num?)
            ?.toDouble(),
        decodeTokensPerSecond: (map['decode_tokens_per_second'] as num?)
            ?.toDouble(),
        finishReason: map['finish_reason']?.toString() ?? '',
      );

  final String type;
  final String text;
  final String message;
  final int? generatedTokens;
  final double? promptTokensPerSecond;
  final double? decodeTokensPerSecond;
  final String finishReason;
}

class ErebrusMlx {
  Future<MlxProbeResult> probe() => ErebrusMlxPlatform.instance.probe();

  Future<void> loadModel(String modelDirectory) =>
      ErebrusMlxPlatform.instance.loadModel(modelDirectory);

  Stream<MlxGenerationEvent> generate({
    required List<Map<String, String>> messages,
    int maxTokens = 256,
    int maxKvSize = 2048,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    double minP = 0.05,
    double repeatPenalty = 1.1,
    int seed = -1,
  }) => ErebrusMlxPlatform.instance.generate(
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

  Future<void> cancel() => ErebrusMlxPlatform.instance.cancel();

  Future<void> unload() => ErebrusMlxPlatform.instance.unload();
}
