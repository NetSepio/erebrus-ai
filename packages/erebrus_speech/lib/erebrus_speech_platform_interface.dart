import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'erebrus_speech.dart';
import 'erebrus_speech_method_channel.dart';

abstract class ErebrusSpeechPlatform extends PlatformInterface {
  ErebrusSpeechPlatform() : super(token: _token);

  static final Object _token = Object();
  static ErebrusSpeechPlatform _instance = MethodChannelErebrusSpeech();

  static ErebrusSpeechPlatform get instance => _instance;

  static set instance(ErebrusSpeechPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<SpeechAnalyzerProbe> probe({required String locale});

  Future<String> start({
    required String sessionDirectory,
    required String locale,
  });

  Stream<SpeechTranscriptionEvent> get events;

  Future<void> pause();

  Future<void> resume();

  Future<SpeechSessionResult> stop();

  Future<void> cancel();
}
