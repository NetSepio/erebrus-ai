import 'package:audioplayers/audioplayers.dart';
import 'package:erebrus_ai/screens/transcribe/transcribe_screen.dart';
import 'package:erebrus_ai/services/transcription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('analysis prompt fits above a mobile keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(() {
      tester.view.reset();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => analysisPromptDialogForTest(
                  'A sufficiently long transcript for analysis.',
                ),
              ),
              child: const Text('ANALYZE'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ANALYZE'));
    await tester.pumpAndSettle();

    expect(find.text('Prepare analysis prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('saved audio playback explicitly routes to the speaker', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final context = transcriptionPlaybackAudioContext();
    expect(context.iOS.category, AVAudioSessionCategory.playAndRecord);
    expect(
      context.iOS.options,
      contains(AVAudioSessionOptions.defaultToSpeaker),
    );
    expect(context.android.isSpeakerphoneOn, isTrue);
  });
}
