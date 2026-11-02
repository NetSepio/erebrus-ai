import 'device_info_service.dart';
import 'speech_package_manager.dart';
import 'transcription_contract.dart';
import 'voice_preferences.dart';

/// What is installed or available right now, gathered by the caller so
/// engine choice stays a pure, testable decision.
class TranscriptionEngineInputs {
  const TranscriptionEngineInputs({
    required this.preference,
    required this.locale,
    required this.device,
    this.localeChosen = false,
    this.systemSpeechReady = false,
    this.whisperInstalled = false,
    this.whisperEnglishOnly = false,
    this.parakeet,
    this.moonshine,
  });

  final DictationEngine preference;

  /// Resolved BCP-47 locale: the user's language, or the device's when the
  /// user left dictation language on Auto.
  final String locale;

  /// Whether the user picked [locale]. When false, an explicit engine choice
  /// is honoured even if the device language is outside its range.
  final bool localeChosen;
  final DeviceProfile device;
  final bool systemSpeechReady;
  final bool whisperInstalled;
  final bool whisperEnglishOnly;

  /// Installed Parakeet package, or null.
  final SpeechPackageSpec? parakeet;

  /// Installed Moonshine package (the selected size), or null.
  final SpeechPackageSpec? moonshine;
}

class TranscriptionEngineDecision {
  const TranscriptionEngineDecision(this.backend, {this.notice = ''});

  /// No engine can run; [notice] tells the user what to download.
  const TranscriptionEngineDecision.unavailable(this.notice) : backend = null;

  final TranscriptionBackendKind? backend;

  /// Why the user's explicit choice was not used, or what is missing.
  final String notice;

  bool get available => backend != null;
}

/// Automatic only upgrades to Parakeet on hardware that runs it comfortably:
/// laptops, desktops and gaming rigs, and 12 GB-class phones.
bool parakeetSuitsDevice(DeviceProfile device) =>
    device.type == DeviceType.desktop
    ? device.ramGB >= 8
    : device.ramClassGB >= 12;

/// Picks the engine for one recording.
///
/// Automatic keeps the existing default — system on-device speech first —
/// then the best downloaded local model for this device and language:
/// Parakeet, then Moonshine (English, phones) or Whisper. An explicit choice
/// always wins
/// when it can run; otherwise Automatic is used and [notice] says why.
TranscriptionEngineDecision chooseTranscriptionEngine(
  TranscriptionEngineInputs inputs,
) {
  final language = _language(inputs.locale);
  final english = language == 'auto' || language == 'en';
  // Explicit engine choices only check a language the user actually chose.
  final explicitEnglish = english || !inputs.localeChosen;
  final parakeet = inputs.parakeet;
  final moonshine = inputs.moonshine;
  final parakeetFits =
      parakeet != null && inputs.device.ramGB >= parakeet.minimumRamGB;
  final parakeetRuns = parakeetFits && parakeet.supportsLocale(inputs.locale);
  final moonshineRuns = moonshine != null && english;
  final whisperRuns =
      inputs.whisperInstalled && (!inputs.whisperEnglishOnly || english);

  String? unusable;
  switch (inputs.preference) {
    case DictationEngine.system:
      if (inputs.systemSpeechReady) {
        return const TranscriptionEngineDecision(
          TranscriptionBackendKind.speechAnalyzer,
        );
      }
      unusable = 'System speech is unavailable for this language here';
    case DictationEngine.whisper:
      if (inputs.whisperInstalled &&
          (!inputs.whisperEnglishOnly || explicitEnglish)) {
        return const TranscriptionEngineDecision(
          TranscriptionBackendKind.whisperCpp,
        );
      }
      unusable = inputs.whisperInstalled
          ? 'The selected Whisper model only recognizes English'
          : 'The Whisper model isn’t downloaded';
    case DictationEngine.parakeet:
      if (parakeetFits &&
          (parakeet.supportsLocale(inputs.locale) || !inputs.localeChosen)) {
        return const TranscriptionEngineDecision(
          TranscriptionBackendKind.parakeet,
        );
      }
      unusable = parakeet == null
          ? 'Parakeet isn’t downloaded'
          : !parakeet.supportsLocale(inputs.locale)
          ? 'Parakeet doesn’t recognize this language'
          : 'This device doesn’t have enough memory for Parakeet';
    case DictationEngine.moonshine:
      if (moonshine != null && explicitEnglish) {
        return const TranscriptionEngineDecision(
          TranscriptionBackendKind.moonshine,
        );
      }
      unusable = moonshine == null
          ? 'Moonshine isn’t downloaded'
          : 'Moonshine only recognizes English';
    case DictationEngine.auto:
      break;
  }

  // Moonshine is the phone-sized choice; computers prefer a Whisper model.
  final phone = inputs.device.type == DeviceType.mobile;
  final fallback = inputs.systemSpeechReady
      ? TranscriptionBackendKind.speechAnalyzer
      : parakeetRuns && parakeetSuitsDevice(inputs.device)
      ? TranscriptionBackendKind.parakeet
      : moonshineRuns && (phone || !whisperRuns)
      ? TranscriptionBackendKind.moonshine
      : whisperRuns
      ? TranscriptionBackendKind.whisperCpp
      // A model the user downloaded still beats having nothing at all.
      : parakeetRuns
      ? TranscriptionBackendKind.parakeet
      : null;
  if (fallback == null) {
    return TranscriptionEngineDecision.unavailable(
      [
        ?unusable,
        'Download a speech model in Settings → Voice before recording on '
            'this device',
      ].join('. '),
    );
  }
  return TranscriptionEngineDecision(
    fallback,
    notice: unusable == null
        ? ''
        : '$unusable, so ${fallback.displayName} is used instead.',
  );
}

String _language(String locale) {
  final language = locale.trim().toLowerCase().split(RegExp('[-_]')).first;
  return language.isEmpty ? 'auto' : language;
}
