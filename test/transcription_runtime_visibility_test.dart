import 'package:erebrus_ai/screens/transcribe/transcribe_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SpeechAnalyzer devices never show the Whisper runtime', () {
    expect(
      shouldShowWhisperRuntime(
        checking: false,
        speechReady: true,
        whisperReady: false,
      ),
      isFalse,
    );
    expect(
      shouldShowWhisperRuntime(
        checking: false,
        speechReady: true,
        whisperReady: true,
      ),
      isFalse,
    );
  });

  test('fallback-only devices always show Whisper setup status', () {
    expect(
      shouldShowWhisperRuntime(
        checking: false,
        speechReady: false,
        whisperReady: true,
      ),
      isTrue,
    );
    expect(
      shouldShowWhisperRuntime(
        checking: false,
        speechReady: false,
        whisperReady: false,
      ),
      isTrue,
    );
  });
}
