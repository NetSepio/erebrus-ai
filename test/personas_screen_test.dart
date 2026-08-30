import 'dart:io';

import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:erebrus_ai/data/mock_data.dart';
import 'package:erebrus_ai/org/org_state.dart';
import 'package:erebrus_ai/screens/personas/personas_screen.dart';
import 'package:erebrus_ai/services/persona_service.dart';
import 'package:erebrus_ai/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('PersonaService unit tests', () {
    test('provides built-in personas and allows custom saving and deleting', () async {
      final service = PersonaService.instance;
      expect(service.builtIns, isNotEmpty);
      expect(service.defaultPersona.name, isNotEmpty);

      // Create a custom persona
      const custom = MockPersona(
        'Custom Test Bot',
        'CB',
        'TEMP 0.8 · 1024 MAX',
        builtIn: false,
        systemPrompt: 'You are a test bot.',
        maxTokens: 1024,
      );

      final saved = await service.save(custom);
      expect(saved.id, isNotNull);
      expect(saved.name, equals('Custom Test Bot'));
      expect(service.userPersonas.any((p) => p.effectiveId == saved.effectiveId), isTrue);
      expect(service.byId(saved.effectiveId), isNotNull);

      // Modify the saved persona
      final updated = saved.copyWith(name: 'Updated Test Bot');
      await service.save(updated);
      expect(service.byId(saved.effectiveId)?.name, equals('Updated Test Bot'));

      // Delete the persona
      await service.delete(saved.effectiveId);
      expect(service.userPersonas.any((p) => p.effectiveId == saved.effectiveId), isFalse);
    });
  });

  group('PersonasScreen widget tests', () {
    testWidgets('renders desktop layout with list and editor side-by-side', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
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
              body: PersonasScreen(wide: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERSONAS'), findsOneWidget);
      expect(find.text('BUILT-IN'), findsOneWidget);
      expect(find.text('Concise Analyst'), findsWidgets);
      expect(find.text('SYSTEM PROMPT'), findsOneWidget);
    });

    testWidgets('renders mobile layout with list', (tester) async {
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
              body: PersonasScreen(wide: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personas'), findsOneWidget);
      expect(find.text('BUILT-IN'), findsOneWidget);
      expect(find.text('Concise Analyst'), findsOneWidget);
    });

    testWidgets('PersonaEditor renders form fields and controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = WalletAuthController();
      final orgState = OrgState(auth: auth);
      final appState = AppState(auth: auth, orgState: orgState);

      const testPersona = MockPersona(
        'Code Assistant',
        'CA',
        'TEMP 0.2 · 2048 MAX',
        builtIn: false,
        systemPrompt: 'You are an expert coder.',
        maxTokens: 2048,
      );

      await tester.pumpWidget(
        AppScope(
          state: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: PersonaEditor(
                persona: testPersona,
                wide: true,
                showBack: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Code Assistant'), findsWidgets);
      expect(find.text('SYSTEM PROMPT'), findsOneWidget);
      expect(find.text('You are an expert coder.'), findsOneWidget);
      expect(find.text('SAMPLING'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Max tokens'), findsOneWidget);
    });
  });
}
