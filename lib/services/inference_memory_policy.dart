import 'device_info_service.dart';
import 'inference_contract.dart';

class InferenceMemoryPlan {
  const InferenceMemoryPlan({
    required this.contextSize,
    required this.gpuLayerCount,
    required this.reservedSystemBytes,
    required this.reason,
  });

  final int contextSize;
  final int? gpuLayerCount;
  final int reservedSystemBytes;
  final String reason;
}

/// Conservative defaults that leave room for the OS and foreground UI.
class InferenceMemoryPolicy {
  const InferenceMemoryPolicy();

  InferenceMemoryPlan plan({
    required DeviceProfile device,
    required BackendKind backend,
  }) {
    final ramGB = device.ramGB;
    final mobile = device.type == DeviceType.mobile;
    final baselineContextSize = mobile
        ? (ramGB < 6
              ? 1024
              : ramGB < 8
              ? 2048
              : 4096)
        : (ramGB < 12
              ? 4096
              : ramGB < 24
              ? 8192
              : 16384);
    final contextSize = backend == BackendKind.turboQuant && !mobile
        ? (ramGB < 8
              ? 4096
              : ramGB < 16
              ? 8192
              : ramGB < 32
              ? 16384
              : 32768)
        : baselineContextSize;
    final reserveGB = mobile
        ? (ramGB < 6 ? 1.5 : 2.0)
        : (ramGB < 12 ? 3.0 : 4.0);
    final appleSilicon =
        device.platform == 'macos-arm64' || device.platform == 'ios-arm64';
    final gpuLayerCount = backend == BackendKind.llamaCpp && appleSilicon
        ? 99
        : null;

    return InferenceMemoryPlan(
      contextSize: contextSize,
      gpuLayerCount: gpuLayerCount,
      reservedSystemBytes: (reserveGB * 1024 * 1024 * 1024).round(),
      reason:
          '$contextSize-token cache with ${reserveGB.toStringAsFixed(1)} GB '
          'reserved for the OS'
          '${backend == BackendKind.turboQuant ? '; compressed q8_0/turbo3 KV enabled' : ''}'
          '${gpuLayerCount == null ? '' : '; Metal offload enabled'}',
    );
  }
}
