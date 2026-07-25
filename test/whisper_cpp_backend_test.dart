import 'dart:io';

import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:erebrus_ai/services/whisper_cpp_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'maps whisper.cpp file output into the transcription contract',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'whisper-backend-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final model = File('${directory.path}/model.bin');
      final audio = File('${directory.path}/audio.wav');
      await model.writeAsBytes([1]);
      await audio.writeAsBytes([2]);
      final runtime = _FakeWhisperRuntime();
      final backend = WhisperCppBackend(
        modelPath: model.path,
        runtime: runtime,
      );

      expect((await backend.probe()).operational, isTrue);
      await backend.prepare(const TranscriptionConfig(locale: 'en-US'));
      final events = await backend
          .transcribe(AudioInput.file(audio.path))
          .toList();
      final result = await backend.finish();

      expect(events.whereType<TranscriptionSegmentUpdated>(), hasLength(1));
      expect(result.text, 'offline words');
      expect(result.segments.single.start, const Duration(seconds: 1));
      expect(runtime.language, 'en');
      expect(runtime.disposed, isTrue);
    },
  );

  test('requires a verified local model and a saved audio file', () async {
    final backend = WhisperCppBackend(
      modelPath: '/missing/model.bin',
      runtime: _FakeWhisperRuntime(),
    );

    expect((await backend.probe()).operational, isFalse);
    expect(
      await backend.transcribe(const AudioInput.live()).single,
      isA<TranscriptionFailure>(),
    );
  });
}

class _FakeWhisperRuntime implements WhisperRuntime {
  String language = '';
  bool disposed = false;

  @override
  Future<void> abort() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<WhisperRuntimeResult> transcribe({
    required String modelPath,
    required String audioPath,
    required String language,
  }) async {
    this.language = language;
    return const WhisperRuntimeResult(
      text: 'offline words',
      segments: [
        TranscriptSegment(
          id: 'one',
          text: 'offline words',
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          isFinal: true,
        ),
      ],
    );
  }
}
