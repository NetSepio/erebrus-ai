import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/inference_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalog variants', () {
    test('converts a schema 1.0 GGUF entry into a legacy variant', () {
      final entry = CatalogEntry.fromJson({
        'id': 'llama-3.2-1b',
        'name': 'Llama 3.2 1B',
        'family': 'Llama',
        'model': {'parameter_count': 1000000000},
        'device_support': {
          'platforms': ['ios-arm64', 'macos-arm64'],
          'minimum_ram_gb': 2,
          'recommended_ram_gb': 3,
        },
        'artifacts': [
          {
            'id': 'model-q4',
            'role': 'model',
            'format': 'gguf',
            'quantization': 'Q4_K_M',
            'filename': 'model.gguf',
            'download_url': 'https://example.test/model.gguf',
            'file_size_bytes': 123,
            'recommended': true,
            'backend': 'llama.cpp',
          },
        ],
        'runtime': {
          'preferred_backend': 'llama.cpp',
          'compatible_backends': ['llama.cpp'],
        },
      });

      expect(entry.variants, hasLength(1));
      expect(entry.variants.single.id, entry.id);
      expect(entry.variants.single.format, 'gguf');
      expect(entry.variants.single.compatibleBackends, ['llama.cpp']);
      expect(entry.preferredVariantId, entry.id);
      expect(entry.downloadUrl, 'https://example.test/model.gguf');
    });

    test('parses MLX packages but projects GGUF through legacy fields', () {
      final entry = _multiVariantEntry();

      expect(entry.variants, hasLength(2));
      expect(entry.variants.first.format, 'mlx');
      expect(entry.variants.first.files, hasLength(3));
      expect(entry.variants.first.sizeBytes, 110);
      expect(entry.preferredVariantId, 'llama-1b-gguf-q4');
      expect(entry.quant, 'Q4_K_M');
      expect(entry.downloadUrl, 'https://example.test/model.gguf');
      expect(entry.artifacts.single.filename, 'model.gguf');
    });

    test('does not expose MLX as a legacy GGUF download', () {
      final json = _multiVariantJson();
      json['variants'] = [(json['variants'] as List).first];

      final entry = CatalogEntry.fromJson(json);

      expect(entry.preferredVariant, isNull);
      expect(entry.downloadUrl, isEmpty);
      expect(entry.artifacts, isEmpty);
      expect(entry.variants.single.format, 'mlx');
    });

    test('parses official and community package provenance', () {
      final json = _multiVariantJson();
      final variants = json['variants'] as List<dynamic>;
      (variants[0] as Map<String, dynamic>)['provenance'] = {
        'kind': 'community_conversion',
        'publisher': 'mlx-community',
        'repository_id': 'mlx-community/Llama-1B-4bit',
        'upstream_repository_id': 'publisher/Llama-1B',
        'verification': 'immutable_revision_size_and_sha256',
      };
      (variants[1] as Map<String, dynamic>)['provenance'] = {
        'kind': 'official',
        'publisher': 'publisher',
        'repository_id': 'publisher/Llama-1B-GGUF',
      };

      final entry = CatalogEntry.fromJson(json);

      expect(entry.variants.first.provenance.isCommunityConversion, isTrue);
      expect(
        entry.variants.first.provenance.upstreamRepositoryId,
        'publisher/Llama-1B',
      );
      expect(entry.variants.last.provenance.isOfficial, isTrue);
      expect(entry.variants.last.provenance.label, 'OFFICIAL');
    });
  });

  group('InferencePlanner', () {
    test('prefers MLX over llama.cpp on Apple devices', () {
      final results = const InferencePlanner().resolve(
        models: [_multiVariantEntry()],
        device: _mac,
        backends: const [
          BackendCapabilities(
            kind: BackendKind.llamaCpp,
            operational: true,
            formats: ['gguf'],
          ),
          BackendCapabilities(
            kind: BackendKind.mlx,
            operational: true,
            formats: ['mlx'],
          ),
        ],
        installedVariantIds: {'llama-1b-mlx-4bit', 'llama-1b-gguf-q4'},
      );

      expect(results, hasLength(2));
      expect(results.first.backend, BackendKind.mlx);
      expect(results.first.variant.id, 'llama-1b-mlx-4bit');
    });

    test('prefers TurboQuant on a validated non-Apple runtime', () {
      final entry = CatalogEntry(
        id: 'qwen-compact',
        family: 'Qwen',
        name: 'Qwen Compact',
        quant: 'Q4_K_M',
        sizeBytes: 100,
        parameterB: 1,
        variants: const [
          ModelVariant(
            id: 'qwen-compact-gguf',
            modelId: 'qwen-compact',
            format: 'gguf',
            quantization: 'Q4_K_M',
            files: [],
            platforms: ['windows-x86_64'],
            compatibleBackends: ['turboquant', 'llama.cpp'],
            minimumRamGB: 1,
            recommendedRamGB: 2,
          ),
        ],
      );

      final results = const InferencePlanner().resolve(
        models: [entry],
        device: _windows,
        backends: const [
          BackendCapabilities(
            kind: BackendKind.llamaCpp,
            operational: true,
            formats: ['gguf'],
          ),
          BackendCapabilities(
            kind: BackendKind.turboQuant,
            operational: true,
            formats: ['gguf'],
          ),
        ],
      );

      expect(results.first.backend, BackendKind.turboQuant);
    });

    test('excludes variants that exceed the device memory budget', () {
      final results = const InferencePlanner().resolve(
        models: [_multiVariantEntry(minimumRamGB: 5)],
        device: _iphone,
        backends: const [
          BackendCapabilities(
            kind: BackendKind.mlx,
            operational: true,
            formats: ['mlx'],
          ),
          BackendCapabilities(
            kind: BackendKind.llamaCpp,
            operational: true,
            formats: ['gguf'],
          ),
        ],
      );

      expect(results, isEmpty);
    });
  });

  test('Nano catalog gives a 1 GB phone a sub-0.5B option', () {
    const constrainedPhone = DeviceProfile(
      type: DeviceType.mobile,
      ramBytes: 1024 * 1024 * 1024,
      name: 'Constrained phone',
      platform: 'android-arm64',
    );

    final recommendation = recommendModel(constrainedPhone);

    expect(recommendation.recommended.id, 'smollm2-135m-instruct');
    expect(recommendation.recommended.parameterB, lessThan(0.5));
    expect(
      recommendation.recommended.preferredVariant?.primaryArtifact?.sha256,
      hasLength(64),
    );
  });

  test('Nano catalog includes a complete verified Apple MLX package', () {
    final entry = modelCatalog.first;
    final mlx = entry.variants.singleWhere(
      (variant) => variant.format == 'mlx',
    );

    expect(mlx.platforms, containsAll(['ios-arm64', 'macos-arm64']));
    expect(mlx.compatibleBackends, ['mlx']);
    expect(
      mlx.files.map((file) => file.filename),
      containsAll([
        'config.json',
        'model.safetensors',
        'tokenizer.json',
        'tokenizer_config.json',
      ]),
    );
    expect(
      mlx.files.every(
        (file) =>
            file.revision.length == 40 &&
            file.sha256.length == 64 &&
            file.sizeBytes != null,
      ),
      isTrue,
    );
  });
}

