import 'dart:io';

import 'package:erebrus_ai/data/transcription_session.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:erebrus_ai/services/transcription_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
      final audio = File(p.join(directory.path, 'capture.caf'));
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
      final linked = await repository.addAnalysisChat(edited, 'chat-123');

      expect(linked.rawTranscript, 'raw words');
      expect(linked.effectiveTranscript, 'corrected words');
      expect(linked.analysisChatIds, ['chat-123']);
      expect(linked.audio?.sha256, isNotEmpty);
      expect(linked.audio?.sampleRate, 16000);
      expect(linked.audio?.channels, 1);
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
      expect(restored.sessions.single.analysisChatIds, ['chat-123']);
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

  test('local index follows edits and excludes audio metadata', () async {
    final directory = await repository.createSessionDirectory('searchable');
    final audio = File('${directory.path}/private-recording.caf');
    await audio.writeAsBytes([1, 2]);
    final session = await repository.finalize(
      sessionId: 'searchable',
      createdAt: DateTime.utc(2026, 7, 25),
      duration: const Duration(seconds: 1),
      locale: 'en-US',
      rawTranscript: 'Roadmap alpha',
      segments: const [],
      audioPath: audio.path,
    );

    expect(repository.search('roadmap').single.id, 'searchable');
    expect(repository.search('private-recording'), isEmpty);
    await repository.saveEdit(session, 'Launch beta');
    expect(repository.search('launch beta').single.id, 'searchable');
    expect(repository.search('roadmap').single.id, 'searchable');
    final index = await File('${root.path}/search-index.json').readAsString();
    expect(index, isNot(contains('private-recording')));
    expect(index, isNot(contains(audio.path)));
  });

  test(
    'export requires consent and delete all removes local evidence',
    () async {
      final directory = await repository.createSessionDirectory('exportable');
      final audio = File('${directory.path}/audio.wav');
      await audio.writeAsBytes([1, 2, 3]);
      await repository.finalize(
        sessionId: 'exportable',
        createdAt: DateTime.utc(2026, 7, 25),
        duration: const Duration(seconds: 1),
        locale: 'en-US',
        rawTranscript: 'export me',
        segments: const [],
        audioPath: audio.path,
      );
      final destination = await Directory.systemTemp.createTemp(
        'erebrus-export-',
      );
      addTearDown(() async {
        if (await destination.exists()) {
          await destination.delete(recursive: true);
        }
      });

      await expectLater(
        repository.exportTo(destination, userConsented: false),
        throwsStateError,
      );
      final exported = await repository.exportTo(
        destination,
        userConsented: true,
      );
      expect(File('${exported.path}/manifest.json').existsSync(), isTrue);
      expect(
        File('${exported.path}/exportable/audio.wav').existsSync(),
        isTrue,
      );

      await repository.deleteAll();
      expect(repository.sessions, isEmpty);
      expect(await root.list().isEmpty, isTrue);
    },
  );

  test('interrupted draft is recovered with transcript and audio', () async {
    final directory = await repository.createSessionDirectory('interrupted');
    final audio = File(p.join(directory.path, 'audio.wav'));
    await audio.writeAsBytes([1, 2, 3, 4]);
    await repository.saveDraft(
      sessionId: 'interrupted',
      createdAt: DateTime.utc(2026, 8, 7),
      duration: const Duration(seconds: 12),
      locale: 'en-US',
      status: TranscriptionSessionStatus.recording,
      backend: TranscriptionBackendKind.whisperCpp,
      backendVersion: 'whisper.cpp 1.8.3',
      rawTranscript: 'checkpointed words',
      segments: const [
        TranscriptSegment(
          id: 'checkpoint',
          text: 'checkpointed words',
          start: Duration.zero,
          end: Duration(seconds: 2),
          isFinal: true,
        ),
      ],
    );

    final restored = TranscriptionSessionRepository(
      rootDirectoryProvider: () async => root,
    );
    await restored.load();
    final recovered = restored.sessions.single;
    expect(recovered.status, TranscriptionSessionStatus.failed);
    expect(recovered.failureCode, 'interrupted_recording');
    expect(recovered.rawTranscript, 'checkpointed words');
    expect(recovered.audio?.relativePath, 'audio.wav');
    expect(await restored.audioPath(recovered), audio.path);
    restored.dispose();
  });

  test('orphan audio without a manifest is recovered', () async {
    final directory = await repository.createSessionDirectory('orphan');
    final audio = File(p.join(directory.path, 'capture.caf'));
    await audio.writeAsBytes([9, 8, 7]);

    final restored = TranscriptionSessionRepository(
      rootDirectoryProvider: () async => root,
    );
    await restored.load();
    final recovered = restored.sessions.single;
    expect(recovered.id, 'orphan');
    expect(recovered.status, TranscriptionSessionStatus.failed);
    expect(recovered.audio?.relativePath, 'capture.caf');
    expect(File(p.join(directory.path, 'session.json')).existsSync(), isTrue);
    restored.dispose();
  });
}
