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

    test('uses the same 60 percent mobile budget as recommendations', () {
      final results = const InferencePlanner().resolve(
        models: [_multiVariantEntry(minimumRamGB: 4.5)],
        device: _iphone,
        backends: const [
          BackendCapabilities(
            kind: BackendKind.mlx,
            operational: true,
            formats: ['mlx'],
          ),
        ],
      );

      expect(results, isNotEmpty);
      expect(results.first.variant.id, 'llama-1b-mlx-4bit');
    });

    test('can expose minimum-fit experimental models as manual options', () {
      final entry = _mobileEntry(
        id: 'bonsai-27b-q1',
        name: 'Bonsai 27B Q1',
        parameterB: 27,
        tier: 'flagship_mobile',
        sortOrder: 250,
        minimumRamGB: 8,
        recommendedRamGB: 16,
        format: 'gguf',
        releaseChannel: 'experimental',
      );
      final results = const InferencePlanner().resolve(
        models: [entry],
        device: DeviceProfile(
          type: DeviceType.mobile,
          ramBytes: 12240656794,
          name: '12 GB-class iPhone',
          platform: 'ios-arm64',
        ),
        backends: const [
          BackendCapabilities(
            kind: BackendKind.llamaCpp,
            operational: true,
            formats: ['gguf'],
          ),
        ],
        allowExperimental: true,
        memoryBudgetFraction: 0.85,
      );

      expect(results, isNotEmpty);
      expect(results.first.model.id, 'bonsai-27b-q1');
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

  test('24 GB Mac recommends Qwen3.5 9B over minimum-fit 20B models', () {
    const mac = DeviceProfile(
      type: DeviceType.desktop,
      ramBytes: 24 * 1024 * 1024 * 1024,
      name: 'MacBook Pro',
      platform: 'macos-arm64',
    );
    const catalog = [
      CatalogEntry(
        id: 'qwen3.5-9b',
        family: 'Qwen3.5',
        name: 'Qwen3.5 9B',
        quant: 'Q4_K_M',
        sizeBytes: 6 * 1024 * 1024 * 1024,
        parameterB: 9,
        minRamGB: 10,
        recRamGB: 16,
        platforms: ['macos-arm64'],
        tiers: ['laptop', 'desktop'],
        recommendedTier: 'laptop',
        featured: true,
        sortOrder: 130,
      ),
      CatalogEntry(
        id: 'gpt-oss-20b',
        family: 'GPT-OSS',
        name: 'GPT-OSS 20B',
        quant: 'MXFP4',
        sizeBytes: 11 * 1024 * 1024 * 1024,
        parameterB: 20,
        minRamGB: 16,
        recRamGB: 24,
        platforms: ['macos-arm64'],
        tiers: ['desktop', 'gpu'],
        recommendedTier: 'desktop',
        featured: true,
        sortOrder: 200,
      ),
      CatalogEntry(
        id: 'mistral-small-3.1-24b-instruct',
        family: 'Mistral',
        name: 'Mistral Small 3.1 24B Instruct',
        quant: 'UD-IQ2_M',
        sizeBytes: 8 * 1024 * 1024 * 1024,
        parameterB: 24,
        minRamGB: 14,
        recRamGB: 24,
        platforms: ['macos-arm64'],
        tiers: ['desktop', 'gpu'],
        recommendedTier: 'desktop',
        sortOrder: 160,
      ),
    ];

    expect(recommendModel(mac, catalog: catalog).recommended.id, 'qwen3.5-9b');
  });

  test('12 GB flagship iPhone prioritizes optimized 4B-class models', () {
    const iphone = DeviceProfile(
      type: DeviceType.mobile,
      ramBytes: 12 * 1024 * 1024 * 1024,
      name: 'Flagship iPhone',
      platform: 'ios-arm64',
    );
    final gemma4 = _mobileEntry(
      id: 'gemma-3-4b-it',
      name: 'Gemma 3 4B IT',
      parameterB: 4,
      tier: 'high_end_mobile',
      sortOrder: 100,
      minimumRamGB: 4,
      recommendedRamGB: 6,
    );
    final gemmaE2 = _mobileEntry(
      id: 'gemma-3n-e2b-it',
      name: 'Gemma 3n E2B IT',
      parameterB: 2,
      tier: 'high_end_mobile',
      sortOrder: 70,
      minimumRamGB: 4,
      recommendedRamGB: 6,
    );
    final qwen2 = _mobileEntry(
      id: 'qwen3.5-2b',
      name: 'Qwen3.5 2B',
      parameterB: 2,
      tier: 'mobile',
      sortOrder: 20,
      minimumRamGB: 2.5,
      recommendedRamGB: 4,
      featured: true,
    );
    final smol = _mobileEntry(
      id: 'smollm2-360m-instruct',
      name: 'SmolLM2 360M Instruct',
      parameterB: 0.36,
      tier: 'mobile',
      sortOrder: 2,
      minimumRamGB: 0.8,
      recommendedRamGB: 1.3,
      featured: true,
    );
    final bonsai = _mobileEntry(
      id: 'bonsai-27b-q1',
      name: 'Bonsai 27B Q1',
      parameterB: 27,
      tier: 'flagship_mobile',
      sortOrder: 250,
      minimumRamGB: 8,
      recommendedRamGB: 16,
      featured: true,
      format: 'gguf',
    );
    final catalog = [smol, qwen2, gemmaE2, gemma4, bonsai];
    final preferredVariants = {
      for (final entry in catalog) entry.id: entry.variants.single,
    };

    final recommendation = recommendModel(
      iphone,
      catalog: catalog,
      preferredVariants: preferredVariants,
    );

    expect(
      [
        recommendation.recommended.id,
        ...recommendation.alternatives.map((entry) => entry.id),
      ],
      ['gemma-3-4b-it', 'gemma-3n-e2b-it', 'qwen3.5-2b'],
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

CatalogEntry _mobileEntry({
  required String id,
  required String name,
  required double parameterB,
  required String tier,
  required int sortOrder,
  required double minimumRamGB,
  required double recommendedRamGB,
  bool featured = false,
  String format = 'mlx',
  String releaseChannel = 'stable',
}) {
  final variant = ModelVariant(
    id: '$id-$format',
    modelId: id,
    format: format,
    quantization: '4bit',
    files: const [],
    platforms: const ['ios-arm64'],
    compatibleBackends: [format == 'mlx' ? 'mlx' : 'llama.cpp'],
    minimumRamGB: minimumRamGB,
    recommendedRamGB: recommendedRamGB,
    releaseChannel: releaseChannel,
  );
  return CatalogEntry(
    id: id,
    family: id,
    name: name,
    quant: '4bit',
    sizeBytes: 1,
    parameterB: parameterB,
    minRamGB: minimumRamGB,
    recRamGB: recommendedRamGB,
    platforms: const ['ios-arm64'],
    tiers: [tier],
    mobileStatus: 'experimental',
    recommendedTier: tier,
    sortOrder: sortOrder,
    featured: featured,
    variants: [variant],
    preferredVariantId: variant.id,
  );
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
