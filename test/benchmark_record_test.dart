import 'package:erebrus_ai/services/benchmark_record.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benchmark summary produces stable machine-readable metrics', () {
    final summary = BenchmarkSummary([
      _record(load: 100, firstToken: 200, tokensPerSecond: 10),
      _record(load: 300, firstToken: 400, tokensPerSecond: 20),
    ]);

    expect(summary.averageLoadMilliseconds, 200);
    expect(summary.averageTimeToFirstTokenMilliseconds, 300);
    expect(summary.averageDecodeTokensPerSecond, 15);
    final json = summary.toJson();
    expect((json['runs'] as List), hasLength(2));
    expect((json['summary'] as Map)['run_count'], 2);
  });
}

InferenceBenchmarkRecord _record({
  required int load,
  required int firstToken,
  required double tokensPerSecond,
}) => InferenceBenchmarkRecord(
  schemaVersion: 1,
  recordedAt: DateTime.utc(2026, 7, 25),
  backend: BackendKind.llamaCpp,
  platform: 'test-platform',
  modelVariantId: 'test-variant',
  contextSize: 2048,
  prompt: 'test',
  generatedTokens: 10,
  loadMilliseconds: load,
  timeToFirstTokenMilliseconds: firstToken,
  totalGenerationMilliseconds: 1000,
  decodeTokensPerSecond: tokensPerSecond,
  finishReason: InferenceFinishReason.stop,
);
