class InstalledModelFile {
  const InstalledModelFile({
    required this.artifactId,
    required this.relativePath,
    required this.sizeBytes,
    required this.sha256,
  });

  factory InstalledModelFile.fromJson(Map<String, Object?> json) =>
      InstalledModelFile(
        artifactId: json['artifact_id'] as String? ?? '',
        relativePath: json['relative_path'] as String? ?? '',
        sizeBytes: json['size_bytes'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );

  final String artifactId;
  final String relativePath;
  final int sizeBytes;
  final String sha256;

  Map<String, Object?> toJson() => {
    'artifact_id': artifactId,
    'relative_path': relativePath,
    'size_bytes': sizeBytes,
    'sha256': sha256,
  };
}

class InstalledModel {
  const InstalledModel({
    required this.modelId,
    required this.variantId,
    required this.format,
    required this.backends,
    required this.installedAt,
    required this.verifiedAt,
    required this.files,
    required this.runnable,
    this.failureCode,
    this.schemaVersion = 1,
  });

  factory InstalledModel.fromJson(Map<String, Object?> json) => InstalledModel(
    schemaVersion: json['schema_version'] as int? ?? 1,
    modelId: json['model_id'] as String? ?? '',
    variantId: json['variant_id'] as String? ?? '',
    format: json['format'] as String? ?? '',
    backends: (json['backends'] as List<Object?>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    installedAt: DateTime.parse(json['installed_at'] as String).toUtc(),
    verifiedAt: DateTime.parse(json['verified_at'] as String).toUtc(),
    files: (json['files'] as List<Object?>? ?? const [])
        .map(
          (value) => InstalledModelFile.fromJson(
            (value as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false),
    runnable: json['runnable'] == true,
    failureCode: json['failure_code'] as String?,
  );

  final int schemaVersion;
  final String modelId;
  final String variantId;
  final String format;
  final List<String> backends;
  final DateTime installedAt;
  final DateTime verifiedAt;
  final List<InstalledModelFile> files;
  final bool runnable;
  final String? failureCode;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'model_id': modelId,
    'variant_id': variantId,
    'format': format,
    'backends': backends,
    'installed_at': installedAt.toUtc().toIso8601String(),
    'verified_at': verifiedAt.toUtc().toIso8601String(),
    'files': files.map((file) => file.toJson()).toList(),
    'runnable': runnable,
    'failure_code': failureCode,
  };
}
