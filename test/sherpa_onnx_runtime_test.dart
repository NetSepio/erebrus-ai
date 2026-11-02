import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:erebrus_ai/services/sherpa_onnx_backend.dart';
import 'package:erebrus_ai/services/speech_package_manager.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs the real sherpa-onnx native runtime against the pinned packages.
///
/// Set EREBRUS_SHERPA_E2E_DIR to a folder with `moonshine/`, `parakeet/` and
/// `vad/` holding the pinned files plus a 16 kHz test WAV (`0.wav`,
/// `en.wav`, `de.wav`), as published in the upstream model repositories.
void main() {
  final root = Platform.environment['EREBRUS_SHERPA_E2E_DIR'];
  final skip = root == null
      ? 'Set EREBRUS_SHERPA_E2E_DIR to downloaded sherpa-onnx packages'
      : !Platform.isMacOS
      ? 'The host runtime check loads the macOS sherpa-onnx library'
      : false;

  // App builds link the library; a host test run loads it globally so the
  // worker isolate's process-wide symbol lookup finds it, as in the app.
  setUpAll(() {
    if (skip != false) return;
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, Object?>;
    final package = (config['packages']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((entry) => entry['name'] == 'sherpa_onnx_macos');
    final packageRoot = Uri.parse(package['rootUri']! as String).toFilePath();
    DynamicLibrary.open(
      p.join(
        packageRoot,
        'macos/sherpa_onnx_macos/sherpa-onnx.xcframework/macos-arm64_x86_64',
        'libsherpa-onnx-c-api.dylib',
      ),
    );
  });

  Future<String> stagePackage(SpeechPackageSpec spec, String folder) async {
    final staged = await Directory.systemTemp.createTemp('erebrus-e2e-');
    addTearDown(() => staged.delete(recursive: true));
    for (final file in spec.files) {
      final source = File(
        file.name == 'silero_vad.onnx'
            ? p.join(root!, 'vad', file.name)
            : p.join(root!, folder, file.name),
      );
      final digest = (await sha256.bind(source.openRead()).first).toString();
      expect(digest, file.sha256, reason: '${spec.id}/${file.name}');
      await Link(p.join(staged.path, file.name)).create(source.path);
    }
    return staged.path;
  }

  Future<FinalTranscript> transcribe(
    SpeechPackageSpec spec,
    String folder,
    String wav,
    String locale,
  ) async {
    final backend = SherpaOnnxBackend(
      spec: spec,
      packagePath: await stagePackage(spec, folder),
    );
    await backend.prepare(TranscriptionConfig(locale: locale));
    final events = await backend
        .transcribe(AudioInput.file(p.join(root!, folder, wav)))
        .toList();
    final failure = events.whereType<TranscriptionFailure>().firstOrNull;
    expect(failure, isNull, reason: failure?.message);
    final result = await backend.finish();
    // ignore: avoid_print
    print('${spec.displayName} · $wav: ${result.text}');
    return result;
  }

  void expectTimedSegments(FinalTranscript result) {
    expect(result.segments, isNotEmpty);
    for (final segment in result.segments) {
      expect(segment.end, greaterThan(segment.start));
    }
  }

  test('Moonshine Tiny transcribes English', () async {
    final result = await transcribe(
      SpeechPackageManager.moonshineTiny,
      'moonshine',
      '0.wav',
      'en-US',
    );

    expect(result.text.toLowerCase(), contains('after early nightfall'));
    expectTimedSegments(result);
  }, skip: skip);

  test(
    'Parakeet TDT v3 transcribes English and German',
    () async {
      final english = await transcribe(
        SpeechPackageManager.parakeetV3,
        'parakeet',
        'en.wav',
        'auto',
      );
      final german = await transcribe(
        SpeechPackageManager.parakeetV3,
        'parakeet',
        'de.wav',
        'de-DE',
      );

      expect(english.text, isNotEmpty);
      expect(german.text, isNotEmpty);
      expectTimedSegments(english);
      expectTimedSegments(german);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
