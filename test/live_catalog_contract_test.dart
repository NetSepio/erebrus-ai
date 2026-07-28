import 'dart:io';

import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final path = Platform.environment['EREBRUS_LIVE_CATALOG_PATH'];

  test(
    'production catalog satisfies the app contract',
    () async {
      final payload = await File(path!).readAsString();
      final entries = CatalogService.parsePayload(payload);
      final variants = entries.expand((entry) => entry.variants).toList();

      expect(entries, hasLength(27));
      expect(variants, hasLength(42));
      expect(
        variants.where((variant) => variant.format == 'mlx'),
        hasLength(12),
      );
      expect(
        variants.where((variant) => variant.provenance.isOfficial),
        hasLength(3),
      );

      const flagshipIphone = DeviceProfile(
        type: DeviceType.mobile,
        ramBytes: 12 * 1024 * 1024 * 1024,
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
      );
      expect(
        [
          recommendation.recommended.id,
          ...recommendation.alternatives.map((entry) => entry.id),
        ],
        ['gemma-3n-e2b-it', 'gemma-3-4b-it', 'phi-4-mini-instruct'],
      );
    },
    skip: path == null
        ? 'Set EREBRUS_LIVE_CATALOG_PATH to a downloaded production payload'
        : false,
  );
}
