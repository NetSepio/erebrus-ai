import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:erebrus_ai/auth/auth_session_store.dart';
import 'package:erebrus_ai/auth/entitlement_state.dart';
import 'package:erebrus_ai/auth/gateway_auth_client.dart';
import 'package:erebrus_ai/auth/user_org_invite.dart';
import 'package:erebrus_ai/auth/user_profile.dart';
import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GatewayAuthClient failures', () {
    test('preserves status and API code and reports bearer 401', () async {
      final server = await _serverReturning(HttpStatus.unauthorized, {
        'error': {'code': 'token_expired', 'message': 'Expired'},
      });
      addTearDown(() => server.close(force: true));
      final rejectedTokens = <String>[];
      final client = GatewayAuthClient(
        gatewayUrl: 'http://${server.address.host}:${server.port}',
        onUnauthorized: (token) async => rejectedTokens.add(token),
      );

      await expectLater(
        client.fetchSubscription('expired-token'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'token_expired')
              .having((e) => e.message, 'message', 'Expired'),
        ),
      );
      expect(rejectedTokens, ['expired-token']);
    });

    test('does not report bearer 403 as an expired session', () async {
      final server = await _serverReturning(HttpStatus.forbidden, {
        'code': 'not_allowed',
        'message': 'Forbidden',
      });
      addTearDown(() => server.close(force: true));
      var unauthorizedCalls = 0;
      final client = GatewayAuthClient(
        gatewayUrl: 'http://${server.address.host}:${server.port}',
        onUnauthorized: (_) async => unauthorizedCalls++,
      );

      await expectLater(
        client.fetchSubscription('valid-token'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'not_allowed'),
        ),
      );
      expect(unauthorizedCalls, 0);
    });
  });

  test(
    'concurrent bearer 401 handling clears a session exactly once',
    () async {
      final store = _MemorySessionStore(_storedSession);
      final controller = WalletAuthController(
        authClient: _SuccessfulAuthClient(),
        store: store,
      );
      await controller.loadPersistedSession();

      await Future.wait([
        controller.handleBearerUnauthorized('session-token'),
        controller.handleBearerUnauthorized('session-token'),
      ]);

      expect(controller.isAuthenticated, isFalse);
      expect(controller.authError, kSessionExpiredMessage);
      expect(controller.sessionExpiredRevision, 1);
      expect(store.clearCount, 1);
    },
  );

  test('stored sessions are revalidated before restore completes', () async {
    final store = _MemorySessionStore(_storedSession);
    final client = _UnauthorizedAuthClient();
    final controller = WalletAuthController(authClient: client, store: store);

    await controller.loadPersistedSession();

    expect(client.validatedTokens, ['session-token']);
    expect(controller.isAuthenticated, isFalse);
    expect(controller.authError, kSessionExpiredMessage);
    expect(store.clearCount, 1);
  });
}

Future<HttpServer> _serverReturning(
  int status,
  Map<String, Object> body,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.first.then((request) async {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    }),
  );
  return server;
}

const _storedSession = StoredAuthSession(
  token: 'session-token',
  walletAddress: 'wallet',
  userId: 'user',
  role: 'user',
  authMethod: 'email',
);

class _MemorySessionStore extends AuthSessionStore {
  _MemorySessionStore(this.session);

  StoredAuthSession? session;
  int clearCount = 0;

  @override
  Future<StoredAuthSession?> read() async => session;

  @override
  Future<void> clear() async {
    clearCount++;
    session = null;
  }

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

class _SuccessfulAuthClient extends GatewayAuthClient {
  @override
  Future<EntitlementState> fetchSubscription(String bearerToken) async =>
      EntitlementState.none;

  @override
  Future<UserProfile> fetchProfile(String bearerToken) async =>
      const UserProfile(id: 'user');

  @override
  Future<List<UserOrgInvite>> fetchAccountOrgInvites(
    String bearerToken,
  ) async => const [];
}

class _UnauthorizedAuthClient extends _SuccessfulAuthClient {
  final validatedTokens = <String>[];

  @override
  Future<EntitlementState> fetchSubscription(String bearerToken) async {
    validatedTokens.add(bearerToken);
    await onUnauthorized?.call(bearerToken);
    throw AuthException(
      'Expired',
      statusCode: HttpStatus.unauthorized,
      code: 'token_expired',
    );
  }
}
