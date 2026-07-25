import '../data/catalog_entry.dart';
import 'device_info_service.dart';

enum BackendKind {
  mlx('mlx'),
  turboQuant('turboquant'),
  llamaCpp('llama.cpp');

  const BackendKind(this.catalogName);

  final String catalogName;
}

class BackendCapabilities {
  const BackendCapabilities({
    required this.kind,
    required this.operational,
    this.platforms = const [],
    this.formats = const [],
    this.reason = '',
  });

  final BackendKind kind;
  final bool operational;
  final List<String> platforms;
  final List<String> formats;
  final String reason;

  bool supports(ModelVariant variant, String platform) {
    if (!operational || !variant.supportsPlatform(platform)) return false;
    if (platforms.isNotEmpty &&
        !platforms.any(
          (candidate) => candidate.toLowerCase() == platform.toLowerCase(),
        )) {
      return false;
    }
    if (formats.isNotEmpty &&
        !formats.any(
          (format) => format.toLowerCase() == variant.format.toLowerCase(),
        )) {
      return false;
    }
    return variant.supportsBackend(kind.catalogName);
  }
}

class ResolvedModelVariant {
  const ResolvedModelVariant({
    required this.model,
    required this.variant,
    required this.backend,
    required this.score,
    required this.reason,
  });

  final CatalogEntry model;
  final ModelVariant variant;
  final BackendKind backend;
  final double score;
  final String reason;
}

/// Pure device/backend/model resolver.
///
/// It contains no native probing or download state. Callers provide those facts
/// explicitly, which keeps selection deterministic and testable.
class InferencePlanner {
  const InferencePlanner();

  List<ResolvedModelVariant> resolve({
    required List<CatalogEntry> models,
    required DeviceProfile device,
    required List<BackendCapabilities> backends,
    Set<String>? installedVariantIds,
    bool allowExperimental = false,
  }) {
    final results = <ResolvedModelVariant>[];
    final memoryBudget =
        device.ramGB * (device.type == DeviceType.mobile ? 0.45 : 0.70);

    for (final model in models) {
      for (final variant in model.variants) {
        if (!variant.isActive) continue;
        if (installedVariantIds != null &&
            !installedVariantIds.contains(variant.id)) {
          continue;
        }
        if (!allowExperimental &&
            variant.releaseChannel.toLowerCase() == 'experimental') {
          continue;
        }

        final recommendedRam = variant.recommendedRamGB > 0
            ? variant.recommendedRamGB
            : model.ramGB;
        final minimumRam = variant.minimumRamGB > 0
            ? variant.minimumRamGB
            : recommendedRam * 0.8;
        if (minimumRam > memoryBudget) continue;

        for (final backend in backends) {
          if (!backend.supports(variant, device.platform)) continue;

          final fitsRecommended = recommendedRam <= memoryBudget;
          final backendScore = _backendPriority(backend.kind, device.platform);
          final fitScore = fitsRecommended ? 1000.0 : 500.0;
          final modelScore = model.featured ? 20.0 : 0.0;
          final channelScore = variant.releaseChannel.toLowerCase() == 'stable'
              ? 20.0
              : 0.0;
          final score = fitScore + backendScore + modelScore + channelScore;
          final fitReason = fitsRecommended
              ? 'fits recommended memory'
              : 'fits minimum memory only';
          results.add(
            ResolvedModelVariant(
              model: model,
              variant: variant,
              backend: backend.kind,
              score: score,
              reason:
                  '${backend.kind.catalogName} preferred for '
                  '${device.platform}; $fitReason',
            ),
          );
        }
      }
    }

    results.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      final modelOrder = a.model.sortOrder.compareTo(b.model.sortOrder);
      if (modelOrder != 0) return modelOrder;
      return a.variant.id.compareTo(b.variant.id);
    });
    return results;
  }

  double _backendPriority(BackendKind kind, String platform) {
    final apple = platform.startsWith('macos-') || platform.startsWith('ios-');
    if (apple) {
      return switch (kind) {
        BackendKind.mlx => 300,
        BackendKind.llamaCpp => 200,
        BackendKind.turboQuant => 100,
      };
    }
    return switch (kind) {
      BackendKind.turboQuant => 300,
      BackendKind.llamaCpp => 200,
      BackendKind.mlx => 0,
    };
  }
}
