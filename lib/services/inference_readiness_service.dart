import '../data/catalog_entry.dart';
import 'device_info_service.dart';
import 'inference_contract.dart';
import 'llama_cpp_backend.dart';

class InferenceReadinessResult {
  const InferenceReadinessResult({
    required this.runnable,
    this.backend,
    this.failureCode = '',
    this.reason = '',
  });

  final bool runnable;
  final BackendKind? backend;
  final String failureCode;
  final String reason;
}

class InferenceReadinessService {
  InferenceReadinessService({List<InferenceBackend>? backends})
    : _backends =
          backends ??
          [LlamaCppBackend(platform: DeviceInfoService.detect().platform)];

  final List<InferenceBackend> _backends;

  Future<InferenceReadinessResult> verify({
    required ModelVariant variant,
    required String packagePath,
    required int contextSize,
  }) async {
    String lastReason = 'No packaged backend supports ${variant.id}';
    for (final backend in _backends) {
      if (!backend.supports(variant)) continue;
      try {
        final capabilities = await backend.probe();
        if (!capabilities.operational) {
          lastReason = capabilities.reason;
          continue;
        }
        await backend.load(
          InferenceLoadRequest(
            variant: variant,
            packagePath: packagePath,
            contextSize: contextSize,
          ),
        );
        await backend.unload();
        return InferenceReadinessResult(
          runnable: true,
          backend: backend.kind,
          reason: 'Verified model load with ${backend.kind.catalogName}',
        );
      } on Object catch (error) {
        lastReason = error.toString();
        await backend.unload();
      }
    }
    return InferenceReadinessResult(
      runnable: false,
      failureCode: 'backend_load_failed',
      reason: lastReason,
    );
  }
}
