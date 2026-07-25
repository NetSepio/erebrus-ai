import 'dart:io';

import 'package:erebrus_ai/app.dart';
import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/org/org_state.dart';
import 'package:erebrus_ai/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // Use the compiled-in catalog in widget tests so remote network calls are
    // not attempted and expected model names stay stable.
    CatalogService.setEntries(modelCatalog);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    WalletAuthController? auth,
    OrgState? orgState,
    double topPadding = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(top: topPadding);
    addTearDown(() {
      tester.view.reset();
      tester.view.resetPadding();
    });
    final controller = auth ?? WalletAuthController();
    await tester.pumpWidget(
      ErebrusApp(
        auth: controller,
        orgState: orgState ?? OrgState(auth: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('desktop 1280x800', () {
    testWidgets('chat, models, personas, settings render', (tester) async {
      await pumpApp(tester, const Size(1280, 800));

      // Chat (default tab) — sidebar + sessions + streaming status.
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('GUEST MODE'), findsOneWidget);
      expect(find.text('Node paused'), findsOneWidget);

      // Models → NETWORK tab with guest gate.
      await tester.tap(find.text('MODELS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Models'), findsOneWidget);
      await tester.tap(find.text('NETWORK · 0'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Private workspace models'), findsOneWidget);
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
      await tester.scrollUntilVisible(
        find.text('Assistant voice'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Assistant voice'), findsOneWidget);
    });

    testWidgets('sign-in page swaps guest → signed-in content', (tester) async {
      await pumpApp(tester, const Size(1280, 800));

      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('SIGN IN / REGISTER'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Erebrus AI'), findsOneWidget);
      expect(find.text('CONTINUE AS GUEST'), findsOneWidget);

      // Real browser/native auth cannot run in widget tests, so toggle signed-in state
      // through AppScope and close the sign-in surface to verify the signed-in
      // UI surfaces.
      final appContext = tester.element(find.text('Welcome to Erebrus AI'));
      AppScope.of(appContext).signIn();
      Navigator.of(appContext).pop();
      await tester.pumpAndSettle();

      // Back on settings, signed in now.
      expect(find.text('Erebrus account'), findsOneWidget);
      expect(find.text('Create an organization'), findsOneWidget);

      // Org node card appears in models network tab.
      await tester.tap(find.text('MODELS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('NETWORK · 0'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No models shared with this workspace'), findsOneWidget);

      // Sign out restores guest state.
      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sign out'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlock private models & workspaces'), findsOneWidget);
    });

    testWidgets('model picker opens as dialog', (tester) async {
      await pumpApp(tester, const Size(1280, 800));
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();
      expect(find.text('SWITCH MODEL'), findsOneWidget);
      expect(find.text('No downloaded models'), findsOneWidget);
    });
  });

  group('mobile 390x844', () {
    testWidgets('onboarding completion survives app restart', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      expect(find.text('01 / PRIVATE AI'), findsOneWidget);

      await tester.tap(find.text('SKIP'));
      await tester.pumpAndSettle();
      expect(find.text('01 / PRIVATE AI'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpApp(tester, const Size(390, 844));
      expect(find.text('01 / PRIVATE AI'), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
    });

    testWidgets('shell content clears the system status bar', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      await pumpApp(tester, const Size(390, 844), topPadding: 48);

      expect(
        tester.getTopLeft(find.text('Select model')).dy,
        greaterThanOrEqualTo(48),
      );
    });

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

      expect(find.text('04 / INSTALL YOUR ON-DEVICE AI'), findsOneWidget);
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text('START USING EREBRUS'), findsOneWidget);

      await tester.tap(find.text('CONTINUE WITHOUT LOCAL AI'));
      await tester.pump(const Duration(milliseconds: 400));

      // Shell opens on the Models network tab.
      expect(find.text('CHAT'), findsOneWidget);
      expect(find.text('Private workspace models'), findsOneWidget);
    });

    testWidgets('models tabs, settings, and sign-in page', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      // Skip onboarding — goes straight to the Models screen.
      await tester.tap(find.text('SKIP'));
      await tester.pump(const Duration(milliseconds: 400));

      // Skip lands on the network tab; switch to local to verify local list.
      await tester.tap(find.textContaining('LOCAL ·'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('STORAGE · 0 MB USED'), findsOneWidget);
      expect(find.text('No Erebrus nodes discovered'), findsOneWidget);

      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Serve while app is open'), findsOneWidget);
      expect(find.text('Maximum response length'), findsOneWidget);
      expect(find.text('Default · ErebrusAI/models'), findsOneWidget);

      // Sign-in is a full-screen page with guest escape.
      await tester.tap(find.text('SIGN IN / REGISTER'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Erebrus AI'), findsOneWidget);
      await tester.tap(find.text('CONTINUE AS GUEST'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock private models & workspaces'), findsOneWidget);
    });
  });
}
