import 'dart:io';

import 'package:erebrus_ai/data/catalog_service.dart';
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
    },
    skip: path == null
        ? 'Set EREBRUS_LIVE_CATALOG_PATH to a downloaded production payload'
        : false,
  );
}
