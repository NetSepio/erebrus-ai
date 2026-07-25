import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidThermalState {
  none,
  light,
  moderate,
  severe,
  critical,
  emergency,
  shutdown,
  unknown,
}

class AndroidHardwareProfile {
  const AndroidHardwareProfile({
    required this.manufacturer,
    required this.model,
    required this.device,
    required this.hardware,
    required this.supportedAbis,
    required this.sdk,
    required this.buildFingerprint,
    required this.vulkanVersion,
    required this.thermalState,
  });

  factory AndroidHardwareProfile.fromJson(Map<Object?, Object?> value) {
    final thermal = value['thermalStatus'] as int? ?? -1;
    return AndroidHardwareProfile(
      manufacturer: value['manufacturer']?.toString() ?? '',
      model: value['model']?.toString() ?? '',
      device: value['device']?.toString() ?? '',
      hardware: value['hardware']?.toString() ?? '',
      supportedAbis: (value['supportedAbis'] as List<Object?>? ?? const [])
          .map((abi) => abi.toString())
          .toList(growable: false),
      sdk: value['sdk'] as int? ?? 0,
      buildFingerprint: value['buildFingerprint']?.toString() ?? '',
      vulkanVersion: value['vulkanVersion'] as int? ?? 0,
      thermalState: switch (thermal) {
        0 => AndroidThermalState.none,
        1 => AndroidThermalState.light,
        2 => AndroidThermalState.moderate,
        3 => AndroidThermalState.severe,
        4 => AndroidThermalState.critical,
        5 => AndroidThermalState.emergency,
        6 => AndroidThermalState.shutdown,
        _ => AndroidThermalState.unknown,
      },
    );
  }

  final String manufacturer;
  final String model;
  final String device;
  final String hardware;
  final List<String> supportedAbis;
  final int sdk;
  final String buildFingerprint;
  final int vulkanVersion;
  final AndroidThermalState thermalState;

  bool get isArm64 => supportedAbis.contains('arm64-v8a');
}

class AndroidAccelerationCertification {
  const AndroidAccelerationCertification({
    required this.manufacturer,
    required this.device,
    required this.hardware,
    required this.minimumSdk,
    required this.maximumSdk,
    required this.buildFingerprintPrefix,
    required this.cpuPassed,
    required this.vulkanPassed,
    this.minimumVulkanVersion = 0,
  });

  final String manufacturer;
  final String device;
  final String hardware;
  final int minimumSdk;
  final int maximumSdk;
  final String buildFingerprintPrefix;
  final bool cpuPassed;
  final bool vulkanPassed;
  final int minimumVulkanVersion;

  bool matches(AndroidHardwareProfile profile) =>
      profile.manufacturer.toLowerCase() == manufacturer.toLowerCase() &&
      profile.device.toLowerCase() == device.toLowerCase() &&
      profile.hardware.toLowerCase() == hardware.toLowerCase() &&
      profile.sdk >= minimumSdk &&
      profile.sdk <= maximumSdk &&
      buildFingerprintPrefix.isNotEmpty &&
      profile.buildFingerprint.startsWith(buildFingerprintPrefix);
}

class AndroidAccelerationDecision {
  const AndroidAccelerationDecision({
    required this.turboQuantCpu,
    required this.turboQuantVulkan,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.reason,
  });

  final bool turboQuantCpu;
  final bool turboQuantVulkan;
  final int contextSize;
  final int maxOutputTokens;
  final String reason;
}

class AndroidAccelerationService {
  const AndroidAccelerationService();

  static const _channel = MethodChannel('com.erebrus.ai/methods');

  /// Production starts empty. A device is added only with committed benchmark,
  /// quality, thermal, driver, and repeated-session evidence.
  static const certifications = <AndroidAccelerationCertification>[];

  Future<AndroidHardwareProfile?> probeHardware() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final value = await _channel.invokeMethod<Map<Object?, Object?>>(
        'androidAccelerationInfo',
      );
      return value == null ? null : AndroidHardwareProfile.fromJson(value);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  AndroidAccelerationDecision evaluate(
    AndroidHardwareProfile profile, {
    required double ramGB,
    List<AndroidAccelerationCertification> allowlist = certifications,
  }) {
    if (!profile.isArm64) {
      return const AndroidAccelerationDecision(
        turboQuantCpu: false,
        turboQuantVulkan: false,
        contextSize: 1024,
        maxOutputTokens: 256,
        reason: 'TurboQuant Android requires ARM64',
      );
    }
    if (profile.thermalState.index >= AndroidThermalState.severe.index) {
      return const AndroidAccelerationDecision(
        turboQuantCpu: false,
        turboQuantVulkan: false,
        contextSize: 1024,
        maxOutputTokens: 256,
        reason: 'TurboQuant paused because the device is thermally constrained',
      );
    }

    AndroidAccelerationCertification? certification;
    for (final candidate in allowlist) {
      if (candidate.matches(profile)) {
        certification = candidate;
        break;
      }
    }
    if (certification == null || !certification.cpuPassed) {
      return const AndroidAccelerationDecision(
        turboQuantCpu: false,
        turboQuantVulkan: false,
        contextSize: 1024,
        maxOutputTokens: 256,
        reason:
            'Android TurboQuant candidate is not certified for this exact '
            'device and OS build; using upstream llama.cpp',
      );
    }

    var contextSize = ramGB < 6
        ? 1024
        : ramGB < 8
        ? 2048
        : ramGB < 12
        ? 4096
        : 8192;
    var maxOutputTokens = ramGB < 8 ? 384 : 768;
    if (profile.thermalState == AndroidThermalState.moderate) {
      contextSize = contextSize.clamp(1024, 2048);
      maxOutputTokens = maxOutputTokens.clamp(128, 384);
    }
    final vulkan =
        certification.vulkanPassed &&
        certification.minimumVulkanVersion > 0 &&
        profile.vulkanVersion >= certification.minimumVulkanVersion;
    return AndroidAccelerationDecision(
      turboQuantCpu: true,
      turboQuantVulkan: vulkan,
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      reason: vulkan
          ? 'Exact device, OS, Vulkan driver, quality, and thermal profile certified'
          : 'Exact device and OS CPU profile certified; Vulkan remains disabled',
    );
  }
}
