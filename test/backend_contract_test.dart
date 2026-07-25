import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/backend_probe_service.dart';
import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_mlx/erebrus_mlx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'current packaged backend report is conservative and explicit',
    () async {
      final service = BackendProbeService.instance;
      service.reset();

      final capabilities = await service.probe(device: _mac);

      final llama = capabilities.singleWhere(
        (capability) => capability.kind == BackendKind.llamaCpp,
      );
      final mlx = capabilities.singleWhere(
        (capability) => capability.kind == BackendKind.mlx,
      );
      final turboQuant = capabilities.singleWhere(
        (capability) => capability.kind == BackendKind.turboQuant,
      );

      expect(llama.accelerators, ['CPU']);
      expect(llama.formats, ['gguf']);
      expect(mlx.operational, isFalse);
      expect(turboQuant.operational, isFalse);
      expect(service.activeLabel, 'llama.cpp · CPU');
    },
  );

  test('backend capability requires backend, format, and platform match', () {
    const variant = ModelVariant(
      id: 'llama-mlx',
      modelId: 'llama',
      format: 'mlx',
      quantization: '4bit',
      files: [],
      platforms: ['macos-arm64'],
      compatibleBackends: ['mlx'],
    );
    const capability = BackendCapabilities(
      kind: BackendKind.mlx,
      operational: true,
      platforms: ['macos-arm64'],
      formats: ['mlx'],
      accelerators: ['Metal'],
    );

    expect(capability.supports(variant, 'macos-arm64'), isTrue);
    expect(capability.supports(variant, 'ios-arm64'), isFalse);
  });

  test('a responding packaged MLX runtime takes priority on Apple', () async {
    final service = BackendProbeService.instance;
    service.reset();

    final capabilities = await service.probe(
      device: _mac,
      mlxProbe: () async => const MlxProbeResult(
        available: true,
        metalAvailable: true,
        platform: 'macos-arm64',
        minimumOperatingSystem: 'macOS 14',
        reason: 'MLX Swift LM 3.31.3 is packaged',
      ),
    );

    expect(
      capabilities
          .singleWhere((capability) => capability.kind == BackendKind.mlx)
          .operational,
      isTrue,
    );
    expect(service.activeLabel, 'mlx · Metal');
  });
}

const _mac = DeviceProfile(
  type: DeviceType.desktop,
  ramBytes: 16 * 1024 * 1024 * 1024,
  name: 'Test Mac',
  platform: 'macos-arm64',
);
