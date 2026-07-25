import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/inference_memory_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = InferenceMemoryPolicy();

  test('constrained phones use a small cache and preserve system memory', () {
    final result = policy.plan(
      device: const DeviceProfile(
        type: DeviceType.mobile,
        ramBytes: 4 * 1024 * 1024 * 1024,
        name: '4 GB phone',
        platform: 'android-arm64',
      ),
      backend: BackendKind.llamaCpp,
    );

    expect(result.contextSize, 1024);
    expect(result.gpuLayerCount, isNull);
    expect(
      result.reservedSystemBytes,
      greaterThanOrEqualTo(1.5 * 1024 * 1024 * 1024),
    );
  });

  test('Apple-silicon Macs offload llama.cpp while bounding context', () {
    final result = policy.plan(
      device: const DeviceProfile(
        type: DeviceType.desktop,
        ramBytes: 8 * 1024 * 1024 * 1024,
        name: 'M1',
        platform: 'macos-arm64',
      ),
      backend: BackendKind.llamaCpp,
    );

    expect(result.contextSize, 4096);
    expect(result.gpuLayerCount, 99);
    expect(result.reason, contains('Metal offload enabled'));
  });

  test('high-memory MLX keeps GPU layers native and grows cache carefully', () {
    final result = policy.plan(
      device: const DeviceProfile(
        type: DeviceType.desktop,
        ramBytes: 32 * 1024 * 1024 * 1024,
        name: 'M-series',
        platform: 'macos-arm64',
      ),
      backend: BackendKind.mlx,
    );

    expect(result.contextSize, 16384);
    expect(result.gpuLayerCount, isNull);
    expect(result.reservedSystemBytes, 4 * 1024 * 1024 * 1024);
  });
}
