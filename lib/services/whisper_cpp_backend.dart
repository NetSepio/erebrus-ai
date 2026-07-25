import 'dart:async';
import 'dart:io';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart' as whisper;

import 'transcription_contract.dart';

class WhisperRuntimeResult {
  const WhisperRuntimeResult({required this.text, required this.segments});

  final String text;
  final List<TranscriptSegment> segments;
}

abstract interface class WhisperRuntime {
  Future<WhisperRuntimeResult> transcribe({
    required String modelPath,
    required String audioPath,
    required String language,
  });
  Future<void> abort();
  Future<void> dispose();
}

class WhisperGgmlRuntime implements WhisperRuntime {
  final whisper.Whisper _whisper = whisper.Whisper(
    model: whisper.WhisperModel.tiny,
  );

  @override
  Future<WhisperRuntimeResult> transcribe({
    required String modelPath,
    required String audioPath,
    required String language,
  }) async {
    final response = await _whisper.transcribe(
      transcribeRequest: whisper.TranscribeRequest(
        audio: audioPath,
        language: language,
        threads: (Platform.numberOfProcessors - 1).clamp(1, 8),
        isNoTimestamps: false,
        vadMode: whisper.WhisperVadMode.auto,
      ),
      modelPath: modelPath,
    );
    final segments = (response.segments ?? const [])
        .asMap()
        .entries
        .map(
          (entry) => TranscriptSegment(
            id: 'whisper-${entry.key}',
            text: entry.value.text,
            start: entry.value.fromTs,
            end: entry.value.toTs,
            isFinal: true,
          ),
        )
        .toList(growable: false);
    return WhisperRuntimeResult(text: response.text, segments: segments);
  }

  @override
  Future<void> abort() => _whisper.abort();

  @override
  Future<void> dispose() => _whisper.dispose();
}

class WhisperCppBackend implements TranscriptionBackend {
  WhisperCppBackend({required this.modelPath, WhisperRuntime? runtime})
    : _runtime = runtime ?? WhisperGgmlRuntime();

  final String modelPath;
  final WhisperRuntime _runtime;
  TranscriptionConfig? _config;
  FinalTranscript? _result;
  bool _active = false;

  @override
  TranscriptionBackendKind get kind => TranscriptionBackendKind.whisperCpp;

  @override
  Future<TranscriptionCapabilities> probe() async {
    if (!await File(modelPath).exists()) {
      return const TranscriptionCapabilities(
        backend: TranscriptionBackendKind.whisperCpp,
        operational: false,
        supportsFiles: true,
        supportsTimecodes: true,
        reason: 'The verified Whisper model is not installed',
      );
    }
    return const TranscriptionCapabilities(
      backend: TranscriptionBackendKind.whisperCpp,
      operational: true,
      supportsFiles: true,
      supportsTimecodes: true,
      supportedLocales: ['auto'],
      reason: 'whisper.cpp file transcription is ready on device',
    );
  }

  @override
  Future<void> prepare(TranscriptionConfig config) async {
    final capabilities = await probe();
    if (!capabilities.operational) throw StateError(capabilities.reason);
    _config = config;
    _result = null;
  }

  @override
  Stream<TranscriptionEvent> transcribe(AudioInput input) async* {
    if (input.kind != AudioInputKind.file || input.filePath.isEmpty) {
      yield const TranscriptionFailure(
        code: 'file_required',
        message: 'This whisper.cpp backend transcribes a saved WAV file',
        recoverable: true,
      );
      return;
    }
    final config = _config;
    if (config == null) {
      yield const TranscriptionFailure(
        code: 'not_prepared',
        message: 'Prepare the whisper.cpp backend before transcription',
        recoverable: true,
      );
      return;
    }
    _active = true;
    try {
      final result = await _runtime.transcribe(
        modelPath: modelPath,
        audioPath: input.filePath,
        language: _whisperLanguage(config.locale),
      );
      _result = FinalTranscript(
        text: result.text.trim(),
        segments: result.segments,
        audioPath: input.filePath,
      );
      for (final segment in result.segments) {
        yield TranscriptionSegmentUpdated(segment);
      }
    } on Object catch (error) {
      yield TranscriptionFailure(
        code: 'whisper_transcription_failed',
        message: error.toString(),
        recoverable: true,
      );
    } finally {
      _active = false;
    }
  }

  @override
  Future<FinalTranscript> finish() async {
    final result = _result;
    if (result == null) {
      throw StateError('Whisper transcription has not completed');
    }
    await _runtime.dispose();
    return result;
  }

  @override
  Future<void> cancel() async {
    if (_active) await _runtime.abort();
    await _runtime.dispose();
    _active = false;
  }

  static String _whisperLanguage(String locale) {
    final normalized = locale.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'auto') return 'auto';
    return normalized.split(RegExp('[-_]')).first;
  }
}
