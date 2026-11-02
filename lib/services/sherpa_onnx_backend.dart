import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_package_manager.dart';
import 'transcription_contract.dart';

/// Version label recorded on sessions transcribed by this backend.
const sherpaOnnxVersion = 'sherpa-onnx 1.13.8';

/// Plain-data description of one file transcription, sendable to an isolate.
class SherpaTranscriptionRequest {
  const SherpaTranscriptionRequest({
    required this.family,
    required this.packagePath,
    required this.audioPath,
    required this.numThreads,
  });

  final SpeechPackageFamily family;
  final String packagePath;
  final String audioPath;
  final int numThreads;
}

abstract interface class SherpaRuntime {
  Future<List<TranscriptSegment>> transcribe(
    SherpaTranscriptionRequest request,
  );
  Future<void> abort();
}

/// Runs sherpa-onnx in a short-lived isolate so long recordings never block
/// the UI and cancellation can stop native decoding immediately.
class SherpaOnnxIsolateRuntime implements SherpaRuntime {
  Isolate? _isolate;
  Completer<List<TranscriptSegment>>? _pending;

  @override
  Future<List<TranscriptSegment>> transcribe(
    SherpaTranscriptionRequest request,
  ) async {
    // One port keeps ordering: the worker's reply always precedes the exit
    // notice (`null`); uncaught errors arrive as `[error, stack]`.
    final port = ReceivePort();
    final completer = Completer<List<TranscriptSegment>>();
    _pending = completer;
    port.listen((message) {
      if (completer.isCompleted) return;
      switch (message) {
        case {'segments': final List<Object?> items}:
          completer.complete([
            for (final (index, item) in items.cast<List<Object?>>().indexed)
              TranscriptSegment(
                id: 'sherpa-$index',
                text: item[0]! as String,
                start: Duration(microseconds: item[1]! as int),
                end: Duration(microseconds: item[2]! as int),
                isFinal: true,
              ),
          ]);
        case {'error': final String error}:
          completer.completeError(StateError(error));
        case [final Object? error, ...]:
          completer.completeError(
            StateError('Local transcription failed: $error'),
          );
        default:
          completer.completeError(
            StateError('Local transcription stopped unexpectedly'),
          );
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _sherpaWorker,
        [
          port.sendPort,
          request.family.name,
          request.packagePath,
          request.audioPath,
          request.numThreads,
        ],
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'sherpa-onnx',
      );
      return await completer.future;
    } finally {
      port.close();
      _isolate = null;
      _pending = null;
    }
  }

  @override
  Future<void> abort() async {
    _isolate?.kill(priority: Isolate.immediate);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Transcription cancelled'));
    }
  }
}

/// Isolate entry point. Replies with `{'segments': [[text, startUs, endUs]]}`
/// or `{'error': message}`; the isolate then exits, freeing native state.
void _sherpaWorker(List<Object?> args) {
  final reply = args[0]! as SendPort;
  try {
    reply.send({
      'segments': transcribeWithSherpa(
        family: SpeechPackageFamily.values.byName(args[1]! as String),
        packagePath: args[2]! as String,
        audioPath: args[3]! as String,
        numThreads: args[4]! as int,
      ),
    });
  } on Object catch (error) {
    reply.send({'error': 'Local transcription failed: $error'});
  }
}

/// Splits [audioPath] into utterances with Silero VAD and decodes each one.
///
/// Must run on an isolate that may block; native bindings are initialized
/// per isolate.
List<List<Object>> transcribeWithSherpa({
  required SpeechPackageFamily family,
  required String packagePath,
  required String audioPath,
  required int numThreads,
}) {
  sherpa.initBindings();
  String file(String name) => p.join(packagePath, name);
  final model = switch (family) {
    SpeechPackageFamily.parakeet => sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(
        encoder: file('encoder.int8.onnx'),
        decoder: file('decoder.int8.onnx'),
        joiner: file('joiner.int8.onnx'),
      ),
      tokens: file('tokens.txt'),
      numThreads: numThreads,
      debug: false,
    ),
    SpeechPackageFamily.moonshine => sherpa.OfflineModelConfig(
      moonshine: sherpa.OfflineMoonshineModelConfig(
        preprocessor: file('preprocess.onnx'),
        encoder: file('encode.int8.onnx'),
        uncachedDecoder: file('uncached_decode.int8.onnx'),
        cachedDecoder: file('cached_decode.int8.onnx'),
      ),
      tokens: file('tokens.txt'),
      numThreads: numThreads,
      debug: false,
    ),
  };
  final wave = sherpa.readWave(audioPath);
  if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
    throw StateError('The recording has no audio');
  }
  // Silero VAD and both models work on 16 kHz mono.
  const sampleRate = 16000;
  final samples = resampleTo16k(wave.samples, wave.sampleRate);
  final vadConfig = sherpa.VadModelConfig(
    sileroVad: sherpa.SileroVadModelConfig(
      model: file('silero_vad.onnx'),
      minSilenceDuration: 0.4,
      minSpeechDuration: 0.25,
      // Moonshine is trained on short utterances; Parakeet handles longer.
      maxSpeechDuration: family == SpeechPackageFamily.moonshine ? 15 : 30,
    ),
    numThreads: 1,
    debug: false,
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(model: model),
  );
  final vad = sherpa.VoiceActivityDetector(
    config: vadConfig,
    bufferSizeInSeconds: 60,
  );
  final segments = <List<Object>>[];
  void drain() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: segment.samples, sampleRate: sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        if (text.isNotEmpty) {
          final startUs = segment.start * 1000000 ~/ sampleRate;
          final lengthUs = segment.samples.length * 1000000 ~/ sampleRate;
          segments.add([text, startUs, startUs + lengthUs]);
        }
      } finally {
        stream.free();
      }
      vad.pop();
    }
  }

  try {
    final window = vadConfig.sileroVad.windowSize;
    for (var start = 0; start + window <= samples.length; start += window) {
      vad.acceptWaveform(
        Float32List.sublistView(samples, start, start + window),
      );
      drain();
    }
    vad.flush();
    drain();
    return segments;
  } finally {
    vad.free();
    recognizer.free();
  }
}

