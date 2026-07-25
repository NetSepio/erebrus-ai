import 'dart:io';

import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/inference_contract.dart';
import 'package:erebrus_ai/services/llama_cpp_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath = String.fromEnvironment('BENCHMARK_MODEL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'retains one packaged llama.cpp model for consecutive turns',
    (tester) async {
      expect(File(_modelPath).existsSync(), isTrue);
      final platform = DeviceInfoService.detect().platform;
      final variant = ModelVariant(
        id: 'retained-smoke-test',
        modelId: 'retained-smoke-test',
        format: 'gguf',
        quantization: 'Q8_0',
        files: const [],
        platforms: [platform],
        compatibleBackends: const ['llama.cpp'],
      );
      final backend = LlamaCppBackend(platform: platform);
      final load = InferenceLoadRequest(
        variant: variant,
        packagePath: _modelPath,
        contextSize: 2048,
        gpuLayerCount: 0,
      );

      // ignore: avoid_print
      print('retained: loading');
      await backend.load(load).timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('retained: loaded');
      expect(backend.isLoaded, isTrue);
      const prompt =
          'Explain why private on-device inference is useful in two sentences.';
      final first = await _generate(backend, prompt);
      // ignore: avoid_print
      print('retained: first turn complete');
      await backend.load(load);
      final second = await _generate(backend, prompt);
      // ignore: avoid_print
      print('retained: second turn complete');

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(backend.loadedVariantId, variant.id);

      await backend.unload().timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('retained: unloaded');
      expect(backend.isLoaded, isFalse);
    },
    skip: _modelPath.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<String> _generate(LlamaCppBackend backend, String prompt) async {
  final text = StringBuffer();
  await for (final event in backend.generate(
    InferenceRequest(
      messages: [InferenceMessage(role: 'user', content: prompt)],
      sampling: const InferenceSampling(temperature: 0),
      maxOutputTokens: 64,
    ),
  )) {
    switch (event) {
      case InferenceToken(text: final token):
        text.write(token);
      case InferenceFailure(:final message):
        fail(message);
      case InferenceLoadCompleted() ||
          InferenceMetrics() ||
          InferenceCompleted():
        break;
    }
  }
  return text.toString().trim();
}
