import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:erebrus_ai/services/speech_package_manager.dart';
import 'package:erebrus_ai/services/transcription_contract.dart';
import 'package:erebrus_ai/services/transcription_engine.dart';
import 'package:erebrus_ai/services/voice_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;
const _rig = DeviceProfile(
  type: DeviceType.desktop,
  ramBytes: 32 * _gb,
  name: 'Gaming rig',
  platform: 'windows-x86_64',
);
const _flagship = DeviceProfile(
  type: DeviceType.mobile,
  ramBytes: 12 * _gb,
  name: '12 GB phone',
  platform: 'android-arm64',
);
const _budgetPhone = DeviceProfile(
  type: DeviceType.mobile,
  ramBytes: 4 * _gb,
  name: '4 GB phone',
  platform: 'android-arm64',
);

TranscriptionEngineDecision _choose({
  DictationEngine preference = DictationEngine.auto,
  String locale = 'en-US',
  bool localeChosen = true,
  DeviceProfile device = _rig,
  bool system = false,
  bool whisper = false,
  bool whisperEnglishOnly = false,
  bool parakeet = false,
  bool moonshine = false,
}) => chooseTranscriptionEngine(
  TranscriptionEngineInputs(
    preference: preference,
    locale: locale,
    localeChosen: localeChosen,
    device: device,
    systemSpeechReady: system,
    whisperInstalled: whisper,
    whisperEnglishOnly: whisperEnglishOnly,
    parakeet: parakeet ? SpeechPackageManager.parakeetV3 : null,
    moonshine: moonshine ? SpeechPackageManager.moonshineTiny : null,
  ),
);

void main() {
  group('Automatic', () {
    test('keeps system on-device speech as the default', () {
      final decision = _choose(system: true, whisper: true, parakeet: true);

      expect(decision.backend, TranscriptionBackendKind.speechAnalyzer);
      expect(decision.notice, isEmpty);
    });

    test('prefers Parakeet over Whisper on a computer', () {
      expect(
        _choose(whisper: true, parakeet: true).backend,
        TranscriptionBackendKind.parakeet,
      );
    });

    test('uses Parakeet on a 12 GB phone but not a 4 GB one', () {
      expect(
        _choose(device: _flagship, whisper: true, parakeet: true).backend,
        TranscriptionBackendKind.parakeet,
      );
      expect(
        _choose(device: _budgetPhone, whisper: true, parakeet: true).backend,
        TranscriptionBackendKind.whisperCpp,
      );
    });

    test('skips Parakeet for languages it does not recognize', () {
      expect(
        _choose(locale: 'hi-IN', whisper: true, parakeet: true).backend,
        TranscriptionBackendKind.whisperCpp,
      );
      expect(
        _choose(locale: 'de-DE', whisper: true, parakeet: true).backend,
        TranscriptionBackendKind.parakeet,
      );
    });

    test('uses Moonshine for English and Whisper otherwise', () {
      expect(
        _choose(device: _budgetPhone, whisper: true, moonshine: true).backend,
        TranscriptionBackendKind.moonshine,
      );
      expect(
        _choose(
          device: _budgetPhone,
          locale: 'fr-FR',
          whisper: true,
          moonshine: true,
        ).backend,
        TranscriptionBackendKind.whisperCpp,
      );
    });

    test('computers prefer Whisper over Moonshine when both exist', () {
      expect(
        _choose(whisper: true, moonshine: true).backend,
        TranscriptionBackendKind.whisperCpp,
      );
      expect(
        _choose(moonshine: true).backend,
        TranscriptionBackendKind.moonshine,
      );
    });

    test('still uses a downloaded Parakeet when it is the only model', () {
      expect(
        _choose(device: _budgetPhone, parakeet: true).backend,
        TranscriptionBackendKind.parakeet,
      );
    });

    test('asks for a download when nothing can run', () {
      final decision = _choose();

      expect(decision.available, isFalse);
      expect(decision.notice, contains('Settings → Voice'));
    });
  });

  group('explicit choice', () {
    test('wins over system speech when it can run', () {
      expect(
        _choose(
          preference: DictationEngine.parakeet,
          system: true,
          parakeet: true,
        ).backend,
        TranscriptionBackendKind.parakeet,
      );
      expect(
        _choose(
          preference: DictationEngine.moonshine,
          system: true,
          moonshine: true,
        ).backend,
        TranscriptionBackendKind.moonshine,
      );
    });

    test('falls back to Automatic and says why', () {
      final missing = _choose(
        preference: DictationEngine.parakeet,
        system: true,
      );
      final language = _choose(
        preference: DictationEngine.moonshine,
        locale: 'es-ES',
        moonshine: true,
        whisper: true,
      );

      expect(missing.backend, TranscriptionBackendKind.speechAnalyzer);
      expect(missing.notice, startsWith('Parakeet isn’t downloaded'));
      expect(language.backend, TranscriptionBackendKind.whisperCpp);
      expect(language.notice, contains('only recognizes English'));
    });

    test('is honoured when the language is left on Auto', () {
      final decision = _choose(
        preference: DictationEngine.parakeet,
        locale: 'hi-IN',
        localeChosen: false,
        parakeet: true,
        whisper: true,
      );

      expect(decision.backend, TranscriptionBackendKind.parakeet);
      expect(decision.notice, isEmpty);
    });

    test('System speech falls back instead of failing', () {
      final decision = _choose(
        preference: DictationEngine.system,
        whisper: true,
      );

      expect(decision.backend, TranscriptionBackendKind.whisperCpp);
      expect(decision.notice, contains('System speech is unavailable'));
    });
  });

  test('Parakeet languages cover its 25 European languages', () {
    final spec = SpeechPackageManager.parakeetV3;

    expect(spec.languages, hasLength(25));
    expect(spec.supportsLocale('auto'), isTrue);
    expect(spec.supportsLocale('pt_BR'), isTrue);
    expect(spec.supportsLocale('ja-JP'), isFalse);
    expect(SpeechPackageManager.moonshineBase.supportsLocale('en-GB'), isTrue);
    expect(SpeechPackageManager.moonshineBase.supportsLocale('de'), isFalse);
  });
}
