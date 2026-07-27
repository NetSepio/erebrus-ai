import 'dart:convert';

import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogService.parsePayload', () {
    test('accepts a verified schema 1.2 multi-variant catalog', () {
      final entries = CatalogService.parsePayload(jsonEncode(_catalog()));

      expect(entries, hasLength(1));
      expect(entries.single.id, 'qwen-small');
      expect(entries.single.variants, hasLength(2));
      expect(entries.single.variants.first.provenance.isOfficial, isTrue);
      expect(
        entries.single.variants.last.provenance.isCommunityConversion,
        isTrue,
      );
    });

    test('rejects unsupported schema versions', () {
      final catalog = _catalog()..['schema_version'] = '2.0.0';

      expect(
        () => CatalogService.parsePayload(jsonEncode(catalog)),
        throwsFormatException,
      );
    });

    test('rejects duplicate package ids', () {
      final catalog = _catalog();
      final variants =
          ((catalog['models'] as List).single as Map)['variants'] as List;
      (variants.last as Map)['variant_id'] =
          (variants.first as Map)['variant_id'];

      expect(
        () => CatalogService.parsePayload(jsonEncode(catalog)),
        throwsFormatException,
      );
    });

    test('rejects mutable or unverified required files', () {
      final catalog = _catalog();
      final variants =
          ((catalog['models'] as List).single as Map)['variants'] as List;
      final files = (variants.first as Map)['files'] as List;
      (files.single as Map)['revision'] = 'main';
      (files.single as Map).remove('sha256');

      expect(
        () => CatalogService.parsePayload(jsonEncode(catalog)),
        throwsFormatException,
      );
    });
  });
}

Map<String, Object?> _catalog() => {
  'schema_version': '1.2.0',
  'models': [
    {
      'id': 'qwen-small',
      'name': 'Qwen Small',
      'family': 'Qwen',
      'model': {'parameter_count': 800000000},
      'device_support': {
        'platforms': ['ios-arm64', 'macos-arm64'],
        'minimum_ram_gb': 1,
        'recommended_ram_gb': 2,
      },
      'variants': [
        _variant(
          id: 'qwen-small-gguf',
          format: 'gguf',
          backend: 'llama.cpp',
          publisher: 'Qwen',
          provenance: 'official',
        ),
        _variant(
          id: 'qwen-small-mlx',
          format: 'mlx',
          backend: 'mlx',
          publisher: 'mlx-community',
          provenance: 'community_conversion',
        ),
      ],
    },
  ],
};

Map<String, Object?> _variant({
  required String id,
  required String format,
  required String backend,
  required String publisher,
  required String provenance,
}) => {
  'variant_id': id,
  'model_id': 'qwen-small',
  'format': format,
  'quantization': '4bit',
  'platforms': ['ios-arm64', 'macos-arm64'],
  'compatible_backends': [backend],
  'provenance': {
    'kind': provenance,
    'publisher': publisher,
    'repository_id': '$publisher/qwen-small',
  },
  'files': [
    {
      'artifact_id': '$id-model',
      'role': 'model',
      'format': format == 'mlx' ? 'safetensors' : 'gguf',
      'filename': format == 'mlx' ? 'model.safetensors' : 'model.gguf',
      'repository_id': '$publisher/qwen-small',
      'revision': 'a'.padRight(40, 'a'),
      'download_url': 'https://example.test/$id/model',
      'file_size_bytes': 1024,
      'sha256': 'b'.padRight(64, 'b'),
      'backend': backend,
    },
  ],
};
