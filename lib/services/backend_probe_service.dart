import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:erebrus_mlx/erebrus_mlx.dart';

import 'device_info_service.dart';
import 'inference_contract.dart';
import 'llama_cpp_backend.dart';

/// Reports packaged inference engines separately from hardware availability.
///
typedef MlxProbe = Future<MlxProbeResult> Function();

/// A backend is operational only when both its package and runtime accelerator
/// respond. Hardware detection alone never advertises an inference backend.
class BackendProbeService extends ChangeNotifier {
  BackendProbeService._();

  static final BackendProbeService instance = BackendProbeService._();

  List<BackendCapabilities> _capabilities = const [];
  bool _probed = false;

  List<BackendCapabilities> get capabilities =>
      List.unmodifiable(_capabilities);
  bool get probed => _probed;

  BackendCapabilities? get activeCapability {
    for (final capability in _capabilities) {
      if (capability.operational) return capability;
    }
    return null;
  }

  String get activeLabel {
    final active = activeCapability;
    if (active == null) return _probed ? 'No local backend' : 'Probing…';
    final accelerator = active.accelerators.firstOrNull ?? 'Unknown';
    return '${active.kind.catalogName} · $accelerator';
  }

  String get activeDescription {
    final active = activeCapability;
    return active?.reason ?? 'No packaged local inference backend responded';
  }

  Future<List<BackendCapabilities>> probe({
    DeviceProfile? device,
    MlxProbe? mlxProbe,
  }) async {
    if (_probed) return capabilities;
    final profile = device ?? DeviceInfoService.detect();
    final inFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
    final mlx = inFlutterTest && mlxProbe == null
        ? BackendCapabilities(
            kind: BackendKind.mlx,
            operational: false,
            platforms: [profile.platform],
            formats: const ['mlx'],
            reason: 'Native MLX probing is disabled in Flutter unit tests',
          )
        : await _probeMlx(profile, mlxProbe ?? ErebrusMlx().probe);
    final llama = LlamaCppBackend(platform: profile.platform);
    _capabilities = [
      mlx,
      if (kIsWeb)
        BackendCapabilities(
          kind: BackendKind.llamaCpp,
          operational: false,
          platforms: [profile.platform],
          formats: const ['gguf'],
          reason: 'Native llama.cpp is unavailable on web',
        )
      else if (inFlutterTest)
        BackendCapabilities(
          kind: BackendKind.llamaCpp,
          operational: true,
          platforms: [profile.platform],
          formats: const ['gguf'],
          accelerators: const ['CPU'],
          reason: 'Native resolution is disabled in Flutter unit tests',
        )
      else
        await llama.probe(),
      BackendCapabilities(
        kind: BackendKind.turboQuant,
        operational: false,
        platforms: [profile.platform],
        formats: const ['gguf'],
        reason: 'TurboQuant runtime is not packaged in this build',
      ),
    ];
    _probed = true;
    notifyListeners();
    return capabilities;
  }

  Future<BackendCapabilities> _probeMlx(
    DeviceProfile profile,
    MlxProbe nativeProbe,
  ) async {
    final isApple =
        profile.platform.startsWith('macos-') ||
        profile.platform.startsWith('ios-');
    if (kIsWeb || !isApple) {
      return BackendCapabilities(
        kind: BackendKind.mlx,
        operational: false,
        platforms: [profile.platform],
        formats: const ['mlx'],
        reason: 'MLX is available only in Apple platform builds',
      );
    }

    try {
      final result = await nativeProbe();
      final operational = result.available && result.metalAvailable;
      return BackendCapabilities(
        kind: BackendKind.mlx,
        operational: operational,
        platforms: [
          if (result.platform.isNotEmpty) result.platform else profile.platform,
        ],
        formats: const ['mlx'],
        accelerators: result.metalAvailable ? const ['Metal'] : const [],
        reason: operational
            ? '${result.reason}; minimum ${result.minimumOperatingSystem}'
            : result.reason.isNotEmpty
            ? result.reason
            : 'MLX package or Metal device probe failed',
      );
    } catch (error) {
      return BackendCapabilities(
        kind: BackendKind.mlx,
        operational: false,
        platforms: [profile.platform],
        formats: const ['mlx'],
        reason: 'MLX native probe did not respond: $error',
      );
    }
  }

  @visibleForTesting
  void reset() {
    _capabilities = const [];
    _probed = false;
    notifyListeners();
  }
}
