import 'erebrus_speech_platform_interface.dart';

class SpeechAnalyzerProbe {
  const SpeechAnalyzerProbe({
    required this.available,
    required this.platform,
    required this.minimumOperatingSystem,
    required this.locale,
    required this.localeSupported,
    required this.assetStatus,
    this.reason = '',
  });

  factory SpeechAnalyzerProbe.fromMap(Map<Object?, Object?> map) =>
      SpeechAnalyzerProbe(
        available: map['available'] == true,
        platform: map['platform']?.toString() ?? '',
        minimumOperatingSystem: map['minimum_os']?.toString() ?? '',
        locale: map['locale']?.toString() ?? '',
        localeSupported: map['locale_supported'] == true,
        assetStatus: map['asset_status']?.toString() ?? 'unknown',
        reason: map['reason']?.toString() ?? '',
      );

  final bool available;
  final String platform;
  final String minimumOperatingSystem;
  final String locale;
  final bool localeSupported;
  final String assetStatus;
  final String reason;
}

class SpeechTranscriptionEvent {
  const SpeechTranscriptionEvent({
    required this.type,
    this.text = '',
    this.startSeconds,
    this.endSeconds,
    this.message = '',
  });

  factory SpeechTranscriptionEvent.fromMap(Map<Object?, Object?> map) =>
      SpeechTranscriptionEvent(
        type: map['type']?.toString() ?? 'unknown',
        text: map['text']?.toString() ?? '',
        startSeconds: (map['start_seconds'] as num?)?.toDouble(),
        endSeconds: (map['end_seconds'] as num?)?.toDouble(),
        message: map['message']?.toString() ?? '',
      );

  final String type;
  final String text;
  final double? startSeconds;
  final double? endSeconds;
  final String message;
}

class SpeechSessionResult {
  const SpeechSessionResult({
    required this.audioPath,
    required this.transcript,
  });

  factory SpeechSessionResult.fromMap(Map<Object?, Object?> map) =>
      SpeechSessionResult(
        audioPath: map['audio_path']?.toString() ?? '',
        transcript: map['transcript']?.toString() ?? '',
      );

  final String audioPath;
  final String transcript;
}

class ErebrusSpeech {
  const ErebrusSpeech();

  Future<SpeechAnalyzerProbe> probe({String locale = ''}) =>
      ErebrusSpeechPlatform.instance.probe(locale: locale);

  Future<String> start({
    required String sessionDirectory,
    String locale = '',
  }) => ErebrusSpeechPlatform.instance.start(
    sessionDirectory: sessionDirectory,
    locale: locale,
  );

  Stream<SpeechTranscriptionEvent> get events =>
      ErebrusSpeechPlatform.instance.events;

  Future<SpeechSessionResult> stop() => ErebrusSpeechPlatform.instance.stop();

  Future<void> cancel() => ErebrusSpeechPlatform.instance.cancel();
}