/// Converts mono PCM at [rate] Hz to 16 kHz.
///
/// Downsampling averages each output interval (a box filter, enough to keep
/// speech intelligible for recognition); upsampling interpolates linearly.
@visibleForTesting
Float32List resampleTo16k(Float32List input, int rate) {
  const target = 16000;
  if (rate == target || input.isEmpty) return input;
  final ratio = rate / target;
  final length = (input.length / ratio).floor();
  final output = Float32List(length);
  for (var i = 0; i < length; i++) {
    final from = i * ratio;
    if (ratio > 1) {
      final start = from.floor();
      final end = math.min(input.length, ((i + 1) * ratio).ceil());
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += input[j];
      }
      output[i] = sum / (end - start);
    } else {
      final index = from.floor();
      final next = math.min(index + 1, input.length - 1);
      final t = from - index;
      output[i] = input[index] * (1 - t) + input[next] * t;
    }
  }
  return output;
}

/// Offline Parakeet/Moonshine transcription of a recorded WAV file.
class SherpaOnnxBackend implements TranscriptionBackend {
  SherpaOnnxBackend({
    required this.spec,
    required this.packagePath,
    SherpaRuntime? runtime,
    int? numThreads,
  }) : _runtime = runtime ?? SherpaOnnxIsolateRuntime(),
       _numThreads =
           numThreads ?? (Platform.numberOfProcessors - 1).clamp(1, 6);

  final SpeechPackageSpec spec;
  final String packagePath;
  final SherpaRuntime _runtime;
  final int _numThreads;
  TranscriptionConfig? _config;
  FinalTranscript? _result;
  bool _active = false;

  @override
  TranscriptionBackendKind get kind => switch (spec.family) {
    SpeechPackageFamily.parakeet => TranscriptionBackendKind.parakeet,
    SpeechPackageFamily.moonshine => TranscriptionBackendKind.moonshine,
  };

  /// Session label such as `sherpa-onnx 1.13.8 · Parakeet TDT 0.6B v3`.
  String get versionLabel => '$sherpaOnnxVersion · ${spec.displayName}';

  @override
  Future<TranscriptionCapabilities> probe() async {
    final ready = await Directory(packagePath).exists();
    return TranscriptionCapabilities(
      backend: kind,
      operational: ready,
      supportsFiles: true,
      supportsTimecodes: true,
      supportedLocales: spec.englishOnly ? const ['en'] : spec.languages,
      reason: ready
          ? '${spec.displayName} is ready on device'
          : '${spec.displayName} is not installed',
    );
  }

  @override
  Future<void> prepare(TranscriptionConfig config) async {
    final capabilities = await probe();
    if (!capabilities.operational) throw StateError(capabilities.reason);
    if (!spec.supportsLocale(config.locale)) {
      throw StateError(
        '${spec.displayName} does not recognize ${config.locale}',
      );
    }
    _config = config;
    _result = null;
  }

  @override
  Stream<TranscriptionEvent> transcribe(AudioInput input) async* {
    if (input.kind != AudioInputKind.file || input.filePath.isEmpty) {
      yield TranscriptionFailure(
        code: 'file_required',
        message: '${spec.displayName} transcribes a saved WAV file',
        recoverable: true,
      );
      return;
    }
    if (_config == null) {
      yield TranscriptionFailure(
        code: 'not_prepared',
        message: 'Prepare ${spec.displayName} before transcription',
        recoverable: true,
      );
      return;
    }
    _active = true;
    try {
      final segments = await _runtime.transcribe(
        SherpaTranscriptionRequest(
          family: spec.family,
          packagePath: packagePath,
          audioPath: input.filePath,
          numThreads: _numThreads,
        ),
      );
      _result = FinalTranscript(
        text: segments.map((segment) => segment.text).join(' ').trim(),
        segments: segments,
        audioPath: input.filePath,
      );
      for (final segment in segments) {
        yield TranscriptionSegmentUpdated(segment);
      }
    } on Object catch (error) {
      yield TranscriptionFailure(
        code: 'sherpa_transcription_failed',
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
      throw StateError('${spec.displayName} transcription has not completed');
    }
    return result;
  }

  @override
  Future<void> cancel() async {
    if (_active) await _runtime.abort();
    _active = false;
  }
}
