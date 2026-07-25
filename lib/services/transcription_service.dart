import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:erebrus_speech/erebrus_speech.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/transcription_session.dart';
import 'inference_service.dart';
import 'transcription_contract.dart';
import 'transcription_session_repository.dart';
import 'whisper_cpp_backend.dart';
import 'whisper_model_manager.dart';

enum TranscriptionUiState {
  ready,
  preparing,
  recording,
  paused,
  finalizing,
  complete,
  failed,
}

enum TranscriptionShareKind { transcript, audio, both }

class TranscriptionService extends ChangeNotifier {
  static final TranscriptionService instance = TranscriptionService();

  TranscriptionService({
    this.speech = const ErebrusSpeech(),
    TranscriptionSessionRepository? repository,
    AudioPlayer? audioPlayer,
    AudioRecorder? recorder,
  }) : _repository = repository ?? TranscriptionSessionRepository.instance,
       _audioPlayer = audioPlayer ?? AudioPlayer(),
       _recorder = recorder ?? AudioRecorder();

  final ErebrusSpeech speech;
  final TranscriptionSessionRepository _repository;
  final AudioPlayer _audioPlayer;
  final AudioRecorder _recorder;
  final List<TranscriptSegment> _segments = [];
  final Stopwatch _recordingClock = Stopwatch();

  StreamSubscription<SpeechTranscriptionEvent>? _subscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  TranscriptionUiState _state = TranscriptionUiState.ready;
  String _locale = 'en-US';
  String _partialText = '';
  String _error = '';
  String? _activeSessionId;
  TranscriptionSession? _current;
  Duration _playbackPosition = Duration.zero;
  bool _playing = false;
  bool _initialized = false;
  bool _usingWhisper = false;

  TranscriptionUiState get state => _state;
  Duration get elapsed => _elapsed;
  String get locale => _locale;
  String get partialText => _partialText;
  String get error => _error;
  String get finalizedText => _segments
      .map((segment) => segment.text.trim())
      .where((text) => text.isNotEmpty)
      .join(' ');
  String get visibleTranscript => [
    finalizedText,
    if (_partialText.trim().isNotEmpty) _partialText.trim(),
  ].where((text) => text.isNotEmpty).join(' ');
  List<TranscriptSegment> get segments => List.unmodifiable(_segments);
  List<TranscriptionSession> get sessions => _repository.sessions;
  TranscriptionSession? get current => _current;
  Duration get playbackPosition => _playbackPosition;
  bool get isPlaying => _playing;
  TranscriptionBackendKind get activeBackend => _usingWhisper
      ? TranscriptionBackendKind.whisperCpp
      : TranscriptionBackendKind.speechAnalyzer;

  List<TranscriptionSession> searchSessions(String query) =>
      _repository.search(query);

  Future<int> storageBytes() => _repository.storageBytes();

  Future<Directory> exportAll(
    Directory destination, {
    required bool userConsented,
  }) => _repository.exportTo(destination, userConsented: userConsented);

