import 'package:erebrus_ai/services/transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto transcription uses the device locale for SpeechAnalyzer', () {
    expect(resolveTranscriptionLocale('auto', deviceLocale: 'hi-IN'), 'hi-IN');
    expect(resolveTranscriptionLocale('', deviceLocale: 'fr-FR'), 'fr-FR');
  });

  test('an explicit transcription locale takes precedence', () {
    expect(resolveTranscriptionLocale('ja-JP', deviceLocale: 'en-US'), 'ja-JP');
  });
}
