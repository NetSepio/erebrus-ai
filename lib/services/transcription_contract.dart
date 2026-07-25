enum TranscriptionBackendKind {
  speechAnalyzer,
  whisperCpp,
  androidOnDeviceRecognizer,
}

enum AudioInputKind { liveMicrophone, file }

class TranscriptionCapabilities {
  const TranscriptionCapabilities({
    required this.backend,
    required this.operational,
    this.onDevice = true,
    this.supportsLive = false,
    this.supportsFiles = false,
    this.supportsTimecodes = false,
    this.supportedLocales = const [],
    this.reason = '',
  });

  final TranscriptionBackendKind backend;
  final bool operational;
  final bool onDevice;
  final bool supportsLive;
  final bool supportsFiles;
  final bool supportsTimecodes;
  final List<String> supportedLocales;
  final String reason;
}

class TranscriptionConfig {
  const TranscriptionConfig({
    required this.locale,
    this.saveAudio = true,
    this.sampleRate = 16000,
    this.channels = 1,
  });

  final String locale;
  final bool saveAudio;
  final int sampleRate;
  final int channels;
}

class AudioInput {
  const AudioInput.live() : kind = AudioInputKind.liveMicrophone, filePath = '';

  const AudioInput.file(this.filePath) : kind = AudioInputKind.file;

  final AudioInputKind kind;
  final String filePath;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.text,
    required this.start,
    required this.end,
    required this.isFinal,
  });

  final String id;
  final String text;
  final Duration start;
  final Duration end;
  final bool isFinal;
}

class FinalTranscript {
  const FinalTranscript({
    required this.text,
    required this.segments,
    this.audioPath,
  });

  final String text;
  final List<TranscriptSegment> segments;
  final String? audioPath;
}

sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

class TranscriptionSegmentUpdated extends TranscriptionEvent {
  const TranscriptionSegmentUpdated(this.segment);

  final TranscriptSegment segment;
}

class TranscriptionAudioLevel extends TranscriptionEvent {
  const TranscriptionAudioLevel(this.normalizedLevel);

  final double normalizedLevel;
}

class TranscriptionAssetProgress extends TranscriptionEvent {
  const TranscriptionAssetProgress(this.progress);

  final double progress;
}

class TranscriptionFailure extends TranscriptionEvent {
  const TranscriptionFailure({
    required this.code,
    required this.message,
    required this.recoverable,
  });

  final String code;
  final String message;
  final bool recoverable;
}

abstract interface class TranscriptionBackend {
  TranscriptionBackendKind get kind;

  Future<TranscriptionCapabilities> probe();
  Future<void> prepare(TranscriptionConfig config);
  Stream<TranscriptionEvent> transcribe(AudioInput input);
  Future<FinalTranscript> finish();
  Future<void> cancel();
}
