import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/turbo_quant_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports the pinned operational runtime', () async {
    final runtime = _FakeRuntime();
    final backend = TurboQuantBackend(platform: 'linux-x64', runtime: runtime);

    final capability = await backend.probe();

    expect(capability.operational, isTrue);
    expect(capability.accelerators, ['CPU']);
    expect(capability.formats, ['gguf']);
    expect(capability.reason, contains('turbo3'));
  });

  test('accepts a compatible GGUF even when catalog names llama.cpp', () {
    final backend = TurboQuantBackend(
      platform: 'windows-x64',
      runtime: _FakeRuntime(),
    );

    expect(backend.supports(_variant(platform: 'windows-x64')), isTrue);
    expect(backend.supports(_variant(platform: 'windows-arm64')), isFalse);
  });

  test('loads once, streams events, and stops on unload', () async {
    final runtime = _FakeRuntime();
    final backend = TurboQuantBackend(platform: 'linux-x64', runtime: runtime);
    final request = InferenceLoadRequest(
      variant: _variant(platform: 'linux-x64'),
      packagePath: '/models/nano.gguf',
      contextSize: 8192,
    );

    await backend.load(request);
    await backend.load(request);
    final events = await backend
        .generate(
          const InferenceRequest(
            messages: [InferenceMessage(role: 'user', content: 'Hello')],
          ),
        )
        .toList();
    await backend.unload();

    expect(runtime.startCount, 1);
    expect(runtime.modelPath, '/models/nano.gguf');
    expect(runtime.contextSize, 8192);
    expect(runtime.gpuLayerCount, 0);
    expect(events.whereType<InferenceToken>().single.text, 'Hi');
    expect(events.whereType<InferenceCompleted>().single.generatedTokens, 1);
    expect(runtime.stopCount, 1);
  });

  test('reloads when the context allocation changes', () async {
    final runtime = _FakeRuntime(accelerator: 'CUDA');
    final backend = TurboQuantBackend(platform: 'linux-x64', runtime: runtime);
    final variant = _variant(platform: 'linux-x64');

    await backend.load(
      InferenceLoadRequest(
        variant: variant,
        packagePath: '/models/nano.gguf',
        contextSize: 8192,
        gpuLayerCount: 48,
      ),
    );
    await backend.load(
      InferenceLoadRequest(
        variant: variant,
        packagePath: '/models/nano.gguf',
        contextSize: 16384,
        gpuLayerCount: 64,
      ),
    );

    expect(runtime.startCount, 2);
    expect(runtime.contextSize, 16384);
    expect(runtime.gpuLayerCount, 64);
  });

  test('refuses load when packaged provenance does not validate', () async {
    final runtime = _FakeRuntime(operational: false);
    final backend = TurboQuantBackend(platform: 'linux-x64', runtime: runtime);

    expect(
      () => backend.load(
        InferenceLoadRequest(
          variant: _variant(platform: 'linux-x64'),
          packagePath: '/models/nano.gguf',
          contextSize: 4096,
        ),
      ),
      throwsA(
        isA<InferenceBackendException>().having(
          (error) => error.code,
          'code',
          'runtime_unavailable',
        ),
      ),
    );
  });
}

ModelVariant _variant({required String platform}) => ModelVariant(
  id: 'nano-q4',
  modelId: 'nano',
  format: 'gguf',
  quantization: 'Q4_K_M',
  files: const [],
  platforms: [platform],
  compatibleBackends: const ['llama.cpp'],
);

class _FakeRuntime implements TurboQuantRuntime {
  _FakeRuntime({this.operational = true, this.accelerator = 'CPU'});

  final bool operational;
  final String accelerator;
  int startCount = 0;
  int stopCount = 0;
  String? modelPath;
  int? contextSize;
  int? gpuLayerCount;

  @override
  Future<TurboQuantRuntimeProbe> probe() async => TurboQuantRuntimeProbe(
    operational: operational,
    accelerator: operational ? accelerator : '',
    reason: operational
        ? 'Pinned TurboQuant+ turbo3 runtime · $accelerator'
        : 'Invalid packaged provenance',
  );

  @override
  Future<void> start({
    required String modelPath,
    required int contextSize,
    required int gpuLayerCount,
  }) async {
    startCount++;
    this.modelPath = modelPath;
    this.contextSize = contextSize;
    this.gpuLayerCount = gpuLayerCount;
  }

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) async* {
    yield const InferenceToken('Hi');
    yield const InferenceCompleted(
      reason: InferenceFinishReason.stop,
      generatedTokens: 1,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> stop() async {
    stopCount++;
  }
}
