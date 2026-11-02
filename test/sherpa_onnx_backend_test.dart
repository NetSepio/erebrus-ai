import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erebrus_ai/services/sherpa_onnx_backend.dart';
import 'package:erebrus_ai/services/speech_package_manager.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeRuntime implements SherpaRuntime {
  _FakeRuntime({this.segments = const [], this.error});

  final List<TranscriptSegment> segments;
  final Object? error;
  SherpaTranscriptionRequest? request;
  Completer<void>? gate;
  bool aborted = false;

  @override
  Future<List<TranscriptSegment>> transcribe(
    SherpaTranscriptionRequest request,
  ) async {
    this.request = request;
    await gate?.future;
    if (error != null) throw error!;
    return segments;
  }

  @override
  Future<void> abort() async {
    aborted = true;
    gate?.complete();
  }
}

TranscriptSegment _segment(String text, int startMs, int endMs) =>
    TranscriptSegment(
      id: text,
      text: text,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      isFinal: true,
    );

void main() {
  late Directory package;

  setUp(() async {
    package = await Directory.systemTemp.createTemp('erebrus-sherpa-');
  });

  tearDown(() async {
    if (await package.exists()) await package.delete(recursive: true);
  });

  test('transcribes a WAV into timed segments', () async {
    final runtime = _FakeRuntime(
      segments: [
        _segment('Hello there.', 0, 900),
        _segment('Bye.', 1200, 1600),
      ],
    );
    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.parakeetV3,
      packagePath: package.path,
      runtime: runtime,
      numThreads: 2,
    );

    await backend.prepare(const TranscriptionConfig(locale: 'de-DE'));
    final events = await backend
        .transcribe(AudioInput.file(p.join(package.path, 'audio.wav')))
        .toList();
    final result = await backend.finish();

    expect(backend.kind, TranscriptionBackendKind.parakeet);
    expect(runtime.request?.family, SpeechPackageFamily.parakeet);
    expect(runtime.request?.numThreads, 2);
    expect(events, everyElement(isA<TranscriptionSegmentUpdated>()));
    expect(result.text, 'Hello there. Bye.');
    expect(result.segments.last.start, const Duration(milliseconds: 1200));
    expect(backend.versionLabel, 'sherpa-onnx 1.13.8 · Parakeet TDT 0.6B v3');
  });

  test('refuses a language the model does not recognize', () async {
    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.moonshineTiny,
      packagePath: package.path,
      runtime: _FakeRuntime(),
    );

    await expectLater(
      backend.prepare(const TranscriptionConfig(locale: 'fr-FR')),
      throwsStateError,
    );
    await backend.prepare(const TranscriptionConfig(locale: 'auto'));
  });

  test('reports runtime failures as recoverable events', () async {
    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.moonshineTiny,
      packagePath: package.path,
      runtime: _FakeRuntime(error: StateError('decoder failed')),
    );
    await backend.prepare(const TranscriptionConfig(locale: 'en-US'));

    final events = await backend
        .transcribe(const AudioInput.file('/audio.wav'))
        .toList();

    expect(events.single, isA<TranscriptionFailure>());
    expect(
      (events.single as TranscriptionFailure).message,
      contains('decoder failed'),
    );
    await expectLater(backend.finish(), throwsStateError);
  });

  test('cancel aborts in-flight decoding', () async {
    final runtime = _FakeRuntime(error: StateError('cancelled'))
      ..gate = Completer<void>();
    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.moonshineTiny,
      packagePath: package.path,
      runtime: runtime,
    );
    await backend.prepare(const TranscriptionConfig(locale: 'en'));

    final events = backend
        .transcribe(const AudioInput.file('/audio.wav'))
        .toList();
    await Future<void>.delayed(Duration.zero);
    await backend.cancel();

    expect(runtime.aborted, isTrue);
    expect((await events).single, isA<TranscriptionFailure>());
  });

  test('is not operational before the package is installed', () async {
    final backend = SherpaOnnxBackend(
      spec: SpeechPackageManager.parakeetV3,
      packagePath: p.join(package.path, 'missing'),
      runtime: _FakeRuntime(),
    );

    expect((await backend.probe()).operational, isFalse);
    await expectLater(
      backend.prepare(const TranscriptionConfig(locale: 'auto')),
      throwsStateError,
    );
  });

  test('resamples other rates to 16 kHz', () {
    final ramp = Float32List.fromList([
      for (var i = 0; i < 48000; i++) i / 48000,
    ]);
    final down = resampleTo16k(ramp, 48000);
    final up = resampleTo16k(Float32List.fromList([0, 1]), 8000);

    expect(down, hasLength(16000));
    expect(down[8000], closeTo(0.5, 0.001));
    expect(up, hasLength(4));
    expect(up[1], closeTo(0.5, 0.001));
    expect(identical(resampleTo16k(ramp, 16000), ramp), isTrue);
  });
}
