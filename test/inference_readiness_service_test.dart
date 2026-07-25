import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/inference_readiness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'readiness requires an operational backend and successful model load',
    () async {
      final backend = _ReadinessBackend();
      final service = InferenceReadinessService(backends: [backend]);
      final variant = modelCatalog.first.variants.singleWhere(
        (candidate) => candidate.format == 'gguf',
      );

      final result = await service.verify(
        variant: variant,
        packagePath: '/models/nano/model.gguf',
        contextSize: 2048,
      );

      expect(result.runnable, isTrue);
      expect(result.backend, BackendKind.llamaCpp);
      expect(backend.loaded, isTrue);
      expect(backend.unloaded, isTrue);
    },
  );
}

class _ReadinessBackend implements InferenceBackend {
  bool loaded = false;
  bool unloaded = false;

  @override
  BackendKind get kind => BackendKind.llamaCpp;

  @override
  Future<void> cancel() async {}

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) =>
      const Stream.empty();

  @override
  Future<void> load(InferenceLoadRequest request) async {
    loaded = true;
  }

  @override
  Future<BackendCapabilities> probe() async =>
      const BackendCapabilities(kind: BackendKind.llamaCpp, operational: true);

  @override
  bool supports(ModelVariant variant) => true;

  @override
  Future<void> unload() async {
    unloaded = true;
  }
}
