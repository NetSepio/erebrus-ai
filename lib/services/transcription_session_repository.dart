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

  List<TranscriptionSession> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    _sessions.clear();
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'session.json'));
      if (!await file.exists()) continue;
      try {
        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        _sessions.add(TranscriptionSession.fromJson(decoded));
      } on Object {
        // A malformed session is ignored but its evidence remains on disk.
      }
    }
    _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<Directory> createSessionDirectory(String sessionId) async {
    final root = await _rootDirectoryProvider();
    final directory = Directory(p.join(root.path, _safeId(sessionId)));
    await directory.create(recursive: true);
    return directory;
  }

  Future<TranscriptionSession> finalize({
    required String sessionId,
    required DateTime createdAt,
    required Duration duration,
    required String locale,
    required String rawTranscript,
    required List<TranscriptSegment> segments,
    required String audioPath,
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
    );
    final now = DateTime.now().toUtc();
    final session = TranscriptionSession(
      id: sessionId,
      createdAt: createdAt.toUtc(),
      updatedAt: now,
      durationMilliseconds: duration.inMilliseconds,
      status: TranscriptionSessionStatus.complete,
      backend: TranscriptionBackendKind.speechAnalyzer,
      backendVersion: 'SpeechAnalyzer',
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
    _replace(session);
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
    _replace(updated);
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
        _replace(audioOnly);
        return;
      } else {
        await directory.delete(recursive: true);
      }
    }
    _sessions.removeWhere((session) => session.id == sessionId);
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

  Future<TranscriptionAudioMetadata?> _audioMetadata(File file) async {
    if (!await file.exists()) return null;
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    return TranscriptionAudioMetadata(
      relativePath: p.basename(file.path),
      container: p.extension(file.path).replaceFirst('.', '').toLowerCase(),
      codec: 'pcm',
      sampleRate: 0,
      channels: 0,
      sizeBytes: size,
      sha256: digest.toString(),
    );
  }

  void _replace(TranscriptionSession session) {
    _sessions.removeWhere((existing) => existing.id == session.id);
    _sessions.insert(0, session);
    notifyListeners();
  }

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
