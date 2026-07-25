import 'dart:async';

import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/inference_coordinator.dart';
import 'package:erebrus_ai/services/llama_cpp_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:lib_llama_cpp_platform_interface/lib_llama_cpp_platform_interface.dart';

void main() {
  group('LlamaCppBackend', () {
    test('retains one loaded model across generations', () async {
      final engine = _FakeLlamaEngine();
      final backend = LlamaCppBackend(engine: engine, platform: 'macos-arm64');
      final load = _loadRequest(BackendKind.llamaCpp);

      await backend.load(load);
      final first = await backend
          .generate(_request())
          .where((event) => event is InferenceToken)
          .cast<InferenceToken>()
          .map((event) => event.text)
          .join();
      await backend.load(load);
      final second = await backend
          .generate(_request())
          .where((event) => event is InferenceToken)
          .cast<InferenceToken>()
          .map((event) => event.text)
          .join();

      expect(first, 'hello');
      expect(second, 'hello');
      expect(engine.loadCount, 1);
      expect(engine.generateCount, 2);
      expect(backend.loadedVariantId, 'variant-llama.cpp');

      await backend.unload();
      expect(backend.isLoaded, isFalse);
    });
  });

  group('InferenceCoordinator', () {
    test('falls back only when failure occurs before first token', () async {
      final preferred = _FakeBackend(
        BackendKind.mlx,
        events: const [
          InferenceFailure(
            code: 'init_failed',
            message: 'failed before output',
            retryable: true,
          ),
        ],
      );
      final fallback = _FakeBackend(
        BackendKind.llamaCpp,
        events: const [
          InferenceToken('fallback'),
          InferenceCompleted(
            reason: InferenceFinishReason.stop,
            generatedTokens: 1,
          ),
        ],
      );
      final coordinator = InferenceCoordinator([preferred, fallback]);

      final events = await coordinator
          .generate(
            plans: [
              InferenceExecutionPlan(
                backend: BackendKind.mlx,
                loadRequest: _loadRequest(BackendKind.mlx),
              ),
              InferenceExecutionPlan(
                backend: BackendKind.llamaCpp,
                loadRequest: _loadRequest(BackendKind.llamaCpp),
              ),
            ],
            request: _request(),
          )
          .toList();

      expect(events.whereType<InferenceToken>().single.text, 'fallback');
      expect(preferred.unloadCount, 1);
      expect(fallback.loadCount, 1);
    });

    test('does not switch backend after output begins', () async {
      final preferred = _FakeBackend(
        BackendKind.mlx,
        events: const [
          InferenceToken('partial'),
          InferenceFailure(
            code: 'decode_failed',
            message: 'failed after output',
            retryable: false,
            beforeFirstToken: false,
          ),
        ],
      );
      final fallback = _FakeBackend(
        BackendKind.llamaCpp,
        events: const [InferenceToken('must-not-run')],
      );
      final coordinator = InferenceCoordinator([preferred, fallback]);

      final events = await coordinator
          .generate(
            plans: [
              InferenceExecutionPlan(
                backend: BackendKind.mlx,
                loadRequest: _loadRequest(BackendKind.mlx),
              ),
              InferenceExecutionPlan(
                backend: BackendKind.llamaCpp,
                loadRequest: _loadRequest(BackendKind.llamaCpp),
              ),
            ],
            request: _request(),
          )
          .toList();

      expect(events.whereType<InferenceToken>().single.text, 'partial');
      expect(events.whereType<InferenceFailure>(), hasLength(1));
      expect(fallback.loadCount, 0);
    });
  });
}

InferenceRequest _request() => const InferenceRequest(
  messages: [InferenceMessage(role: 'user', content: 'hello')],
  maxOutputTokens: 8,
);

InferenceLoadRequest _loadRequest(BackendKind backend) {
  final variant = ModelVariant(
    id: 'variant-${backend.catalogName}',
    modelId: 'model',
    format: backend == BackendKind.mlx ? 'mlx' : 'gguf',
    quantization: 'test',
    files: const [],
    platforms: const ['macos-arm64'],
    compatibleBackends: [backend.catalogName],
  );
  return InferenceLoadRequest(
    variant: variant,
    packagePath: '/models/${variant.id}',
    contextSize: 2048,
  );
}

class _FakeLlamaEngine implements LlamaEngine {
  int loadCount = 0;
  int generateCount = 0;

  @override
  Stream<LlamaResponse> transform(
    Stream<LlamaCommand> commands, {
    LlamaState initialState = const LlamaState.empty(),
    LlamaCppLibraryRequest libraryRequest = const LlamaCppLibraryRequest(),
  }) async* {
    await for (final command in commands) {
      switch (command) {
        case LlamaLoadModelCommand(:final modelPath):
          loadCount++;
          yield LlamaStateChangedResponse(
            state: LlamaState(
              modelPath: modelPath,
              isModelLoaded: true,
              capabilities: const LlamaModelCapabilities(text: true),
            ),
          );
        case LlamaGenerateCommand() || LlamaGenerateMessagesCommand():
          generateCount++;
          yield const LlamaTokenResponse(text: 'hello', index: 0);
          yield const LlamaDoneResponse();
        case LlamaDisposeCommand():
          yield const LlamaStateChangedResponse(state: LlamaState.empty());
          yield const LlamaDoneResponse();
          return;
      }
    }
  }
}

class _FakeBackend implements InferenceBackend {
  _FakeBackend(this.kind, {required this.events});

  @override
  final BackendKind kind;
  final List<InferenceEvent> events;
  int loadCount = 0;
  int unloadCount = 0;

  @override
  Future<void> cancel() async {}

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) =>
      Stream.fromIterable(events);

  @override
  Future<void> load(InferenceLoadRequest request) async {
    loadCount++;
  }

  @override
  Future<BackendCapabilities> probe() async =>
      BackendCapabilities(kind: kind, operational: true);

  @override
  bool supports(ModelVariant variant) => true;

  @override
  Future<void> unload() async {
    unloadCount++;
  }
}
