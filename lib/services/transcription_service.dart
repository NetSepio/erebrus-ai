import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:erebrus_speech/erebrus_speech.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/transcription_session.dart';
import 'transcription_contract.dart';
import 'transcription_session_repository.dart';

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
  }) : _repository = repository ?? TranscriptionSessionRepository.instance,
       _audioPlayer = audioPlayer ?? AudioPlayer();

  final ErebrusSpeech speech;
  final TranscriptionSessionRepository _repository;
  final AudioPlayer _audioPlayer;
  final List<TranscriptSegment> _segments = [];

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
    notifyListeners();

    try {
      final probe = await speech.probe(locale: locale);
      if (!probe.available || !probe.localeSupported) {
        throw StateError(
          probe.reason.isEmpty
              ? 'SpeechAnalyzer is unavailable for $locale'
              : probe.reason,
        );
      }
      final sessionId = const Uuid().v4();
      final directory = await _repository.createSessionDirectory(sessionId);
      _activeSessionId = sessionId;
      _startedAt = DateTime.now().toUtc();
      await _subscription?.cancel();
      _subscription = speech.events.listen(
        _handleEvent,
        onError: (Object error) => _fail(error.toString()),
      );
      await speech.start(sessionDirectory: directory.path, locale: locale);
      _state = TranscriptionUiState.recording;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final startedAt = _startedAt;
        if (startedAt != null && _state == TranscriptionUiState.recording) {
          _elapsed = DateTime.now().toUtc().difference(startedAt);
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
    await speech.pause();
    _state = TranscriptionUiState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != TranscriptionUiState.paused) return;
    await speech.resume();
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
    notifyListeners();
    try {
      final result = await speech.stop();
      await _subscription?.cancel();
      _subscription = null;
      final sessionId = _activeSessionId;
      final createdAt = _startedAt;
      if (sessionId == null || createdAt == null) {
        throw StateError('The transcription session identity was lost');
      }
      final raw = result.transcript.trim().isEmpty
          ? finalizedText
          : result.transcript.trim();
      _current = await _repository.finalize(
        sessionId: sessionId,
        createdAt: createdAt,
        duration: _elapsed,
        locale: _locale,
        rawTranscript: raw,
        segments: _segments,
        audioPath: result.audioPath,
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
    await speech.cancel();
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
    _error = message;
    _state = TranscriptionUiState.failed;
    notifyListeners();
  }

  void _reset() {
    _ticker?.cancel();
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
    super.dispose();
  }
}
