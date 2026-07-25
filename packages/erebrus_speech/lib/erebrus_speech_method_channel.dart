import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'erebrus_speech.dart';
import 'erebrus_speech_platform_interface.dart';

class MethodChannelErebrusSpeech extends ErebrusSpeechPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('erebrus_speech/methods');

  @visibleForTesting
  final eventChannel = const EventChannel('erebrus_speech/events');

  Stream<SpeechTranscriptionEvent>? _events;

  @override
  Future<SpeechAnalyzerProbe> probe({required String locale}) async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'probe',
      {'locale': locale},
    );
    return SpeechAnalyzerProbe.fromMap(result ?? const {});
  }

  @override
  Future<String> start({
    required String sessionDirectory,
    required String locale,
  }) async {
    return await methodChannel.invokeMethod<String>('start', {
          'session_directory': sessionDirectory,
          'locale': locale,
        }) ??
        '';
  }

  @override
  Stream<SpeechTranscriptionEvent> get events =>
      _events ??= eventChannel.receiveBroadcastStream().map(
        (event) => SpeechTranscriptionEvent.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      );

  @override
  Future<void> pause() => methodChannel.invokeMethod<void>('pause');

  @override
  Future<void> resume() => methodChannel.invokeMethod<void>('resume');

  @override
  Future<SpeechSessionResult> stop() async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'stop',
    );
    return SpeechSessionResult.fromMap(result ?? const {});
  }

  @override
  Future<void> cancel() => methodChannel.invokeMethod<void>('cancel');
}
