import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/mlx_backend.dart';
import 'package:erebrus_mlx/erebrus_mlx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MlxBackend', () {
    test('retains the loaded model and maps native metrics', () async {
      final runtime = _FakeMlxRuntime();
      final backend = MlxBackend(platform: 'macos-arm64', runtime: runtime);
      final load = _loadRequest();

      await backend.load(load);
      await backend.load(load);
      final events = await backend.generate(_request()).toList();

      expect(runtime.loadCount, 1);
      expect(runtime.messages, const [
        {'role': 'system', 'content': 'Be concise'},
        {'role': 'user', 'content': 'Earlier question'},
        {'role': 'assistant', 'content': 'Earlier answer'},
        {'role': 'user', 'content': 'Current question'},
      ]);
      expect(events.whereType<InferenceToken>().single.text, 'answer');
      expect(
        events.whereType<InferenceMetrics>().last.decodeTokensPerSecond,
        42,
      );
      expect(events.whereType<InferenceCompleted>().single.generatedTokens, 3);
    });

    test(
      'rejects unsupported requests before output so fallback is safe',
      () async {
        final backend = MlxBackend(
          platform: 'ios-arm64',
          runtime: _FakeMlxRuntime(),
        );
        await backend.load(_loadRequest(platform: 'ios-arm64'));

        final events = await backend
            .generate(
              InferenceRequest(
                messages: _request().messages,
                stopSequences: const ['END'],
              ),
            )
            .toList();

        final failure = events.single as InferenceFailure;
        expect(failure.beforeFirstToken, isTrue);
        expect(failure.retryable, isTrue);
      },
    );

    test('does not advertise MLX on Intel Macs', () async {
      final backend = MlxBackend(
        platform: 'macos-x86_64',
        runtime: _FakeMlxRuntime(),
      );

      expect(backend.supports(_loadRequest().variant), isFalse);
      expect((await backend.probe()).operational, isFalse);
    });
  });
}

InferenceLoadRequest _loadRequest({String platform = 'macos-arm64'}) =>
    InferenceLoadRequest(
      variant: ModelVariant(
        id: 'smollm-mlx',
        modelId: 'smollm',
        format: 'mlx',
        quantization: '4bit',
        files: const [],
        platforms: [platform],
        compatibleBackends: const ['mlx'],
      ),
      packagePath: '/models/smollm-mlx',
      contextSize: 2048,
    );

InferenceRequest _request() => const InferenceRequest(
  messages: [
    InferenceMessage(role: 'system', content: 'Be concise'),
    InferenceMessage(role: 'user', content: 'Earlier question'),
    InferenceMessage(role: 'assistant', content: 'Earlier answer'),
    InferenceMessage(role: 'user', content: 'Current question'),
  ],
  maxOutputTokens: 16,
);

class _FakeMlxRuntime implements MlxRuntime {
  int loadCount = 0;
  List<Map<String, String>> messages = const [];

  @override
  Future<void> cancel() async {}

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
  }) async* {
    this.messages = messages;
    yield const MlxGenerationEvent(type: 'started');
    yield const MlxGenerationEvent(type: 'token', text: 'answer');
    yield const MlxGenerationEvent(
      type: 'completed',
      generatedTokens: 3,
      promptTokensPerSecond: 100,
      decodeTokensPerSecond: 42,
      finishReason: 'stop',
    );
  }

  @override
  Future<void> loadModel(String modelDirectory) async {
    loadCount++;
  }

  @override
  Future<MlxProbeResult> probe() async => const MlxProbeResult(
    available: true,
    metalAvailable: true,
    platform: 'macos-arm64',
    minimumOperatingSystem: 'macOS 14',
  );

  @override
  Future<void> unload() async {}
}
