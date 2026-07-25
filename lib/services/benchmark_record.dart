import 'inference_contract.dart';

class InferenceBenchmarkRecord {
  const InferenceBenchmarkRecord({
    required this.schemaVersion,
    required this.recordedAt,
    required this.backend,
    required this.platform,
    required this.modelVariantId,
    required this.contextSize,
    required this.prompt,
    required this.generatedTokens,
    required this.loadMilliseconds,
    required this.timeToFirstTokenMilliseconds,
    required this.totalGenerationMilliseconds,
    required this.decodeTokensPerSecond,
    required this.finishReason,
    this.promptTokensPerSecond,
    this.peakMemoryBytes,
    this.error,
  });

  final int schemaVersion;
  final DateTime recordedAt;
  final BackendKind backend;
  final String platform;
  final String modelVariantId;
  final int contextSize;
  final String prompt;
  final int generatedTokens;
  final int loadMilliseconds;
  final int timeToFirstTokenMilliseconds;
  final int totalGenerationMilliseconds;
  final double decodeTokensPerSecond;
  final InferenceFinishReason finishReason;
  final double? promptTokensPerSecond;
  final int? peakMemoryBytes;
  final String? error;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'backend': backend.catalogName,
    'platform': platform,
    'model_variant_id': modelVariantId,
    'context_size': contextSize,
    'prompt': prompt,
    'generated_tokens': generatedTokens,
    'load_ms': loadMilliseconds,
    'time_to_first_token_ms': timeToFirstTokenMilliseconds,
    'total_generation_ms': totalGenerationMilliseconds,
    'decode_tokens_per_second': decodeTokensPerSecond,
    'prompt_tokens_per_second': promptTokensPerSecond,
    'peak_memory_bytes': peakMemoryBytes,
    'finish_reason': finishReason.name,
    'error': error,
  };
}

class BenchmarkSummary {
  const BenchmarkSummary(this.records);

  final List<InferenceBenchmarkRecord> records;

  double get averageLoadMilliseconds =>
      _average(records.map((record) => record.loadMilliseconds.toDouble()));

  double get averageTimeToFirstTokenMilliseconds => _average(
    records.map((record) => record.timeToFirstTokenMilliseconds.toDouble()),
  );

  double get averageDecodeTokensPerSecond =>
      _average(records.map((record) => record.decodeTokensPerSecond));

  Map<String, Object?> toJson() => {
    'runs': records.map((record) => record.toJson()).toList(),
    'summary': {
      'run_count': records.length,
      'average_load_ms': averageLoadMilliseconds,
      'average_time_to_first_token_ms': averageTimeToFirstTokenMilliseconds,
      'average_decode_tokens_per_second': averageDecodeTokensPerSecond,
    },
  };

  static double _average(Iterable<double> values) {
    if (values.isEmpty) return 0;
    var total = 0.0;
    var count = 0;
    for (final value in values) {
      total += value;
      count++;
    }
    return total / count;
  }
}
