class ImportedModel {
  const ImportedModel({
    required this.id,
    required this.name,
    required this.format,
    required this.path,
    required this.sourcePath,
    required this.sizeBytes,
    required this.importedAt,
    this.architecture = '',
    this.quantization = '',
    this.parameterB = 0,
    this.reference = false,
    this.bookmark,
  });

  factory ImportedModel.fromJson(Map<String, Object?> json) => ImportedModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    format: json['format'] as String? ?? '',
    path: json['path'] as String? ?? '',
    sourcePath: json['source_path'] as String? ?? json['path'] as String? ?? '',
    sizeBytes: json['size_bytes'] as int? ?? 0,
    importedAt:
        DateTime.tryParse(json['imported_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    architecture: json['architecture'] as String? ?? '',
    quantization: json['quantization'] as String? ?? '',
    parameterB: (json['parameter_b'] as num?)?.toDouble() ?? 0,
    reference: json['reference'] == true,
    bookmark: json['bookmark'] as String?,
  );

  final String id;
  final String name;
  final String format;
  final String path;
  final String sourcePath;
  final int sizeBytes;
  final DateTime importedAt;
  final String architecture;
  final String quantization;
  final double parameterB;
  final bool reference;
  final String? bookmark;

  String get backend => format.toLowerCase() == 'mlx' ? 'mlx' : 'llama.cpp';
  String get variantId => 'imported-$id-$format';
  String get parameterLabel => parameterB <= 0
      ? ''
      : parameterB < 1
      ? '${(parameterB * 1000).round()}M'
      : '${parameterB.toStringAsFixed(parameterB % 1 == 0 ? 0 : 1)}B';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'format': format,
    'path': path,
    'source_path': sourcePath,
    'size_bytes': sizeBytes,
    'imported_at': importedAt.toUtc().toIso8601String(),
    'architecture': architecture,
    'quantization': quantization,
    'parameter_b': parameterB,
    'reference': reference,
    'bookmark': bookmark,
  };
}

class ImportedModelDraft {
  const ImportedModelDraft({
    required this.sourcePath,
    required this.name,
    required this.format,
    required this.sizeBytes,
    this.architecture = '',
    this.quantization = '',
    this.parameterB = 0,
  });

  final String sourcePath;
  final String name;
  final String format;
  final int sizeBytes;
  final String architecture;
  final String quantization;
  final double parameterB;

  ImportedModelDraft copyWith({
    String? name,
    String? architecture,
    String? quantization,
    double? parameterB,
  }) => ImportedModelDraft(
    sourcePath: sourcePath,
    name: name ?? this.name,
    format: format,
    sizeBytes: sizeBytes,
    architecture: architecture ?? this.architecture,
    quantization: quantization ?? this.quantization,
    parameterB: parameterB ?? this.parameterB,
  );
}
