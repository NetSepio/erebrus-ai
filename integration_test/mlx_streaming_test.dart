import 'package:erebrus_mlx/erebrus_mlx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelDirectory = String.fromEnvironment('MLX_TEST_MODEL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'loads a local MLX package and streams generated text',
    (tester) async {
      final mlx = ErebrusMlx();
      final probe = await mlx.probe();
      expect(probe.available, isTrue);
      expect(probe.metalAvailable, isTrue);

      final loadWatch = Stopwatch()..start();
      await mlx.loadModel(_modelDirectory);
      loadWatch.stop();

      final generationWatch = Stopwatch()..start();
      Duration? firstToken;
      final text = StringBuffer();
      var completed = false;
      await for (final event
          in mlx
              .generate(
                messages: const [
                  {'role': 'system', 'content': 'Be concise.'},
                  {
                    'role': 'user',
                    'content': 'Reply with exactly three words about local AI.',
                  },
                ],
                maxTokens: 24,
                temperature: 0,
              )
              .timeout(const Duration(minutes: 2))) {
        if (event.type == 'token') {
          firstToken ??= generationWatch.elapsed;
          text.write(event.text);
        } else if (event.type == 'completed') {
          completed = true;
        } else if (event.type == 'error') {
          fail(event.message);
        }
      }
      generationWatch.stop();

      expect(completed, isTrue);
      expect(text.toString().trim(), isNotEmpty);
      expect(firstToken, isNotNull);

      // Visible in CI logs and suitable for the Phase 0 evidence record.
      // ignore: avoid_print
      print({
        'backend': 'mlx',
        'model': 'SmolLM-135M-Instruct-4bit',
        'load_ms': loadWatch.elapsedMilliseconds,
        'ttft_ms': firstToken!.inMilliseconds,
        'generation_ms': generationWatch.elapsedMilliseconds,
        'output': text.toString().trim(),
      });

      await mlx.unload();
    },
    skip: _modelDirectory.isEmpty,
  );
}
