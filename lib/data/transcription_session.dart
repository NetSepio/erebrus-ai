import '../services/transcription_contract.dart';

enum TranscriptionSessionStatus { recording, finalizing, complete, failed }

enum TranscriptEditState { unedited, edited }

class TranscriptionAudioMetadata {
  const TranscriptionAudioMetadata({
    required this.relativePath,
    required this.container,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.sizeBytes,
    required this.sha256,
  });

  factory TranscriptionAudioMetadata.fromJson(Map<String, Object?> json) =>
      TranscriptionAudioMetadata(
        relativePath: json['relative_path'] as String? ?? '',
        container: json['container'] as String? ?? '',
        codec: json['codec'] as String? ?? '',
        sampleRate: json['sample_rate'] as int? ?? 0,
        channels: json['channels'] as int? ?? 0,
        sizeBytes: json['size_bytes'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );

  final String relativePath;
  final String container;
  final String codec;
  final int sampleRate;
  final int channels;
  final int sizeBytes;
  final String sha256;

  Map<String, Object?> toJson() => {
    'relative_path': relativePath,
    'container': container,
    'codec': codec,
    'sample_rate': sampleRate,
    'channels': channels,
    'size_bytes': sizeBytes,
    'sha256': sha256,
  };
}

class StoredTranscriptSegment {
  const StoredTranscriptSegment({
    required this.id,
    required this.text,
    required this.startMilliseconds,
    required this.endMilliseconds,
  });

  factory StoredTranscriptSegment.fromJson(Map<String, Object?> json) =>
      StoredTranscriptSegment(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        startMilliseconds: json['start_ms'] as int? ?? 0,
        endMilliseconds: json['end_ms'] as int? ?? 0,
      );

  factory StoredTranscriptSegment.fromTranscript(TranscriptSegment segment) =>
      StoredTranscriptSegment(
        id: segment.id,
        text: segment.text,
        startMilliseconds: segment.start.inMilliseconds,
        endMilliseconds: segment.end.inMilliseconds,
      );

  final String id;
  final String text;
  final int startMilliseconds;
  final int endMilliseconds;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'start_ms': startMilliseconds,
    'end_ms': endMilliseconds,
  };
}

class TranscriptionSession {
  const TranscriptionSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.durationMilliseconds,
    required this.status,
    required this.backend,
    required this.backendVersion,
    required this.locale,
    required this.assetVersion,
    required this.rawTranscript,
    required this.segments,
    this.audio,
    this.editedTranscript,
    this.analysisChatIds = const [],
    this.failureCode,
    this.schemaVersion = 1,
  });

  factory TranscriptionSession.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'] as List<Object?>? ?? const [];
    return TranscriptionSession(
      schemaVersion: json['schema_version'] as int? ?? 1,
      id: json['session_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      durationMilliseconds: json['duration_ms'] as int? ?? 0,
      status: TranscriptionSessionStatus.values.byName(
        json['status'] as String? ?? TranscriptionSessionStatus.failed.name,
      ),
      backend: TranscriptionBackendKind.values.byName(
        json['backend'] as String? ?? TranscriptionBackendKind.whisperCpp.name,
      ),
      backendVersion: json['backend_version'] as String? ?? '',
      locale: json['locale'] as String? ?? '',
      assetVersion: json['asset_version'] as String? ?? '',
      audio: switch (json['audio']) {
        final Map<Object?, Object?> value =>
          TranscriptionAudioMetadata.fromJson(value.cast<String, Object?>()),
        _ => null,
      },
      rawTranscript: json['raw_transcript'] as String? ?? '',
      editedTranscript: json['edited_transcript'] as String?,
      segments: rawSegments
          .map(
            (value) => StoredTranscriptSegment.fromJson(
              (value as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      analysisChatIds: (json['analysis_chat_ids'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      failureCode: json['failure_code'] as String?,
    );
  }

  final int schemaVersion;
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int durationMilliseconds;
  final TranscriptionSessionStatus status;
  final TranscriptionBackendKind backend;
  final String backendVersion;
  final String locale;
  final String assetVersion;
  final TranscriptionAudioMetadata? audio;
  final String rawTranscript;
  final String? editedTranscript;
  final List<StoredTranscriptSegment> segments;
  final List<String> analysisChatIds;
  final String? failureCode;

  TranscriptEditState get editState => editedTranscript == null
      ? TranscriptEditState.unedited
      : TranscriptEditState.edited;

  String get effectiveTranscript => editedTranscript ?? rawTranscript;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'session_id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'duration_ms': durationMilliseconds,
    'status': status.name,
    'backend': backend.name,
    'backend_version': backendVersion,
    'locale': locale,
    'asset_version': assetVersion,
    'audio': audio?.toJson(),
    'raw_transcript': rawTranscript,
    'edited_transcript': editedTranscript,
    'edit_state': editState.name,
    'segments': segments.map((segment) => segment.toJson()).toList(),
    'analysis_chat_ids': analysisChatIds,
    'failure_code': failureCode,
  };
}
