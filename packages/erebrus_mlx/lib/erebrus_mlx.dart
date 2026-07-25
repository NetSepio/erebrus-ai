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
  });

  factory MlxGenerationEvent.fromMap(Map<Object?, Object?> map) =>
      MlxGenerationEvent(
        type: map['type']?.toString() ?? 'unknown',
        text: map['text']?.toString() ?? '',
        message: map['message']?.toString() ?? '',
      );

  final String type;
  final String text;
  final String message;
}

class ErebrusMlx {
  Future<MlxProbeResult> probe() => ErebrusMlxPlatform.instance.probe();

  Future<void> loadModel(String modelDirectory) =>
      ErebrusMlxPlatform.instance.loadModel(modelDirectory);

  Stream<MlxGenerationEvent> generate({
    required String prompt,
    String systemPrompt = '',
    int maxTokens = 256,
    int maxKvSize = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) => ErebrusMlxPlatform.instance.generate(
    prompt: prompt,
    systemPrompt: systemPrompt,
    maxTokens: maxTokens,
    maxKvSize: maxKvSize,
    temperature: temperature,
    topP: topP,
  );

  Future<void> cancel() => ErebrusMlxPlatform.instance.cancel();

  Future<void> unload() => ErebrusMlxPlatform.instance.unload();
}
