import 'dart:convert';
import 'dart:io';

import 'package:erebrus_ai/services/benchmark_record.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';

const _modelPath = String.fromEnvironment('BENCHMARK_MODEL');
const _variantId = String.fromEnvironment(
  'BENCHMARK_VARIANT_ID',
  defaultValue: 'local-gguf',
);
const _prompt = String.fromEnvironment(
  'BENCHMARK_PROMPT',
  defaultValue:
      'Explain why private on-device inference is useful in two sentences.',
);
const _outputPath = String.fromEnvironment('BENCHMARK_OUTPUT');
const _contextSize = int.fromEnvironment(
  'BENCHMARK_CONTEXT',
  defaultValue: 2048,
);
const _maxTokens = int.fromEnvironment(
  'BENCHMARK_MAX_TOKENS',
  defaultValue: 128,
);
const _iterations = int.fromEnvironment(
  'BENCHMARK_ITERATIONS',
  defaultValue: 3,
);
const _gpuLayers = int.fromEnvironment('BENCHMARK_GPU_LAYERS', defaultValue: 0);

void main() {
  test(
    'records the current llama.cpp baseline',
    () async {
      expect(File(_modelPath).existsSync(), isTrue);
      final records = <InferenceBenchmarkRecord>[];
      for (var iteration = 1; iteration <= _iterations; iteration++) {
        // ignore: avoid_print
        print('Benchmark run $iteration/$_iterations');
        records.add(await _run());
      }

      final encoded = const JsonEncoder.withIndent(
        '  ',
      ).convert(BenchmarkSummary(records).toJson());
      if (_outputPath.isEmpty) {
        // ignore: avoid_print
        print(encoded);
      } else {
        final output = File(_outputPath);
        output.parent.createSync(recursive: true);
        output.writeAsStringSync('$encoded\n', flush: true);
        // ignore: avoid_print
        print('Wrote ${output.path}');
      }
    },
    skip: _modelPath.isEmpty
        ? 'Set --dart-define=BENCHMARK_MODEL=/absolute/model.gguf'
        : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<InferenceBenchmarkRecord> _run() async {
  final totalClock = Stopwatch()..start();
  var loadMilliseconds = 0;
  var firstTokenMilliseconds = 0;
  var tokenCount = 0;
  var finishReason = InferenceFinishReason.stop;
  String? failure;

  final commands = Stream<LlamaCommand>.fromIterable([
    LlamaLoadModelCommand(
      modelPath: _modelPath,
      contextSize: _contextSize,
      gpuLayerCount: _gpuLayers,
    ),
    LlamaGenerateMessagesCommand(
      messages: [LlamaMessage(role: 'user', content: _prompt)],
      maxTokens: _maxTokens,
      temperature: 0,
    ),
    const LlamaDisposeCommand(),
  ]);

  await for (final response in const LibLlamaCpp().transform(commands)) {
    switch (response) {
      case LlamaStateChangedResponse(:final state):
        if (state.isModelLoaded && loadMilliseconds == 0) {
          loadMilliseconds = totalClock.elapsedMilliseconds;
        }
      case LlamaTokenResponse():
        tokenCount++;
        if (tokenCount == 1) {
          firstTokenMilliseconds = totalClock.elapsedMilliseconds;
        }
      case LlamaErrorResponse(:final message):
        failure = message;
        finishReason = InferenceFinishReason.error;
      case LlamaDoneResponse():
        if (tokenCount >= _maxTokens) {
          finishReason = InferenceFinishReason.length;
        }
      case LlamaReadyResponse() || LlamaToolCallResponse():
        break;
    }
  }
  totalClock.stop();

  final decodeMilliseconds =
      totalClock.elapsedMilliseconds - firstTokenMilliseconds;
  final decodedTokens = tokenCount > 1 ? tokenCount - 1 : tokenCount;
  final decodeTokensPerSecond = decodeMilliseconds > 0
      ? decodedTokens / (decodeMilliseconds / 1000)
      : 0.0;

  return InferenceBenchmarkRecord(
    schemaVersion: 1,
    recordedAt: DateTime.now(),
    backend: BackendKind.llamaCpp,
    platform: Platform.operatingSystem,
    modelVariantId: _variantId,
    contextSize: _contextSize,
    prompt: _prompt,
    generatedTokens: tokenCount,
    loadMilliseconds: loadMilliseconds,
    timeToFirstTokenMilliseconds: firstTokenMilliseconds,
    totalGenerationMilliseconds: totalClock.elapsedMilliseconds,
    decodeTokensPerSecond: decodeTokensPerSecond,
    finishReason: finishReason,
    error: failure,
  );
}
