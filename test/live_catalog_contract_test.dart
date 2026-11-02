import 'dart:io';

import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/inference_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final path = Platform.environment['EREBRUS_LIVE_CATALOG_PATH'];

  test(
    'production catalog satisfies the app contract',
    () async {
      final payload = await File(path!).readAsString();
      final entries = CatalogService.parsePayload(payload);
      final editorial = CatalogService.parseRecommendations(payload);
      final variants = entries.expand((entry) => entry.variants).toList();

      expect(entries, hasLength(60));
      expect(variants, hasLength(79));
      expect(
        variants.where((variant) => variant.format == 'mlx'),
        hasLength(15),
      );
      expect(
        variants.where((variant) => variant.provenance.isOfficial),
        hasLength(10),
      );
      expect(entries.where((entry) => entry.reducedSafety), hasLength(14));
      // Every package must load on a bundled runtime: no PrismML-fork
      // backends and no ggml types beyond what llama.cpp/TurboQuant ship.
      expect(entries.where((entry) => !entry.hasShippedBackend), isEmpty);
      expect(
        variants.where(
          (variant) =>
              variant.quantization == 'Q2_0' ||
              variant.quantization.startsWith('PTQ') ||
              variant.quantization.startsWith('PQ'),
        ),
        isEmpty,
      );
      expect(editorial.mobile, isNotEmpty);
      expect(editorial.computer, isNotEmpty);

      final flagshipIphone = DeviceProfile(
        type: DeviceType.mobile,
        ramBytes: (11.4 * 1024 * 1024 * 1024).round(),
        name: 'Flagship iPhone',
        platform: 'ios-arm64',
      );
      final preferredVariants = {
        for (final entry in entries)
          if (entry.variants.any(
            (variant) =>
                variant.format == 'mlx' &&
                variant.supportsPlatform(flagshipIphone.platform),
          ))
            entry.id: entry.variants.firstWhere(
              (variant) =>
                  variant.format == 'mlx' &&
                  variant.supportsPlatform(flagshipIphone.platform),
            )
          else if (entry.variants.any(
            (variant) => variant.supportsPlatform(flagshipIphone.platform),
          ))
            entry.id: entry.variants.firstWhere(
              (variant) => variant.supportsPlatform(flagshipIphone.platform),
            ),
      };
      final recommendation = recommendModel(
        flagshipIphone,
        catalog: entries,
        preferredVariants: preferredVariants,
        editorial: editorial,
      );
      expect(
        [
          recommendation.recommended.id,
          ...recommendation.alternatives.map((entry) => entry.id),
        ],
        ['gemma-4-e4b-it', 'spark-x2.6-4b', 'gemma-4-e2b-it'],
      );

      // Every device class gets catalog-driven picks it can actually resolve,
      // and reduced-safety builds never rank above a normally aligned one.
      for (final (platform, type, ramGB) in const [
        ('android-arm64', DeviceType.mobile, 7.6),
        ('ios-arm64', DeviceType.mobile, 5.6),
        ('macos-arm64', DeviceType.desktop, 16.0),
        ('windows-x86_64', DeviceType.desktop, 32.0),
        ('linux-x86_64', DeviceType.desktop, 64.0),
      ]) {
        final device = DeviceProfile(
          type: type,
          ramBytes: (ramGB * 1024 * 1024 * 1024).round(),
          name: platform,
          platform: platform,
        );
        final resolved = const InferencePlanner().resolve(
          models: entries,
          device: device,
          backends: [
            BackendCapabilities(
              kind: BackendKind.llamaCpp,
              operational: true,
              platforms: [platform],
              formats: const ['gguf'],
            ),
          ],
          allowExperimental: true,
          memoryBudgetFraction: 0.85,
        );
        final runnable = {
          for (final candidate in resolved)
            candidate.model.id: candidate.variant,
        };
        final picks = recommendModel(
          device,
          catalog: entries,
          preferredVariants: runnable,
          editorial: editorial,
        );
        final ids = [
          picks.recommended.id,
          ...picks.alternatives.map((entry) => entry.id),
        ];
        expect(ids, hasLength(3), reason: platform);
        expect(runnable.keys, containsAll(ids), reason: platform);
        final reduced = [
          for (final id in ids)
            entries.firstWhere((entry) => entry.id == id).reducedSafety,
        ];
        final aligned = List<bool>.of(reduced)..sort(_falseFirst);
        expect(reduced, orderedEquals(aligned), reason: platform);
        expect(reduced.first, isFalse, reason: platform);
      }

      final manualOptions = const InferencePlanner().resolve(
        models: entries,
        device: flagshipIphone,
        backends: const [
          BackendCapabilities(
            kind: BackendKind.mlx,
            operational: true,
            platforms: ['ios-arm64'],
            formats: ['mlx'],
          ),
          BackendCapabilities(
            kind: BackendKind.llamaCpp,
            operational: true,
            platforms: ['ios-arm64'],
            formats: ['gguf'],
          ),
        ],
        allowExperimental: true,
        memoryBudgetFraction: 0.85,
      );
      expect(
        manualOptions.map((candidate) => candidate.model.id),
        containsAll([
          'gemma-4-e2b-it',
          'gemma-4-e4b-it',
          'gemma-3n-e2b-it',
          'gemma-3-4b-it',
          'bonsai-27b-q1',
        ]),
      );
    },
    skip: path == null
        ? 'Set EREBRUS_LIVE_CATALOG_PATH to a downloaded production payload'
        : false,
  );
}

int _falseFirst(bool a, bool b) => (a ? 1 : 0).compareTo(b ? 1 : 0);
