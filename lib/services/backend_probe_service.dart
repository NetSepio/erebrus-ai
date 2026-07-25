import 'package:flutter/foundation.dart';

import 'device_info_service.dart';
import 'inference_contract.dart';

/// Reports packaged inference engines separately from hardware availability.
///
/// This initial probe is intentionally conservative: Erebrus currently ships a
/// CPU llama.cpp runtime and does not claim MLX, TurboQuant, or Metal until
/// their native packages and operational probes are integrated.
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

  Future<List<BackendCapabilities>> probe({DeviceProfile? device}) async {
    if (_probed) return capabilities;
    final profile = device ?? DeviceInfoService.detect();
    _capabilities = [
      BackendCapabilities(
        kind: BackendKind.llamaCpp,
        operational: !kIsWeb,
        platforms: [profile.platform],
        formats: const ['gguf'],
        accelerators: const ['CPU'],
        reason: kIsWeb
            ? 'Native llama.cpp is unavailable on web'
            : 'Packaged CPU runtime; each model load is verified separately',
      ),
      BackendCapabilities(
        kind: BackendKind.mlx,
        operational: false,
        platforms: [profile.platform],
        formats: const ['mlx'],
        reason: 'MLX Swift runtime is not packaged in this build',
      ),
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

  @visibleForTesting
  void reset() {
    _capabilities = const [];
    _probed = false;
    notifyListeners();
  }
}
