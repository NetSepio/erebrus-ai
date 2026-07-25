import 'dart:io';

import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:erebrus_ai/services/transcription_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late TranscriptionSessionRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('erebrus-transcriptions-');
    repository = TranscriptionSessionRepository(
      rootDirectoryProvider: () async => root,
    );
  });

  tearDown(() async {
    repository.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'finalized session preserves audio, raw text, timecodes, and edits',
    () async {
      final directory = await repository.createSessionDirectory('session-1');
      final audio = File('${directory.path}/capture.caf');
      await audio.writeAsBytes([1, 2, 3, 4]);

      final session = await repository.finalize(
        sessionId: 'session-1',
        createdAt: DateTime.utc(2026, 7, 25),
        duration: const Duration(seconds: 3),
        locale: 'en-US',
        rawTranscript: 'raw words',
        segments: const [
          TranscriptSegment(
            id: 'one',
            text: 'raw words',
            start: Duration.zero,
            end: Duration(seconds: 3),
            isFinal: true,
          ),
        ],
        audioPath: audio.path,
        audioSampleRate: 16000,
        audioChannels: 1,
      );
      final edited = await repository.saveEdit(session, 'corrected words');

      expect(edited.rawTranscript, 'raw words');
      expect(edited.effectiveTranscript, 'corrected words');
      expect(edited.audio?.sha256, isNotEmpty);
      expect(edited.audio?.sampleRate, 16000);
      expect(edited.audio?.channels, 1);
      expect(File('${directory.path}/session.json').existsSync(), isTrue);
      expect(
        File('${directory.path}/transcript.raw.json').existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}/transcript.txt').readAsStringSync(),
        'raw words',
      );
      expect(
        File('${directory.path}/transcript.edited.txt').readAsStringSync(),
        'corrected words',
      );

      final restored = TranscriptionSessionRepository(
        rootDirectoryProvider: () async => root,
      );
      await restored.load();
      expect(restored.sessions.single.effectiveTranscript, 'corrected words');
      restored.dispose();
    },
  );

  test('delete can remove transcript metadata while retaining audio', () async {
    final directory = await repository.createSessionDirectory('session-2');
    final audio = File('${directory.path}/capture.caf');
    await audio.writeAsBytes([1]);
    await repository.finalize(
      sessionId: 'session-2',
      createdAt: DateTime.utc(2026, 7, 25),
      duration: const Duration(seconds: 1),
      locale: 'en-US',
      rawTranscript: 'hello',
      segments: const [],
      audioPath: audio.path,
    );

    await repository.delete('session-2', keepAudio: true);

    expect(audio.existsSync(), isTrue);
    expect(File('${directory.path}/session.json').existsSync(), isTrue);
    expect(repository.sessions.single.rawTranscript, isEmpty);
    expect(repository.sessions.single.audio, isNotNull);
  });
}
