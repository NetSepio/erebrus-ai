import 'package:erebrus_speech/erebrus_speech.dart';
import 'package:erebrus_speech/erebrus_speech_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('erebrus_speech/methods');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'probe' => <String, Object?>{
              'available': true,
              'platform': 'macos-arm64',
              'minimum_os': 'macOS 26',
              'locale': 'en-US',
              'locale_supported': true,
              'asset_status': 'installed',
              'reason': 'available',
            },
            'start' => '/tmp/session/audio.caf',
            'stop' => <String, Object?>{
              'audio_path': '/tmp/session/audio.caf',
              'transcript': 'hello on device',
            },
            'pause' => null,
            'resume' => null,
            'cancel' => null,
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('probe decodes capability and locale metadata', () async {
    final plugin = MethodChannelErebrusSpeech();

    final probe = await plugin.probe(locale: 'en-US');

    expect(probe.available, isTrue);
    expect(probe.localeSupported, isTrue);
    expect(probe.assetStatus, 'installed');
    expect(calls.single.arguments, <String, Object?>{'locale': 'en-US'});
  });

  test('start and stop preserve the recorded audio path', () async {
    final plugin = MethodChannelErebrusSpeech();

    final audioPath = await plugin.start(
      sessionDirectory: '/tmp/session',
      locale: 'en-US',
    );
    final result = await plugin.stop();

    expect(audioPath, '/tmp/session/audio.caf');
    expect(result.audioPath, audioPath);
    expect(result.transcript, 'hello on device');
    expect(calls.first.arguments, <String, Object?>{
      'session_directory': '/tmp/session',
      'locale': 'en-US',
    });
  });

  test('cancel is forwarded to the native bridge', () async {
    final plugin = MethodChannelErebrusSpeech();

    await plugin.cancel();

    expect(calls.single.method, 'cancel');
  });

  test('pause and resume are forwarded to the native bridge', () async {
    final plugin = MethodChannelErebrusSpeech();

    await plugin.pause();
    await plugin.resume();

    expect(calls.map((call) => call.method), ['pause', 'resume']);
  });

  test('event DTO preserves partial timing and diagnostics', () {
    final event = SpeechTranscriptionEvent.fromMap(<Object?, Object?>{
      'type': 'partial',
      'text': 'hello',
      'start_seconds': 1,
      'end_seconds': 2.25,
      'message': 'local',
    });

    expect(event.type, 'partial');
    expect(event.text, 'hello');
    expect(event.startSeconds, 1);
    expect(event.endSeconds, 2.25);
    expect(event.message, 'local');
  });
}
