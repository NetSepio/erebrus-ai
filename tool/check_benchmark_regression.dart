import 'dart:convert';
import 'dart:io';

/// Fails CI when a benchmark regresses beyond the release thresholds.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('Usage: check_benchmark_regression <baseline> <candidate>');
    exitCode = 64;
    return;
  }
  final baseline = _summary(arguments[0]);
  final candidate = _summary(arguments[1]);
  final failures = <String>[];
  _maximum(failures, 'load_ms', baseline, candidate, allowedIncrease: 0.20);
  _maximum(
    failures,
    'time_to_first_token_ms',
    baseline,
    candidate,
    allowedIncrease: 0.20,
  );
  _minimum(
    failures,
    'decode_tokens_per_second',
    baseline,
    candidate,
    allowedDecrease: 0.10,
  );
  if (baseline.containsKey('peak_memory_bytes') &&
      candidate.containsKey('peak_memory_bytes')) {
    _maximum(
      failures,
      'peak_memory_bytes',
      baseline,
      candidate,
      allowedIncrease: 0.15,
    );
  }
  if (failures.isNotEmpty) {
    stderr.writeln('Benchmark regression gate failed:');
    for (final failure in failures) {
      stderr.writeln('  - $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Benchmark regression gate passed.');
}

Map<String, num> _summary(String path) {
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  final raw = switch (decoded['summary']) {
    final Map<Object?, Object?> value => value.cast<String, Object?>(),
    _ => decoded,
  };
  num requiredMetric(String primary, String alternate) {
    final value = raw[primary] ?? raw[alternate];
    if (value is! num || !value.isFinite || value <= 0) {
      throw FormatException('$path has no valid $primary metric');
    }
    return value;
  }

  final result = <String, num>{
    'load_ms': requiredMetric('load_ms', 'average_load_ms'),
    'time_to_first_token_ms': requiredMetric(
      'time_to_first_token_ms',
      'average_time_to_first_token_ms',
    ),
    'decode_tokens_per_second': requiredMetric(
      'decode_tokens_per_second',
      'average_decode_tokens_per_second',
    ),
  };
  final peak = raw['peak_memory_bytes'] ?? raw['average_peak_memory_bytes'];
  if (peak is num && peak.isFinite && peak > 0) {
    result['peak_memory_bytes'] = peak;
  }
  return result;
}

void _maximum(
  List<String> failures,
  String metric,
  Map<String, num> baseline,
  Map<String, num> candidate, {
  required double allowedIncrease,
}) {
  final limit = baseline[metric]! * (1 + allowedIncrease);
  if (candidate[metric]! > limit) {
    failures.add(
      '$metric ${candidate[metric]} exceeds ${limit.toStringAsFixed(2)} '
      '(baseline ${baseline[metric]}, +${(allowedIncrease * 100).round()}%)',
    );
  }
}

void _minimum(
  List<String> failures,
  String metric,
  Map<String, num> baseline,
  Map<String, num> candidate, {
  required double allowedDecrease,
}) {
  final limit = baseline[metric]! * (1 - allowedDecrease);
  if (candidate[metric]! < limit) {
    failures.add(
      '$metric ${candidate[metric]} is below ${limit.toStringAsFixed(2)} '
      '(baseline ${baseline[metric]}, -${(allowedDecrease * 100).round()}%)',
    );
  }
}
