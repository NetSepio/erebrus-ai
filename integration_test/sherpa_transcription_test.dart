import 'dart:io';

import 'package:erebrus_ai/services/sherpa_onnx_backend.dart';
import 'package:erebrus_ai/services/speech_package_manager.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Downloads the pinned Moonshine Tiny package (~120 MB) and transcribes the
/// upstream sample with the app's linked sherpa-onnx runtime. Opt in with
/// `--dart-define=EREBRUS_SHERPA_E2E=true`.
const _enabled = bool.fromEnvironment('EREBRUS_SHERPA_E2E');
const _sampleUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/'
    'resolve/bf2b762c076d8ea61e2af0b3851c9564fb77552e/test_wavs/0.wav';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('installs Moonshine and transcribes on device', (tester) async {
    final root = await Directory.systemTemp.createTemp('erebrus-sherpa-');
    addTearDown(() => root.delete(recursive: true));
    final manager = SpeechPackageManager(
      spec: SpeechPackageManager.moonshineTiny,
      directoryProvider: () async => root,
    );

    final packagePath = await manager.install();
    final wav = File(p.join(root.path, 'sample.wav'));
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse(_sampleUrl),
      )).close();
      await response.pipe(wav.openWrite());
    } finally {
      client.close();
    }

    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.moonshineTiny,
      packagePath: packagePath,
    );
    await backend.prepare(const TranscriptionConfig(locale: 'en-US'));
    final events = await backend.transcribe(AudioInput.file(wav.path)).toList();
    final failure = events.whereType<TranscriptionFailure>().firstOrNull;
    expect(failure, isNull, reason: failure?.message);
    final result = await backend.finish();

    expect(result.text.toLowerCase(), contains('after early nightfall'));
    expect(result.segments, isNotEmpty);
  }, skip: !_enabled);
}
