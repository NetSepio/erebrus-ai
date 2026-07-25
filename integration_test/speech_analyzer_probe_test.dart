import 'package:erebrus_speech/erebrus_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports the native SpeechAnalyzer capability', (tester) async {
    const speech = ErebrusSpeech();

    final probe = await speech.probe(locale: 'en-US');

    expect(probe.platform, anyOf('macos-arm64', 'ios-arm64'));
    expect(probe.minimumOperatingSystem, isNotEmpty);
    expect(probe.assetStatus, isNotEmpty);
    if (probe.available) {
      expect(probe.localeSupported, isTrue);
      expect(probe.locale, isNotEmpty);
    } else {
      expect(probe.reason, isNotEmpty);
    }
  });
}
