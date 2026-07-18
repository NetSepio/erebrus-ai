import 'mock_data.dart';

/// A single downloadable artifact (usually a GGUF model file or mmproj).
class Artifact {
  const Artifact({
    required this.id,
    required this.role,
    required this.format,
    required this.quantization,
    required this.filename,
    required this.repositoryId,
    required this.downloadUrl,
    this.fileSizeDisplay,
    this.sizeBytes,
    this.platforms = const [],
    this.recommended = false,
  });

  factory Artifact.fromJson(Map<String, dynamic> json) {
    final fileSizeDisplay = json['file_size_display'] as String?;
    return Artifact(
      id: (json['id'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      format: (json['format'] as String?) ?? '',
      quantization: (json['quantization'] as String?) ?? '',
      filename: (json['filename'] as String?) ?? '',
      repositoryId: (json['repository_id'] as String?) ?? '',
      downloadUrl: (json['download_url'] as String?) ?? '',
      fileSizeDisplay: fileSizeDisplay,
      sizeBytes: (json['file_size_bytes'] as int?) ?? parseFileSizeDisplay(fileSizeDisplay),
      platforms: _stringList(json['platforms']),
      recommended: json['recommended'] == true,
    );
  }

  final String id;
  final String role;
  final String format;
  final String quantization;
  final String filename;
  final String repositoryId;
  final String downloadUrl;
  final String? fileSizeDisplay;
  final int? sizeBytes;
  final List<String> platforms;
  final bool recommended;
}

/// A real open-source model that can be downloaded and run locally.
///
/// Can be constructed manually (legacy hard-coded catalog) or parsed from the
/// remote `models.json` published by Erebrus AI.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.family,
    required this.name,
    required this.quant,
    required this.sizeBytes,
    required this.parameterB,
    this.mobileFriendly = false,
    this.desktopFriendly = true,
    this.tags = const [],
    this.slug = '',
    this.variant = '',
    this.description = '',
    this.collections = const [],
    this.badges = const [],
    this.minRamGB = 0,
    this.recRamGB = 0,
    this.platforms = const [],
    this.tiers = const [],
    this.mobileStatus = '',
    this.recommendedTier = '',
    this.gpuRequired = false,
    this.gpuRecommended = false,
    this.artifacts = const [],
    this.downloadUrl = '',
    this.mmprojDownloadUrl = '',
    this.sortOrder = 0,
    this.featured = false,
    this.status = 'active',
    this.fileSizeDisplay = '',
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    final modelMap = json['model'] as Map<String, dynamic>?;
    final dsMap = json['device_support'] as Map<String, dynamic>?;
    final displayMap = json['display'] as Map<String, dynamic>?;
    final statusMap = json['status'] as Map<String, dynamic>?;

    final parameterCount =
        (modelMap?['parameter_count'] as num?)?.toDouble() ?? 0;
    final parameterLabel = (modelMap?['parameter_label'] as String?) ?? '';
    final parameterB = parameterCount > 0
        ? parameterCount / 1e9
        : parseParameterLabel(parameterLabel);

    final artifacts = (json['artifacts'] as List<dynamic>? ?? [])
        .map((a) => Artifact.fromJson(a as Map<String, dynamic>))
        .toList();

    final modelArtifact = artifacts.firstWhere(
      (a) => a.role == 'model' && a.recommended,
      orElse: () => artifacts.firstWhere(
        (a) => a.role == 'model',
        orElse: () => const Artifact(
          id: '',
          role: 'model',
          format: '',
          quantization: '',
          filename: '',
          repositoryId: '',
          downloadUrl: '',
        ),
      ),
    );
    final mmprojArtifact = artifacts.firstWhere(
      (a) => a.role == 'mmproj',
      orElse: () => const Artifact(
        id: '',
        role: '',
        format: '',
        quantization: '',
        filename: '',
        repositoryId: '',
        downloadUrl: '',
      ),
    );

    final artifactSizeBytes = modelArtifact.sizeBytes ??
        parseFileSizeDisplay(modelArtifact.fileSizeDisplay) ??
        0;
    final artifactSizeDisplay =
        modelArtifact.fileSizeDisplay ?? formatBytes(artifactSizeBytes);

    final tiers = _stringList(dsMap?['tiers']);
    final platforms = _stringList(dsMap?['platforms']);
    final mobileStatus = (dsMap?['mobile_status'] as String?) ?? '';

    final mobileFriendly = platforms.any((p) =>
            p.startsWith('android') ||
            p.startsWith('ios') ||
            p.startsWith('mobile')) ||
        tiers.any((t) =>
            t == 'mobile' ||
            t == 'tablet' ||
            t == 'flagship_mobile') ||
        mobileStatus == 'supported' ||
        mobileStatus == 'supported_on_recent_devices';

    final desktopFriendly = platforms.any((p) =>
            p.startsWith('macos') ||
            p.startsWith('windows') ||
            p.startsWith('linux') ||
            p.startsWith('desktop') ||
            p.startsWith('laptop')) ||
        tiers.any((t) =>
            t == 'laptop' ||
            t == 'desktop' ||
            t == 'gpu') ||
        platforms.isEmpty;

    return CatalogEntry(
      id: (json['id'] as String?) ?? '',
      slug: (json['slug'] as String?) ?? (json['id'] as String?) ?? '',
      family: (json['family'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      variant: (json['variant'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      quant: modelArtifact.quantization,
      sizeBytes: artifactSizeBytes,
      fileSizeDisplay: artifactSizeDisplay,
      parameterB: parameterB,
      mobileFriendly: mobileFriendly,
      desktopFriendly: desktopFriendly,
      tags: _stringList(json['tags']),
      collections: _stringList(json['collections']),
      badges: _stringList(displayMap?['badges']),
      minRamGB: (dsMap?['minimum_ram_gb'] as num?)?.toDouble() ?? 0,
      recRamGB: (dsMap?['recommended_ram_gb'] as num?)?.toDouble() ?? 0,
      platforms: platforms,
      tiers: tiers,
      mobileStatus: mobileStatus,
      recommendedTier: (dsMap?['recommended_tier'] as String?) ?? '',
      gpuRequired: dsMap?['gpu_required'] == true,
      gpuRecommended: dsMap?['gpu_recommended'] == true,
      artifacts: artifacts,
      downloadUrl: modelArtifact.downloadUrl,
      mmprojDownloadUrl: mmprojArtifact.downloadUrl,
      sortOrder: (displayMap?['sort_order'] as int?) ?? 0,
      featured: displayMap?['featured'] == true,
      status: (statusMap?['catalog_state'] as String?) ?? 'active',
    );
  }

  final String id;
  final String slug;
  final String family;
  final String name;
  final String variant;
  final String quant;
  final int sizeBytes;
  final String fileSizeDisplay;

  /// Billion parameters (e.g. 0.5, 7, 32).
  final double parameterB;

  /// Shown in the mobile catalog and considered for phone recommendations.
  final bool mobileFriendly;

  /// Shown in the desktop catalog and considered for desktop recommendations.
  final bool desktopFriendly;

  final List<String> tags;
  final List<String> collections;
  final List<String> badges;
  final String description;

  /// Minimum RAM required to run at all, in GB, from the catalog.
  final double minRamGB;

  /// RAM recommended for a comfortable run, in GB, from the catalog.
  final double recRamGB;

  /// Supported platforms such as `android-arm64`, `macos-arm64`.
  final List<String> platforms;

  /// Supported device tiers such as `mobile`, `laptop`, `desktop`.
  final List<String> tiers;

  /// Remote mobile status: `supported`, `supported_on_recent_devices`,
  /// `experimental`, `not_recommended`.
  final String mobileStatus;

  /// Recommended tier for this model.
  final String recommendedTier;

  final bool gpuRequired;
  final bool gpuRecommended;

  /// All artifacts for this model (model file + optional mmproj, etc.).
  final List<Artifact> artifacts;

  /// Direct download URL for the recommended model artifact.
  final String downloadUrl;

  /// Direct download URL for the mmproj artifact, when required.
  final String mmprojDownloadUrl;

  /// Catalog display order; lower numbers appear earlier.
  final int sortOrder;

  /// Whether the catalog flags this as featured.
  final bool featured;

  /// Catalog lifecycle state, e.g. `active`, `beta`, `deprecated`.
  final String status;

  String get letter => name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

  double get sizeGB => sizeBytes / (1024 * 1024 * 1024);

  /// Estimated RAM required to run this model comfortably.
  /// Prefer the catalog's [recRamGB] when available, otherwise derive from size.
  double get ramGB => recRamGB > 0 ? recRamGB : sizeGB * 1.25 + 0.3;

  String get spec => sizeBytes > 0
      ? '$quant · ${formatBytes(sizeBytes)}'
      : (fileSizeDisplay.isNotEmpty ? '$quant · $fileSizeDisplay' : quant);

  MockModel toMockModel({ModelStatus status = ModelStatus.catalog, bool accent = false}) =>
      MockModel(name, letter, spec, id: id, status: status, accent: accent);

  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        family.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q)) ||
        variant.toLowerCase().contains(q);
  }
}

String formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
  return '${(bytes / mb).round()} MB';
}

String formatGB(double gb) => gb >= 1
    ? '${gb.toStringAsFixed(1)} GB'
    : '${(gb * 1024).round()} MB';

/// Parses human-readable sizes like `533 MB` or `1.9 GB` into bytes.
int? parseFileSizeDisplay(String? display) {
  if (display == null || display.trim().isEmpty) return null;
  final match = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)\s*$')
      .firstMatch(display.trim());
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!) ?? 0;
  final unit = match.group(2)!.toLowerCase();
  if (unit.startsWith('gb')) return (value * 1024 * 1024 * 1024).round();
  if (unit.startsWith('mb')) return (value * 1024 * 1024).round();
  if (unit.startsWith('kb')) return (value * 1024).round();
  if (unit == 'b' || unit == 'bytes') return value.round();
  return null;
}

/// Parses a parameter label such as `0.8B` or `32B` into billions.
double parseParameterLabel(String label) {
  final s = label.toLowerCase().replaceAll('b', '').replaceAll(',', '').trim();
  return double.tryParse(s) ?? 0;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}
