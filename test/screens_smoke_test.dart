import 'dart:io';

import 'package:erebrus_ai/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Screens-only smoke tests: every screen builds at desktop (1280×800) and
/// mobile (390×844) sizes, in guest and signed-in states, without exceptions.
///
/// The real app fonts are loaded so text metrics (and overflow checks) match
/// what users see instead of the square-glyph Ahem test font.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Future<ByteData> read(String path) async =>
        ByteData.sublistView(File(path).readAsBytesSync());

    final grotesk = FontLoader('Space Grotesk')
      ..addFont(read('assets/fonts/SpaceGrotesk-Variable.ttf'));
    await grotesk.load();

    final mono = FontLoader('IBM Plex Mono')
      ..addFont(read('assets/fonts/IBMPlexMono-Regular.ttf'))
      ..addFont(read('assets/fonts/IBMPlexMono-Medium.ttf'))
      ..addFont(read('assets/fonts/IBMPlexMono-SemiBold.ttf'));
    await mono.load();
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ErebrusApp());
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('desktop 1280x800', () {
    testWidgets('chat, models, personas, settings render', (tester) async {
      await pumpApp(tester, const Size(1280, 800));

      // Chat (default tab) — sidebar + sessions + streaming status.
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('GUEST MODE'), findsOneWidget);
      expect(find.text('Serving on LAN'), findsOneWidget);

      // Models → NETWORK tab with guest gate.
      await tester.tap(find.text('MODELS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Models'), findsOneWidget);
      expect(find.text('LOADED'), findsOneWidget);
      await tester.tap(find.text('NETWORK · 2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Erebrus AI on MacBook-Pro'), findsOneWidget);
      expect(find.text('Private workspace models'), findsOneWidget);

      // Personas editor.
      await tester.tap(find.text('PERSONAS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SYSTEM PROMPT'), findsOneWidget);
      expect(find.text('SAVE PERSONA'), findsOneWidget);
      expect(find.text('Share to workspace'), findsOneWidget);

      // Settings (guest).
      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlock private models & workspaces'), findsOneWidget);
      expect(find.text('Serve on local network'), findsOneWidget);
      expect(find.text('EREBRUS AI 0.1.0 · LLAMA.CPP B4432'), findsOneWidget);
    });

    testWidgets('sign-in page swaps guest → signed-in content',
        (tester) async {
      await pumpApp(tester, const Size(1280, 800));

      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('SIGN IN / REGISTER'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Erebrus AI'), findsOneWidget);
      expect(find.text('CONTINUE AS GUEST'), findsOneWidget);

      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();

      // Back on settings, signed in now.
      expect(find.text('shachi.eth'), findsOneWidget);
      expect(find.text('NetSepio Workspace'), findsOneWidget);
      expect(find.text('Pending invites'), findsOneWidget);

      // Org node card appears in models network tab.
      await tester.tap(find.text('MODELS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('NETWORK · 2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Sec-Analyst 8B'), findsOneWidget);
      expect(find.text('PRIVATE'), findsOneWidget);
      expect(find.text('Private workspace models'), findsNothing);

      // Sign out restores guest state.
      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sign out'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlock private models & workspaces'), findsOneWidget);
    });

    testWidgets('model picker opens as dialog', (tester) async {
      await pumpApp(tester, const Size(1280, 800));
      await tester.tap(find.text('Qwen 3.5 0.8B'));
      await tester.pumpAndSettle();
      expect(find.text('SWITCH MODEL'), findsOneWidget);
      expect(find.text('Qwen 3.5 14B'), findsOneWidget);
    });
  });

  group('mobile 390x844', () {
    testWidgets('onboarding pages → first model → shell', (tester) async {
      await pumpApp(tester, const Size(390, 844));

      expect(find.text('01 / PRIVATE AI'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('02 / ONE NETWORK'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('03 / GUEST FIRST'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('04 / PICK YOUR FIRST MODEL'), findsOneWidget);
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text('START CHATTING'), findsOneWidget);

      await tester.tap(find.text('SKIP — USE A NETWORK MODEL'));
      await tester.pump(const Duration(milliseconds: 400));

      // Shell with bottom nav + chat.
      expect(find.text('CHAT'), findsOneWidget);
      expect(find.text('ON-DEVICE · NOTHING LEAVES YOUR PHONE'), findsOneWidget);
    });

    testWidgets('models tabs, settings, and sign-in sheet', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      // Skip onboarding quickly.
      await tester.tap(find.text('SKIP'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('SKIP — USE A NETWORK MODEL'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('MODELS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('STORAGE · 1.9 GB OF 128 GB'), findsOneWidget);
      expect(find.text('2 nodes on your network'), findsOneWidget);

      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Serve while app is open'), findsOneWidget);
      expect(find.text('Pause on low battery'), findsOneWidget);

      // Sign-in bottom sheet with guest escape.
      await tester.tap(find.text('SIGN IN / REGISTER'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Erebrus'), findsOneWidget);
      await tester.tap(find.text('NOT NOW — KEEP USING AS GUEST'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock private models & workspaces'), findsOneWidget);
    });
  });
}
