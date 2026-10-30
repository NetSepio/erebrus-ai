import 'package:erebrus_ai/app.dart';
import 'package:erebrus_ai/auth/auth_session_store.dart';
import 'package:erebrus_ai/auth/session_mutex.dart';
import 'package:erebrus_ai/auth/entitlement_state.dart';
import 'package:erebrus_ai/auth/gateway_auth_client.dart';
import 'package:erebrus_ai/auth/user_org_invite.dart';
import 'package:erebrus_ai/auth/user_profile.dart';
import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:erebrus_ai/data/catalog_service.dart';
import 'package:erebrus_ai/data/model_catalog.dart';
import 'package:erebrus_ai/org/org_state.dart';
import 'package:erebrus_ai/screens/auth/sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Completing sign-in closes the sign-in page and anything stacked on it
/// (email sheet, wallet modal) exactly once. Popping twice used to remove
/// the home route and leave a black screen on Android.
void main() {
  setUpAll(() => CatalogService.setEntries(modelCatalog));

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'default_model_id': 'smollm2-135m-instruct',
      'default_model_variant_id': 'smollm2-135m-instruct-gguf-q8_0',
    }),
  );

  testWidgets('successful sign-in returns to the shell without over-popping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = WalletAuthController(
      authClient: _FakeAuthClient(),
      sessionMutex: _TestMutex(),
      store: _MemorySessionStore(),
    );
    await tester.pumpWidget(
      ErebrusApp(
        auth: auth,
        orgState: OrgState(auth: auth),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('SETTINGS'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('SIGN IN / REGISTER'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Erebrus AI'), findsOneWidget);

    // A sheet above the sign-in page, like the email code sheet.
    showModalBottomSheet<void>(
      context: tester.element(find.text('Welcome to Erebrus AI')),
      builder: (_) => const SizedBox(height: 200, child: Text('code sheet')),
    );
    await tester.pumpAndSettle();
    expect(find.text('code sheet'), findsOneWidget);

    final verify = auth.verifyEmailLoginCode(
      email: 'user@example.com',
      code: '123456',
    );
    await tester.pumpAndSettle();
    await verify;
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isTrue);
    expect(find.text('code sheet'), findsNothing);
    expect(find.text('Welcome to Erebrus AI'), findsNothing);
    // The shell (home route) is still mounted and is the only route.
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.text('SETTINGS'))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'retained sessions can sign in again without closing the page early',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _MemorySessionStore()
        ..session = const StoredAuthSession(
          token: 'old',
          userId: 'user-1',
          walletAddress: '',
          role: 'user',
          authMethod: 'email',
          renewalPending: true,
        );
      final auth = WalletAuthController(
        authClient: _FakeAuthClient(),
        store: store,
        sessionMutex: _TestMutex(),
      );
      await auth.loadPersistedSession();
      final org = OrgState(auth: auth);
      await tester.pumpWidget(ErebrusApp(auth: auth, orgState: org));
      await tester.pumpAndSettle();
      openSignIn(tester.element(find.text('SETTINGS')));
      await tester.pumpAndSettle();
      await auth.revalidateSession();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Erebrus AI'), findsOneWidget);
      await auth.verifyEmailLoginCode(
        email: 'user@example.com',
        code: '123456',
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Erebrus AI'), findsNothing);
      expect(auth.bearerToken, 'session-token');
      await tester.pumpWidget(const SizedBox.shrink());
      org.dispose();
      auth.dispose();
    },
  );

  testWidgets('resuming after 25 hours renews without a suspended timer', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 19);
    final client = _FakeAuthClient()..now = () => now;
    final store = _MemorySessionStore()
      ..session = StoredAuthSession(
        token: 'old',
        refreshToken: 'refresh-old',
        sessionId: 'session',
        userId: 'user-1',
        role: 'user',
        walletAddress: '',
        authMethod: 'email',
        expiresAt: now.add(const Duration(hours: 24)),
        refreshExpiresAt: now.add(const Duration(days: 30)),
      );
    final auth = WalletAuthController(
      authClient: client,
      store: store,
      sessionMutex: _TestMutex(),
      now: () => now,
    );
    await auth.loadPersistedSession();
    final org = OrgState(auth: auth);
    await tester.pumpWidget(ErebrusApp(auth: auth, orgState: org));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 25));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.refreshes, 1);
    expect(auth.bearerToken, 'replacement');
    expect(store.session!.refreshToken, 'refresh-replacement');
    await tester.pumpWidget(const SizedBox.shrink());
    org.dispose();
    auth.dispose();
  });
}

class _FakeAuthClient extends GatewayAuthClient {
  int refreshes = 0;
  DateTime Function() now = DateTime.now;

  @override
  Future<AuthSession> refreshSession(String token) async {
    refreshes++;
    return AuthSession(
      token: 'replacement',
      refreshToken: 'refresh-replacement',
      tokenType: 'Bearer',
      sessionId: 'session',
      userId: 'user-1',
      role: 'user',
      walletAddress: '',
      expiresAt: now().add(const Duration(hours: 24)),
      refreshExpiresAt: now().add(const Duration(days: 30)),
    );
  }

  @override
  Future<AuthSession> emailLoginVerify({
    required String email,
    required String code,
  }) async => const AuthSession(
    token: 'session-token',
    userId: 'user-1',
    role: 'user',
    walletAddress: '',
  );

  @override
  Future<EntitlementState> fetchSubscription(String bearerToken) async =>
      EntitlementState.none;

  @override
  Future<UserProfile> fetchProfile(String bearerToken) async =>
      const UserProfile(id: 'user-1', email: 'user@example.com');

  @override
  Future<List<UserOrgInvite>> fetchAccountOrgInvites(
    String bearerToken,
  ) async => const [];

  @override
  Future<RankStanding> fetchRank(String bearerToken) async => RankStanding.zero;

  @override
  Future<AuthMethods> fetchAuthMethods() async => AuthMethods.unknown;
}

class _MemorySessionStore extends AuthSessionStore {
  StoredAuthSession? session;

  @override
  Future<void> save(StoredAuthSession value) async => session = value;

  @override
  Future<StoredAuthSession?> read() async => session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<void> write({
    required String token,
    required String walletAddress,
    required String userId,
    required String role,
    required String authMethod,
    String? mwaAuthToken,
  }) async {
    session = StoredAuthSession(
      token: token,
      walletAddress: walletAddress,
      userId: userId,
      role: role,
      authMethod: authMethod,
      mwaAuthToken: mwaAuthToken,
    );
  }
}

class _TestMutex extends SessionMutex {
  @override
  Future<T> synchronized<T>(Future<T> Function() action) => action();
}