  Future<void> deleteAll() async {
    await _repository.deleteAll();
    _reset();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      _playbackPosition = position;
      notifyListeners();
    });
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      _playing = state == PlayerState.playing;
      notifyListeners();
    });
    await _repository.load();
    if (_repository.sessions.isNotEmpty) _current = _repository.sessions.first;
    notifyListeners();
  }

  Future<SpeechAnalyzerProbe> probe({String locale = 'en-US'}) =>
      speech.probe(locale: locale);

  Future<void> start({String locale = 'en-US'}) async {
    if (_state == TranscriptionUiState.recording ||
        _state == TranscriptionUiState.paused) {
      return;
    }
    _state = TranscriptionUiState.preparing;
    _error = '';
    _locale = locale;
    _segments.clear();
    _partialText = '';
    _elapsed = Duration.zero;
    _recordingClock
      ..reset()
      ..start();
    notifyListeners();

    try {
      final sessionId = const Uuid().v4();
      final directory = await _repository.createSessionDirectory(sessionId);
      _activeSessionId = sessionId;
      _startedAt = DateTime.now().toUtc();
      SpeechAnalyzerProbe? speechProbe;
      try {
        speechProbe = await speech.probe(locale: locale);
      } on Object {
        speechProbe = null;
      }
      final useSpeechAnalyzer =
          speechProbe?.available == true &&
          speechProbe?.localeSupported == true;
      _usingWhisper = !useSpeechAnalyzer;
      if (useSpeechAnalyzer) {
        await _subscription?.cancel();
        _subscription = speech.events.listen(
          _handleEvent,
          onError: (Object error) => _fail(error.toString()),
        );
        await speech.start(sessionDirectory: directory.path, locale: locale);
      } else {
        final modelPath = await WhisperModelManager.instance.installedPath();
        if (modelPath == null) {
          throw StateError(
            'Download the 74 MB Whisper Tiny fallback before recording on this device',
          );
        }
        if (!await _recorder.hasPermission()) {
          throw StateError('Microphone permission is required');
        }
        await InferenceService.instance.unload();
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: p.join(directory.path, 'audio.wav'),
        );
      }
      _state = TranscriptionUiState.recording;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == TranscriptionUiState.recording) {
          _elapsed = _recordingClock.elapsed;
          notifyListeners();
        }
      });
      notifyListeners();
    } on Object catch (error) {
      _fail(error.toString());
    }
  }

  Future<void> pause() async {
    if (_state != TranscriptionUiState.recording) return;
    if (_usingWhisper) {
      await _recorder.pause();
    } else {
      await speech.pause();
    }
    _recordingClock.stop();
    _elapsed = _recordingClock.elapsed;
    _state = TranscriptionUiState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != TranscriptionUiState.paused) return;
    if (_usingWhisper) {
      await _recorder.resume();
    } else {
      await speech.resume();
    }
    _recordingClock.start();
    _state = TranscriptionUiState.recording;
    notifyListeners();
  }

  Future<TranscriptionSession?> stop() async {
    if (_state != TranscriptionUiState.recording &&
        _state != TranscriptionUiState.paused) {
      return _current;
    }
    _state = TranscriptionUiState.finalizing;
    _ticker?.cancel();
    _recordingClock.stop();
    _elapsed = _recordingClock.elapsed;
    notifyListeners();
    try {
      final sessionId = _activeSessionId;
      final createdAt = _startedAt;
      if (sessionId == null || createdAt == null) {
        throw StateError('The transcription session identity was lost');
      }
      late final String raw;
      late final String audioPath;
      var backend = TranscriptionBackendKind.speechAnalyzer;
      var backendVersion = 'SpeechAnalyzer';
      if (_usingWhisper) {
        final recordedPath = await _recorder.stop();
        if (recordedPath == null) {
          throw StateError('The recorder did not return an audio file');
        }
        audioPath = recordedPath;
        await InferenceService.instance.unload();
        final modelPath = await WhisperModelManager.instance.installedPath();
        if (modelPath == null) {
          throw StateError('The verified Whisper model is unavailable');
        }
        final whisperBackend = WhisperCppBackend(modelPath: modelPath);
        await whisperBackend.prepare(TranscriptionConfig(locale: _locale));
        await for (final event in whisperBackend.transcribe(
          AudioInput.file(audioPath),
        )) {
          switch (event) {
            case TranscriptionSegmentUpdated(:final segment):
              _segments.add(segment);
              notifyListeners();
            case TranscriptionFailure(:final message):
              throw StateError(message);
            default:
              break;
          }
        }
        final result = await whisperBackend.finish();
        raw = result.text;
        backend = TranscriptionBackendKind.whisperCpp;
        backendVersion = 'whisper.cpp 1.8.3';
      } else {
        final result = await speech.stop();
        await _subscription?.cancel();
        _subscription = null;
        audioPath = result.audioPath;
        raw = result.transcript.trim().isEmpty
            ? finalizedText
            : result.transcript.trim();
      }
      _current = await _repository.finalize(
        sessionId: sessionId,
        createdAt: createdAt,
        duration: _elapsed,
        locale: _locale,
        rawTranscript: raw,
        segments: _segments,
        audioPath: audioPath,
        backend: backend,
        backendVersion: backendVersion,
        audioSampleRate: _usingWhisper ? 16000 : 0,
        audioChannels: _usingWhisper ? 1 : 0,
      );
      _partialText = '';
      _state = TranscriptionUiState.complete;
      notifyListeners();
      return _current;
    } on Object catch (error) {
      _fail(error.toString());
      return null;
    }
  }

  Future<void> cancel() async {
    _ticker?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    if (_usingWhisper) {
      await _recorder.cancel();
    } else {
      await speech.cancel();
    }
    _reset();
  }

  void selectSession(TranscriptionSession session) {
    _current = session;
    _state = TranscriptionUiState.complete;
    notifyListeners();
  }

  Future<void> editCurrent(String text) async {
    final current = _current;
    if (current == null) return;
    _current = await _repository.saveEdit(current, text);
    notifyListeners();
  }

  Future<void> playCurrent() async {
    final current = _current;
    if (current == null) return;
    final path = await _repository.audioPath(current);
    if (path == null) throw StateError('This session has no saved audio');
    if (_playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(path));
    }
  }

  Future<void> shareCurrent(TranscriptionShareKind kind) async {
    final current = _current;
    if (current == null) return;
    final audioPath = await _repository.audioPath(current);
    final includeTranscript = kind != TranscriptionShareKind.audio;
    final includeAudio = kind != TranscriptionShareKind.transcript;
    if (includeAudio && audioPath == null) {
      throw StateError('This session has no saved audio');
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Erebrus transcription',
        text: includeTranscript ? current.effectiveTranscript : null,
        files: includeAudio ? [XFile(audioPath!)] : null,
      ),
    );
  }

  Future<void> deleteCurrent({bool keepAudio = false}) async {
    final current = _current;
    if (current == null) return;
    await _repository.delete(current.id, keepAudio: keepAudio);
    _current = _repository.sessions.firstOrNull;
    _state = _current == null
        ? TranscriptionUiState.ready
        : TranscriptionUiState.complete;
    notifyListeners();
  }

  void newSession() => _reset();

  void _handleEvent(SpeechTranscriptionEvent event) {
    switch (event.type) {
      case 'partial':
        _partialText = event.text;
        break;
      case 'final':
        final segment = TranscriptSegment(
          id: '${event.startSeconds ?? 0}-${event.endSeconds ?? 0}-${_segments.length}',
          text: event.text,
          start: _seconds(event.startSeconds),
          end: _seconds(event.endSeconds),
          isFinal: true,
        );
        _segments.add(segment);
        _partialText = '';
        break;
      case 'error':
        _fail(event.message);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void _fail(String message) {
    _ticker?.cancel();
    _recordingClock.stop();
    _error = message;
    _state = TranscriptionUiState.failed;
    notifyListeners();
  }

  void _reset() {
    _ticker?.cancel();
    _recordingClock
      ..stop()
      ..reset();
    _state = TranscriptionUiState.ready;
    _segments.clear();
    _partialText = '';
    _error = '';
    _activeSessionId = null;
    _startedAt = null;
    _elapsed = Duration.zero;
    _current = null;
    notifyListeners();
  }

  static Duration _seconds(double? value) => Duration(
    microseconds: ((value ?? 0) * Duration.microsecondsPerSecond).round(),
  );

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_audioPlayer.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
