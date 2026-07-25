import 'package:erebrus_ai/services/android_acceleration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = AndroidAccelerationService();

  test('unknown devices always remain on upstream llama.cpp', () {
    final decision = service.evaluate(_profile(), ramGB: 8);

    expect(decision.turboQuantCpu, isFalse);
    expect(decision.turboQuantVulkan, isFalse);
    expect(decision.reason, contains('not certified'));
  });

  test('certification must match exact build and hardware', () {
    final decision = service.evaluate(
      _profile(),
      ramGB: 12,
      allowlist: const [_certification],
    );

    expect(decision.turboQuantCpu, isTrue);
    expect(decision.turboQuantVulkan, isTrue);
    expect(decision.contextSize, 8192);
  });

  test('a driver or OS change invalidates Vulkan and CPU promotion', () {
    final decision = service.evaluate(
      _profile(buildFingerprint: 'vendor/device/device:16/changed'),
      ramGB: 12,
      allowlist: const [_certification],
    );

    expect(decision.turboQuantCpu, isFalse);
    expect(decision.turboQuantVulkan, isFalse);
  });

  test('severe thermal pressure disables an otherwise certified device', () {
    final decision = service.evaluate(
      _profile(thermalState: AndroidThermalState.severe),
      ramGB: 12,
      allowlist: const [_certification],
    );

    expect(decision.turboQuantCpu, isFalse);
    expect(decision.reason, contains('thermally constrained'));
  });

  test('moderate thermal pressure caps sustained-session work', () {
    final decision = service.evaluate(
      _profile(thermalState: AndroidThermalState.moderate),
      ramGB: 12,
      allowlist: const [_certification],
    );

    expect(decision.turboQuantCpu, isTrue);
    expect(decision.contextSize, 2048);
    expect(decision.maxOutputTokens, 384);
  });
}

const _certification = AndroidAccelerationCertification(
  manufacturer: 'Erebrus',
  device: 'reference',
  hardware: 'reference-soc',
  minimumSdk: 35,
  maximumSdk: 36,
  buildFingerprintPrefix: 'vendor/device/device:16/reference',
  cpuPassed: true,
  vulkanPassed: true,
  minimumVulkanVersion: 0x00403000,
);

AndroidHardwareProfile _profile({
  String buildFingerprint = 'vendor/device/device:16/reference/release',
  AndroidThermalState thermalState = AndroidThermalState.none,
}) => AndroidHardwareProfile(
  manufacturer: 'Erebrus',
  model: 'Reference Phone',
  device: 'reference',
  hardware: 'reference-soc',
  supportedAbis: const ['arm64-v8a'],
  sdk: 36,
  buildFingerprint: buildFingerprint,
  vulkanVersion: 0x00403000,
  thermalState: thermalState,
);
