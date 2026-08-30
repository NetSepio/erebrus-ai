import 'dart:io';

import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/org/org_state.dart';
import 'package:erebrus_ai/screens/onboarding/onboarding_flow.dart';
import 'package:erebrus_ai/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    CatalogService.setEntries(modelCatalog);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': false,
    });
  });

  testWidgets('OnboardingFlow renders initial slide and steps through stories', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final auth = WalletAuthController();
    final orgState = OrgState(auth: auth);
    final appState = AppState(auth: auth, orgState: orgState);

    await tester.pumpWidget(
      AppScope(
        state: appState,
        child: const MaterialApp(
          home: Scaffold(
            body: OnboardingFlow(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Slide 1
    expect(find.text('01 / PRIVATE AI'), findsOneWidget);
    expect(find.text('Your models. Your hardware. Your rules.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);

    // Advance to Slide 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('02 / ONE NETWORK'), findsOneWidget);
    expect(find.text('Every device shares its models.'), findsOneWidget);

    // Advance to Slide 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('03 / GUEST FIRST'), findsOneWidget);
    expect(find.text('No account. Unless you want one.'), findsOneWidget);
  });

  testWidgets('OnboardingFlow skip jumps to model setup step', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final auth = WalletAuthController();
    final orgState = OrgState(auth: auth);
    final appState = AppState(auth: auth, orgState: orgState);

    await tester.pumpWidget(
      AppScope(
        state: appState,
        child: const MaterialApp(
          home: Scaffold(
            body: OnboardingFlow(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap SKIP on first slide
    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();

    // Should now be on the model setup slide
    expect(find.text('04 / INSTALL YOUR ON-DEVICE AI'), findsOneWidget);
    expect(find.text('Install a private default model'), findsOneWidget);
  });
}