CatalogEntry _multiVariantEntry({double minimumRamGB = 1}) {
  final json = _multiVariantJson();
  for (final variant in json['variants'] as List) {
    (variant as Map<String, dynamic>)['minimum_ram_gb'] = minimumRamGB;
  }
  return CatalogEntry.fromJson(json);
}

Map<String, dynamic> _multiVariantJson() => {
  'id': 'llama-3.2-1b',
  'name': 'Llama 3.2 1B',
  'family': 'Llama',
  'model': {'parameter_count': 1000000000},
  'device_support': {
    'platforms': ['ios-arm64', 'macos-arm64'],
    'minimum_ram_gb': 1,
    'recommended_ram_gb': 2,
  },
  'variants': [
    {
      'variant_id': 'llama-1b-mlx-4bit',
      'model_id': 'llama-3.2-1b',
      'format': 'mlx',
      'quantization': '4bit',
      'platforms': ['ios-arm64', 'macos-arm64'],
      'compatible_backends': ['mlx'],
      'minimum_ram_gb': 1,
      'recommended_ram_gb': 2,
      'files': [
        {
          'artifact_id': 'weights',
          'filename': 'model.safetensors',
          'download_url': 'https://example.test/model.safetensors',
          'file_size_bytes': 100,
        },
        {
          'artifact_id': 'config',
          'filename': 'config.json',
          'download_url': 'https://example.test/config.json',
          'file_size_bytes': 10,
        },
        {
          'artifact_id': 'optional-metadata',
          'filename': 'README.md',
          'download_url': 'https://example.test/README.md',
          'file_size_bytes': 5,
          'required': false,
        },
      ],
    },
    {
      'variant_id': 'llama-1b-gguf-q4',
      'model_id': 'llama-3.2-1b',
      'format': 'gguf',
      'quantization': 'Q4_K_M',
      'platforms': ['ios-arm64', 'macos-arm64'],
      'compatible_backends': ['llama.cpp'],
      'minimum_ram_gb': 1,
      'recommended_ram_gb': 2,
      'files': [
        {
          'artifact_id': 'model',
          'role': 'model',
          'filename': 'model.gguf',
          'download_url': 'https://example.test/model.gguf',
          'file_size_bytes': 123,
          'recommended': true,
        },
      ],
    },
  ],
};

const _mac = DeviceProfile(
  type: DeviceType.desktop,
  ramBytes: 16 * 1024 * 1024 * 1024,
  name: 'Test Mac',
  platform: 'macos-arm64',
);

const _iphone = DeviceProfile(
  type: DeviceType.mobile,
  ramBytes: 8 * 1024 * 1024 * 1024,
  name: 'Test iPhone',
  platform: 'ios-arm64',
);

const _windows = DeviceProfile(
  type: DeviceType.desktop,
  ramBytes: 16 * 1024 * 1024 * 1024,
  name: 'Test PC',
  platform: 'windows-x86_64',
);
