import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'speech_package_manager.dart';
import 'whisper_model_manager.dart';

/// Which speech-to-text engine dictation and transcription use.
enum DictationEngine {
  /// Prefer the operating system's on-device recognizer, then a downloaded
  /// local model that suits this device and language.
  auto(
    'Automatic',
    'System speech when available, otherwise the best downloaded local model',
  ),

  /// Only the operating system's on-device recognizer (Apple SpeechAnalyzer).
  system('System speech', 'Built-in on-device recognizer'),

  /// Always run the downloaded Whisper model locally and offline.
  whisper(
    'Local transcription',
    'Runs a Whisper speech-to-text model locally and works offline',
  ),

  /// NVIDIA Parakeet TDT: fast, accurate, 25 European languages.
  parakeet('Parakeet', 'Fast, accurate local model for 25 European languages'),

  /// Moonshine: lightweight English model for phones.
  moonshine('Moonshine', 'Lightweight local English model for phones');

  const DictationEngine(this.label, this.description);

  final String label;
  final String description;
}

/// Device-wide voice preferences shown in Settings → Voice.
class VoicePreferences extends ChangeNotifier {
  VoicePreferences._();

  static final VoicePreferences instance = VoicePreferences._();

  static const _engineKey = 'voice_dictation_engine';
  static const _localeKey = 'voice_dictation_locale';
  static const _readAloudKey = 'voice_read_aloud_enabled';

  DictationEngine _engine = DictationEngine.auto;
  String _locale = 'auto';
  bool _readAloudEnabled = true;
  bool _loaded = false;

  DictationEngine get engine => _engine;
  String get locale => _locale;
  bool get readAloudEnabled => _readAloudEnabled;
  bool get isLoaded => _loaded;

  WhisperModelSpec get whisperModel => WhisperModelManager.selectedSpec;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _engine =
          DictationEngine.values
              .where((value) => value.name == preferences.getString(_engineKey))
              .firstOrNull ??
          DictationEngine.auto;
      _locale = preferences.getString(_localeKey) ?? 'auto';
      _readAloudEnabled = preferences.getBool(_readAloudKey) ?? true;
      await WhisperModelManager.loadSelection();
      await SpeechPackageManager.loadSelection();
    } on Object catch (error) {
      debugPrint('[Voice] preference load failed: $error');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setEngine(DictationEngine value) async {
    _engine = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _engineKey,
      value.name,
    );
  }

  Future<void> setLocale(String value) async {
    _locale = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_localeKey, value);
  }

  Future<void> setWhisperModel(String specId) async {
    await WhisperModelManager.select(specId);
    notifyListeners();
  }

  Future<void> setMoonshineModel(String specId) async {
    await SpeechPackageManager.selectMoonshine(specId);
    notifyListeners();
  }

  Future<void> setReadAloudEnabled(bool value) async {
    _readAloudEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_readAloudKey, value);
  }
}
