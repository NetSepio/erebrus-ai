import 'package:erebrus_ai/data/transcription_session.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'transcription session round-trips raw, edits, audio, and timecodes',
    () {
      final session = TranscriptionSession(
        id: 'session-1',
        createdAt: DateTime.utc(2026, 7, 25, 10),
        updatedAt: DateTime.utc(2026, 7, 25, 10, 1),
        durationMilliseconds: 4200,
        status: TranscriptionSessionStatus.complete,
        backend: TranscriptionBackendKind.speechAnalyzer,
        backendVersion: '26.0',
        locale: 'en-US',
        assetVersion: 'system-managed',
        audio: const TranscriptionAudioMetadata(
          relativePath: 'audio.m4a',
          container: 'm4a',
          codec: 'aac',
          sampleRate: 48000,
          channels: 1,
          sizeBytes: 1234,
          sha256: 'abc',
        ),
        rawTranscript: 'raw words',
        editedTranscript: 'corrected words',
        segments: const [
          StoredTranscriptSegment(
            id: 'segment-1',
            text: 'raw words',
            startMilliseconds: 100,
            endMilliseconds: 4100,
          ),
        ],
        analysisChatIds: const ['chat-1'],
      );

      final decoded = TranscriptionSession.fromJson(session.toJson());

      expect(decoded.id, session.id);
      expect(decoded.audio?.relativePath, 'audio.m4a');
      expect(decoded.segments.single.endMilliseconds, 4100);
      expect(decoded.editState, TranscriptEditState.edited);
      expect(decoded.effectiveTranscript, 'corrected words');
      expect(decoded.analysisChatIds, ['chat-1']);
    },
  );
}
