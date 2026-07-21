import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speaks assistant responses through the platform speech engine.
///
/// Android and Apple users can install higher-quality system voices from their
/// device's text-to-speech/accessibility settings without increasing app size.
class SpeechService extends ChangeNotifier {
  SpeechService._() {
    _tts.setStartHandler(() {
      _speaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(_finish);
    _tts.setCancelHandler(_finish);
    _tts.setErrorHandler((_) => _finish());
    _initialize();
  }

  static final SpeechService instance = SpeechService._();

  final FlutterTts _tts = FlutterTts();
  String? _messageId;
  bool _speaking = false;
  bool _initialized = false;
  List<VoiceOption> _voices = const [];
  List<String> _engines = const [];
  String? _selectedEngine;
  String? _selectedVoiceId;
  double _rate = 0.48;
  double _pitch = 1.0;

  String? get messageId => _messageId;
  bool get isSpeaking => _speaking;
  bool get isInitialized => _initialized;
  List<VoiceOption> get voices => List.unmodifiable(_voices);
  List<String> get engines => List.unmodifiable(_engines);
  String? get selectedEngine => _selectedEngine;
  double get rate => _rate;
  double get pitch => _pitch;
  VoiceOption? get selectedVoice =>
      _voices.where((voice) => voice.id == _selectedVoiceId).firstOrNull;
  String get selectedVoiceLabel =>
      selectedVoice?.label ?? 'System default voice';
  String get selectedEngineLabel => _selectedEngine == null
      ? 'System default engine'
      : _friendlyEngineName(_selectedEngine!);
  String engineLabel(String engine) => _friendlyEngineName(engine);

  bool isSpeakingMessage(String id) => _speaking && _messageId == id;

  Future<void> toggle({required String messageId, required String text}) async {
    if (text.trim().isEmpty) return;
    if (isSpeakingMessage(messageId)) {
      await stop();
      return;
    }

    await _tts.stop();
    _messageId = messageId;
    _speaking = true;
    notifyListeners();

    if (!_initialized) await _initialize();
    final voice = selectedVoice;
    if (voice != null) {
      await _tts.setVoice(voice.platformValue);
    } else {
      final locale = PlatformDispatcher.instance.locale.toLanguageTag();
      final available = await _tts.isLanguageAvailable(locale);
      await _tts.setLanguage(
        available == true || available == 1 ? locale : 'en-US',
      );
    }
    await _tts.setSpeechRate(_rate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(1.0);
    await _tts.speak(text);
  }

  Future<void> selectVoice(VoiceOption? voice) async {
    _selectedVoiceId = voice?.id;
    if (voice != null) await _tts.setVoice(voice.platformValue);
    await _persist();
    notifyListeners();
  }

  Future<void> selectEngine(String engine) async {
    if (engine == _selectedEngine) return;
    await _tts.stop();
    await _tts.setEngine(engine);
    _selectedEngine = engine;
    _selectedVoiceId = null;
    await _loadVoices();
    await _persist();
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    _rate = value.clamp(0.2, 0.8);
    await _tts.setSpeechRate(_rate);
    await _persist();
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value.clamp(0.5, 1.5);
    await _tts.setPitch(_pitch);
    await _persist();
    notifyListeners();
  }

  Future<void> preview() => toggle(
    messageId: '__voice_preview__',
    text: 'This is how Erebrus AI will sound.',
  );

  Future<void> _initialize() async {
    if (_initialized) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _selectedEngine = preferences.getString('speech_engine');
      _selectedVoiceId = preferences.getString('speech_voice_id');
      _rate = preferences.getDouble('speech_rate') ?? _rate;
      _pitch = preferences.getDouble('speech_pitch') ?? _pitch;
      final rawEngines = await _tts.getEngines;
      if (rawEngines is List) {
        _engines = rawEngines.map((engine) => '$engine').toList()..sort();
      }
      if (_selectedEngine != null && _engines.contains(_selectedEngine)) {
        await _tts.setEngine(_selectedEngine!);
      } else {
        _selectedEngine = (await _tts.getDefaultEngine)?.toString();
      }
      await _loadVoices();
      if (selectedVoice != null) {
        await _tts.setVoice(selectedVoice!.platformValue);
      }
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
    } catch (error) {
      debugPrint('[Speech] voice initialization failed: $error');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    if (_selectedEngine == null) {
      await preferences.remove('speech_engine');
    } else {
      await preferences.setString('speech_engine', _selectedEngine!);
    }
    if (_selectedVoiceId == null) {
      await preferences.remove('speech_voice_id');
    } else {
      await preferences.setString('speech_voice_id', _selectedVoiceId!);
    }
    await preferences.setDouble('speech_rate', _rate);
    await preferences.setDouble('speech_pitch', _pitch);
  }

  Future<void> _loadVoices() async {
    final rawVoices = await _tts.getVoices;
    if (rawVoices is! List) {
      _voices = const [];
      return;
    }
    final deviceLocale = PlatformDispatcher.instance.locale.toLanguageTag();
    final deviceLanguage = deviceLocale.split(RegExp('[-_]')).first;
    _voices =
        rawVoices
            .whereType<Map>()
            .map(VoiceOption.fromPlatform)
            .where((voice) => voice.name.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final priority = _voicePriority(
              a.locale,
              deviceLocale,
              deviceLanguage,
            ).compareTo(_voicePriority(b.locale, deviceLocale, deviceLanguage));
            if (priority != 0) return priority;
            final locale = a.locale.compareTo(b.locale);
            return locale != 0 ? locale : a.name.compareTo(b.name);
          });
  }

  static int _voicePriority(
    String locale,
    String deviceLocale,
    String deviceLanguage,
  ) {
    final normalized = locale.replaceAll('_', '-').toLowerCase();
    final preferred = deviceLocale.replaceAll('_', '-').toLowerCase();
    if (normalized == preferred) return 0;
    if (normalized.split('-').first == deviceLanguage.toLowerCase()) return 1;
    if (normalized == 'en' || normalized.startsWith('en-')) return 2;
    return 3;
  }

  static String _friendlyEngineName(String engine) {
    final parts = engine.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return engine;
    return parts.last
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAllMapped(
          RegExp(r'\b\w'),
          (match) => match.group(0)!.toUpperCase(),
        );
  }

  Future<void> stop() async {
    await _tts.stop();
    _finish();
  }

  void _finish() {
    _speaking = false;
    _messageId = null;
    notifyListeners();
  }
}

class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    required this.platformValue,
  });

  factory VoiceOption.fromPlatform(Map<dynamic, dynamic> value) {
    final map = value.map((key, value) => MapEntry('$key', '$value'));
    final name = map['name'] ?? '';
    final locale = map['locale'] ?? '';
    final identifier = map['identifier'];
    return VoiceOption(
      id: identifier?.isNotEmpty == true ? identifier! : '$name|$locale',
      name: name,
      locale: locale,
      platformValue: {
        if (identifier?.isNotEmpty == true) 'identifier': identifier!,
        'name': name,
        'locale': locale,
      },
    );
  }

  final String id;
  final String name;
  final String locale;
  final Map<String, String> platformValue;

  String get label => locale.isEmpty ? name : '$name · $locale';
}
