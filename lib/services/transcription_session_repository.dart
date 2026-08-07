import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/transcription_session.dart';
import 'storage_service.dart';
import 'transcription_contract.dart';

class TranscriptionSessionRepository extends ChangeNotifier {
  static final TranscriptionSessionRepository instance =
      TranscriptionSessionRepository();

  TranscriptionSessionRepository({
    Future<Directory> Function()? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? StorageService.instance.transcriptionsDir;

  final Future<Directory> Function() _rootDirectoryProvider;
  final List<TranscriptionSession> _sessions = [];
  final Map<String, String> _searchDocuments = {};

  List<TranscriptionSession> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    _sessions.clear();
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'session.json'));
      TranscriptionSession? session;
      if (await file.exists()) {
        try {
          final decoded =
              jsonDecode(await file.readAsString()) as Map<String, Object?>;
          session = TranscriptionSession.fromJson(decoded);
        } on Object {
          // Preserve the directory and try to recover its audio below.
        }
      }
      session = await _recoverInterrupted(entity, session);
      if (session != null) _sessions.add(session);
    }
    _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _rebuildSearchIndex();
    notifyListeners();
  }

  List<TranscriptionSession> search(String query) {
    final terms = _terms(query);
    if (terms.isEmpty) return sessions;
    return _sessions
        .where((session) {
          final document = _searchDocuments[session.id] ?? '';
          return terms.every(document.contains);
        })
        .toList(growable: false);
  }

  Future<int> storageBytes() async {
    final root = await _rootDirectoryProvider();
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Copies the complete local transcription store to a user-selected folder.
  ///
  /// This API deliberately requires the UI to record explicit consent. The
  /// export contains transcripts and session audio, but never app credentials.
  Future<Directory> exportTo(
    Directory destination, {
    required bool userConsented,
  }) async {
    if (!userConsented) {
      throw StateError('Transcription export requires explicit user consent.');
    }
    final root = await _rootDirectoryProvider();
    final export = Directory(
      p.join(
        destination.path,
        'erebrus-transcriptions-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}',
      ),
    );
    await export.create(recursive: true);
    for (final session in _sessions) {
      final source = Directory(p.join(root.path, _safeId(session.id)));
      if (!await source.exists()) continue;
      final target = Directory(p.join(export.path, _safeId(session.id)));
      await target.create(recursive: true);
      await for (final entity in source.list()) {
        if (entity is! File) continue;
        await entity.copy(p.join(target.path, p.basename(entity.path)));
      }
    }
    await File(p.join(export.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'session_count': _sessions.length,
        'includes_audio': true,
        'source': 'Erebrus AI on-device transcription',
      }),
      flush: true,
    );
    return export;
  }

  Future<void> deleteAll() async {
    final root = await _rootDirectoryProvider();
    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else if (entity is File) {
          await entity.delete();
        }
      }
    }
    _sessions.clear();
    _searchDocuments.clear();
    notifyListeners();
  }

  Future<Directory> createSessionDirectory(String sessionId) async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(p.join(root.path, _safeId(sessionId)));
    await directory.create(recursive: true);
    return directory;
  }

  Future<TranscriptionSession> saveDraft({
    required String sessionId,
    required DateTime createdAt,
    required Duration duration,
    required String locale,
    required TranscriptionSessionStatus status,
    required TranscriptionBackendKind backend,
    required String backendVersion,
    required String rawTranscript,
    required List<TranscriptSegment> segments,
    String? audioPath,
    String? failureCode,
  }) async {
    final directory = await createSessionDirectory(sessionId);
    TranscriptionAudioMetadata? audio;
    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        audio = await _audioMetadata(
          file,
          codec: backend == TranscriptionBackendKind.whisperCpp ? 'pcm' : '',
          sampleRate: backend == TranscriptionBackendKind.whisperCpp
              ? 16000
              : 0,
          channels: backend == TranscriptionBackendKind.whisperCpp ? 1 : 0,
        );
      }
    }
    final session = TranscriptionSession(
      id: sessionId,
      createdAt: createdAt.toUtc(),
      updatedAt: DateTime.now().toUtc(),
      durationMilliseconds: duration.inMilliseconds,
      status: status,
      backend: backend,
      backendVersion: backendVersion,
      locale: locale,
      assetVersion: backend == TranscriptionBackendKind.speechAnalyzer
          ? 'system-managed'
          : 'verified-local',
      audio: audio,
      rawTranscript: rawTranscript,
      segments: segments
          .where((segment) => segment.isFinal)
          .map(StoredTranscriptSegment.fromTranscript)
          .toList(growable: false),
      failureCode: failureCode,
    );
    await _writeSession(directory, session);
    await _replace(session);
    return session;
  }

  Future<TranscriptionSession> finalize({
    required String sessionId,
    required DateTime createdAt,
    required Duration duration,
    required String locale,
    required String rawTranscript,
    required List<TranscriptSegment> segments,
    required String audioPath,
    TranscriptionBackendKind backend = TranscriptionBackendKind.speechAnalyzer,
    String backendVersion = 'SpeechAnalyzer',
    String audioCodec = 'pcm',
    int audioSampleRate = 0,
    int audioChannels = 0,
  }) async {
    final directory = await createSessionDirectory(sessionId);
    final sourceAudio = File(audioPath);
    final audioName = p.basename(audioPath);
    final destinationAudio = File(p.join(directory.path, audioName));
    if (sourceAudio.path != destinationAudio.path &&
        await sourceAudio.exists()) {
      await sourceAudio.copy(destinationAudio.path);
    }
    final storedAudio = await _audioMetadata(
      await destinationAudio.exists() ? destinationAudio : sourceAudio,
      codec: audioCodec,
      sampleRate: audioSampleRate,
      channels: audioChannels,
    );
    final now = DateTime.now().toUtc();
    final session = TranscriptionSession(
      id: sessionId,
      createdAt: createdAt.toUtc(),
      updatedAt: now,
      durationMilliseconds: duration.inMilliseconds,
      status: TranscriptionSessionStatus.complete,
      backend: backend,
      backendVersion: backendVersion,
      locale: locale,
      assetVersion: 'system-managed',
      audio: storedAudio,
      rawTranscript: rawTranscript,
      segments: segments
          .where((segment) => segment.isFinal)
          .map(StoredTranscriptSegment.fromTranscript)
          .toList(growable: false),
    );
    await _writeSession(directory, session);
    await _replace(session);
    return session;
  }

  Future<TranscriptionSession> saveEdit(
    TranscriptionSession session,
    String editedTranscript,
  ) async {
    final updated = TranscriptionSession(
      schemaVersion: session.schemaVersion,
      id: session.id,
      createdAt: session.createdAt,
      updatedAt: DateTime.now().toUtc(),
      durationMilliseconds: session.durationMilliseconds,
      status: session.status,
      backend: session.backend,
      backendVersion: session.backendVersion,
      locale: session.locale,
      assetVersion: session.assetVersion,
      audio: session.audio,
      rawTranscript: session.rawTranscript,
      editedTranscript: editedTranscript.trim(),
      segments: session.segments,
      analysisChatIds: session.analysisChatIds,
      failureCode: session.failureCode,
    );
    final directory = await createSessionDirectory(session.id);
    await _writeSession(directory, updated);
    await _replace(updated);
    return updated;
  }

  Future<void> delete(String sessionId, {bool keepAudio = false}) async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(p.join(root.path, _safeId(sessionId)));
    final existing = _sessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
    if (await directory.exists()) {
      if (keepAudio && existing != null && existing.audio != null) {
        await for (final entity in directory.list()) {
          if (entity is File &&
              !_isAudio(entity.path) &&
              p.basename(entity.path) != 'session.json') {
            await entity.delete();
          }
        }
        final audioOnly = TranscriptionSession(
          schemaVersion: existing.schemaVersion,
          id: existing.id,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now().toUtc(),
          durationMilliseconds: existing.durationMilliseconds,
          status: TranscriptionSessionStatus.complete,
          backend: existing.backend,
          backendVersion: existing.backendVersion,
          locale: existing.locale,
          assetVersion: existing.assetVersion,
          audio: existing.audio,
          rawTranscript: '',
          segments: const [],
          analysisChatIds: existing.analysisChatIds,
        );
        await File(p.join(directory.path, 'session.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(audioOnly.toJson()),
          flush: true,
        );
        await _replace(audioOnly);
        return;
      } else {
        await directory.delete(recursive: true);
      }
    }
    _sessions.removeWhere((session) => session.id == sessionId);
    _searchDocuments.remove(sessionId);
    await _writeSearchIndex();
    notifyListeners();
  }

  Future<String?> audioPath(TranscriptionSession session) async {
    final relativePath = session.audio?.relativePath;
    if (relativePath == null || relativePath.isEmpty) return null;
    final root = await _rootDirectoryProvider();
    final file = File(
      p.join(root.path, _safeId(session.id), p.basename(relativePath)),
    );
    return await file.exists() ? file.path : null;
  }

  Future<void> _writeSession(
    Directory directory,
    TranscriptionSession session,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await File(
      p.join(directory.path, 'session.json'),
    ).writeAsString(encoder.convert(session.toJson()), flush: true);
    await File(p.join(directory.path, 'transcript.raw.json')).writeAsString(
      encoder.convert({
        'text': session.rawTranscript,
        'segments': session.segments
            .map((segment) => segment.toJson())
            .toList(),
      }),
      flush: true,
    );
    await File(
      p.join(directory.path, 'transcript.txt'),
    ).writeAsString(session.rawTranscript, flush: true);
    final edited = session.editedTranscript;
    final editedFile = File(p.join(directory.path, 'transcript.edited.txt'));
    if (edited != null) {
      await editedFile.writeAsString(edited, flush: true);
    } else if (await editedFile.exists()) {
      await editedFile.delete();
    }
  }

  Future<TranscriptionAudioMetadata?> _audioMetadata(
    File file, {
    required String codec,
    required int sampleRate,
    required int channels,
  }) async {
    if (!await file.exists()) return null;
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    return TranscriptionAudioMetadata(
      relativePath: p.basename(file.path),
      container: p.extension(file.path).replaceFirst('.', '').toLowerCase(),
      codec: codec,
      sampleRate: sampleRate,
      channels: channels,
      sizeBytes: size,
      sha256: digest.toString(),
    );
  }

  Future<void> _replace(TranscriptionSession session) async {
    _sessions.removeWhere((existing) => existing.id == session.id);
    _sessions.insert(0, session);
    _searchDocuments[session.id] = _searchDocument(session);
    await _writeSearchIndex();
    notifyListeners();
  }

  Future<TranscriptionSession?> _recoverInterrupted(
    Directory directory,
    TranscriptionSession? session,
  ) async {
    if (session != null &&
        session.status != TranscriptionSessionStatus.recording &&
        session.status != TranscriptionSessionStatus.finalizing) {
      return session;
    }
    File? audioFile;
    await for (final entity in directory.list()) {
      if (entity is File && _isAudio(entity.path)) {
        audioFile = entity;
        break;
      }
    }
    if (session == null && audioFile == null) {
      // Empty preparation directories have no recoverable user evidence.
      await directory.delete(recursive: true);
      return null;
    }
    final stat = audioFile == null
        ? await directory.stat()
        : await audioFile.stat();
    final id = session?.id ?? p.basename(directory.path);
    final backend =
        session?.backend ??
        (p.extension(audioFile?.path ?? '').toLowerCase() == '.wav'
            ? TranscriptionBackendKind.whisperCpp
            : TranscriptionBackendKind.speechAnalyzer);
    final recovered = TranscriptionSession(
      id: id,
      createdAt: session?.createdAt ?? stat.modified.toUtc(),
      updatedAt: DateTime.now().toUtc(),
      durationMilliseconds: session?.durationMilliseconds ?? 0,
      status: TranscriptionSessionStatus.failed,
      backend: backend,
      backendVersion: session?.backendVersion ?? 'recovered',
      locale: session?.locale ?? 'auto',
      assetVersion: session?.assetVersion ?? 'recovered',
      audio: audioFile == null
          ? session?.audio
          : await _audioMetadata(
              audioFile,
              codec: backend == TranscriptionBackendKind.whisperCpp
                  ? 'pcm'
                  : '',
              sampleRate: backend == TranscriptionBackendKind.whisperCpp
                  ? 16000
                  : 0,
              channels: backend == TranscriptionBackendKind.whisperCpp ? 1 : 0,
            ),
      rawTranscript: session?.rawTranscript ?? '',
      editedTranscript: session?.editedTranscript,
      segments: session?.segments ?? const [],
      analysisChatIds: session?.analysisChatIds ?? const [],
      failureCode: 'interrupted_recording',
    );
    await _writeSession(directory, recovered);
    return recovered;
  }

  Future<void> _rebuildSearchIndex() async {
    _searchDocuments
      ..clear()
      ..addEntries(
        _sessions.map(
          (session) => MapEntry(session.id, _searchDocument(session)),
        ),
      );
    await _writeSearchIndex();
  }

  Future<void> _writeSearchIndex() async {
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    final destination = File(p.join(root.path, 'search-index.json'));
    final staging = File('${destination.path}.part');
    await staging.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'documents': _searchDocuments.entries
            .map((entry) => {'session_id': entry.key, 'text': entry.value})
            .toList(growable: false),
      }),
      flush: true,
    );
    if (await destination.exists()) await destination.delete();
    await staging.rename(destination.path);
  }

  static String _searchDocument(TranscriptionSession session) {
    // Intentionally excludes audio metadata, hashes, and filesystem paths.
    return _terms(
      '${session.rawTranscript} ${session.editedTranscript ?? ''} '
      '${session.locale} ${session.backend.name}',
    ).join(' ');
  }

  static List<String> _terms(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static String _safeId(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..') {
      throw ArgumentError.value(value, 'sessionId', 'Invalid session ID');
    }
    return safe;
  }

  static bool _isAudio(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.caf' ||
        extension == '.m4a' ||
        extension == '.wav' ||
        extension == '.mp3';
  }
}
