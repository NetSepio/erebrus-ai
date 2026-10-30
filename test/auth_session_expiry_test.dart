import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:erebrus_ai/auth/auth_session_repository.dart';
import 'package:erebrus_ai/auth/auth_session_store.dart';
import 'package:erebrus_ai/auth/gateway_auth_client.dart';
import 'package:erebrus_ai/auth/session_mutex.dart';
import 'package:erebrus_ai/auth/wallet_auth_controller.dart';
import 'package:erebrus_ai/org/org_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _epoch = DateTime.utc(2026, 10, 19);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late _Harness h;
  setUp(() async => h = await _Harness.create());
  tearDown(() async => h.close());

  test(
    'metadata accepts access_token alias, epoch/ISO expiry and relative TTLs',
    () {
      final payload = _payload('new', _epoch)..['token'] = 'legacy-alias';
      final session = AuthSession.fromJson(payload, now: _epoch);
      expect(session.token, 'new');
      expect(session.refreshToken, 'refresh-new');
      expect(session.expiresAt, _epoch.add(const Duration(hours: 24)));
      expect(session.refreshExpiresAt, _epoch.add(const Duration(days: 30)));
      expect(session.sessionId, 'session-1');
      expect(session.tokenType, 'Bearer');
      payload.remove('access_token');
      payload['expires_at'] = _epoch.millisecondsSinceEpoch ~/ 1000;
      expect(AuthSession.fromJson(payload).token, 'legacy-alias');
      expect(AuthSession.fromJson(payload).expiresAt, _epoch);
      payload.remove('expires_at');
      expect(
        AuthSession.fromJson(payload, now: _epoch).expiresAt,
        _epoch.add(const Duration(hours: 24)),
      );
    },
  );

  test(
    'all direct login providers parse the complete replacement payload',
    () async {
      h.handler = (request) async =>
          _reply(request, _payload('provider', h.now));
      final client = h.client;
      final sessions = await Future.wait([
        client.authenticate(
          flowId: 'flow',
          signature: 'signature',
          publicKey: 'wallet',
        ),
        client.emailLoginVerify(email: 'test@example.com', code: '123456'),
        client.googleLogin('google-id'),
        client.appleLogin(
          idToken: 'apple-id',
          authorizationCode: 'code',
          nonce: 'nonce',
          state: 'state',
        ),
      ]);
      for (final session in sessions) {
        expect(session.token, 'provider');
        expect(session.refreshToken, 'refresh-provider');
        expect(session.expiresIn, 86400);
        expect(session.refreshExpiresIn, 2592000);
        expect(session.refreshExpiresAt, h.now.add(const Duration(days: 30)));
      }
    },
  );

  test(
    'secure store commits one session item, migrates legacy and tombstones logout',
    () async {
      final values = <String, String>{
        AuthSessionStore.kToken: 'opaque-v4.local.legacy',
        AuthSessionStore.kUserId: 'user',
      };
      FlutterSecureStorage.setMockInitialValues(values);
      final store = AuthSessionStore();
      final legacy = await store.read();
      expect(legacy!.token, 'opaque-v4.local.legacy');
      expect(legacy.refreshToken, isNull);
      await store.save(_stored('new', h.now));
      final encoded = jsonDecode(values[AuthSessionStore.kSession]!) as Map;
      expect(encoded['session']['refresh_token'], 'refresh-new');
      expect(values.containsKey(AuthSessionStore.kToken), isFalse);
      final restored = await store.read();
      expect(restored!.refreshToken, 'refresh-new');
      expect(restored.expiresAt, h.now.add(const Duration(hours: 24)));
      await store.clear();
      values[AuthSessionStore.kToken] = 'left-over-legacy';
      expect(await store.read(), isNull);
    },
  );

  test(
    'unreadable secure record is retained, never cleared as a read side effect',
    () async {
      final values = <String, String>{
        AuthSessionStore.kSession: 'corrupt-fixture',
      };
      FlutterSecureStorage.setMockInitialValues(values);
      await expectLater(AuthSessionStore().read(), throwsFormatException);
      expect(values[AuthSessionStore.kSession], 'corrupt-fixture');
    },
  );

  test(
    'startup after over 24 hours restores and rotates before account requests',
    () async {
      h.store.session = _stored(
        'old',
        h.now.subtract(const Duration(hours: 25)),
      );
      final controller = h.controller();
      await controller.loadPersistedSession();
      expect(controller.isAuthenticated, isTrue);
      expect(controller.bearerToken, 'new');
      expect(h.refreshCount, 1);
      expect(h.store.session!.refreshToken, 'refresh-new');
      expect(h.protectedTokens, everyElement('Bearer new'));
      expect(controller.userProfile?.id, 'user');
      expect(controller.sessionExpiredRevision, 0);
      controller.dispose();
    },
  );

  test(
    'resume entry point uses current clock, with no background timer',
    () async {
      h.store.session = _stored('old', h.now);
      final controller = h.controller();
      await controller.loadPersistedSession();
      expect(h.refreshCount, 0);
      h.now = h.now.add(const Duration(hours: 25));
      await controller.revalidateSession();
      expect(h.refreshCount, 1);
      expect(controller.bearerToken, 'new');
      // A new controller models a process restart after the rotation commit.
      final restarted = h.controller();
      await restarted.loadPersistedSession();
      expect(h.refreshCount, 1);
      expect(restarted.bearerToken, 'new');
      controller.dispose();
      restarted.dispose();
    },
  );

  test(
    'resume picks up logout committed by another repository/isolate',
    () async {
      h.store.session = _stored('old', h.now);
      final controller = h.controller();
      await controller.loadPersistedSession();
      expect(controller.userProfile, isNotNull);
      final background = h.repository(
        client: GatewayAuthClient(gatewayUrl: h.base),
      );
      await background.restore();
      await background.logout();
      await controller.revalidateSession();
      expect(controller.isAuthenticated, isFalse);
      expect(controller.userProfile, isNull);
      controller.dispose();
    },
  );

  test(
    '60 second window and concurrent auth/org requests use one persisted replacement',
    () async {
      h.store.session = _stored(
        'old',
        h.now
            .subtract(const Duration(hours: 24))
            .add(const Duration(seconds: 60)),
      );
      final repository = h.repository();
      await repository.restore();
      final org = OrgClient(gatewayUrl: h.base)..sessionRepository = repository;
      await Future.wait([
        ...List.generate(12, (_) => h.client.fetchSubscription('old')),
        org.fetchOrganizations('old'),
      ]);
      expect(h.refreshCount, 1);
      expect(h.refreshBodies, [
        {'refresh_token': 'refresh-old'},
      ]);
      expect(h.refreshBearers, [null]);
      expect(h.protectedTokens, everyElement('Bearer new'));
      expect(h.store.session!.token, 'new');
      expect(h.store.publishedBeforeProtected, isTrue);
    },
  );

  test(
    'two repository instances re-read storage under the same lock',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final first = h.repository();
      final second = h.repository(
        client: GatewayAuthClient(gatewayUrl: h.base),
      );
      await first.restore();
      await second.restore();
      final results = await Future.wait([
        first.validSession('old'),
        second.validSession('old'),
      ]);
      expect(results.map((e) => e.token), ['new', 'new']);
      expect(h.refreshCount, 1);
    },
  );

  test(
    '401 expiry retries once and preserves POST body and idempotency key',
    () async {
      h.store.session = _stored('old', h.now);
      final repository = h.repository();
      await repository.restore();
      final bodies = <String>[];
      final keys = <String?>[];
      h.protectedHandler = (request) async {
        bodies.add(await utf8.decodeStream(request));
        keys.add(request.headers.value('idempotency-key'));
        if (request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer old') {
          await _error(request, 401, 'ACCESS_TOKEN_EXPIRED');
        } else {
          await _reply(request, {'accepted': true});
        }
      };
      final result = await h.client.requestJson(
        'POST',
        Uri.parse('${h.base}/api/v2/action'),
        bearerToken: 'old',
        body: {
          'amount': 7,
          'items': ['x'],
        },
        headers: {'Idempotency-Key': 'stable-key'},
      );
      expect(result['accepted'], isTrue);
      expect(h.refreshCount, 1);
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1]);
      expect(keys, ['stable-key', 'stable-key']);
    },
  );

  test(
    'simultaneous expiry 401s reuse the replacement even after another request renews',
    () async {
      h.store.session = _stored('old', h.now);
      final repository = h.repository();
      await repository.restore();
      final bothRejected = Completer<void>();
      var oldRequests = 0;
      h.protectedHandler = (request) async {
        if (request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer old') {
          if (++oldRequests == 2) bothRejected.complete();
          await bothRejected.future;
          await _error(request, 401, 'ACCESS_TOKEN_EXPIRED');
        } else {
          await _reply(request, {});
        }
      };
      await Future.wait([
        h.client.fetchSubscription('old'),
        h.client.fetchProfile('old'),
      ]);
      expect(h.refreshCount, 1);
      expect(h.protectedTokens.where((e) => e == 'Bearer new').length, 2);
    },
  );

  test(
    'a second expiry 401 is surfaced without another refresh or logout',
    () async {
      h.store.session = _stored('old', h.now);
      final repository = h.repository();
      await repository.restore();
      h.protectedHandler = (request) =>
          _error(request, 401, 'ACCESS_TOKEN_EXPIRED');
      await expectLater(
        h.client.fetchSubscription('old'),
        throwsA(_code('ACCESS_TOKEN_EXPIRED')),
      );
      expect(h.refreshCount, 1);
      expect(h.protectedTokens.length, 2);
      expect(repository.current, isNotNull);
    },
  );

  for (final (code, status) in [
    ('REFRESH_TOKEN_INVALID', 401),
    ('REFRESH_TOKEN_REUSED', 401),
    ('SESSION_REVOKED', 401),
    ('ACCOUNT_SUSPENDED', 403),
  ]) {
    test('$code alone terminates an invalid refresh session', () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final repository = h.repository();
      await repository.restore();
      final reasons = <String?>[];
      repository.onTerminated = (reason) => reasons.add(reason.code);
      h.refreshHandler = (request) => _error(request, status, code);
      await expectLater(repository.validSession('old'), throwsA(_code(code)));
      expect(repository.current, isNull);
      expect(h.store.session, isNull);
      expect(reasons, [code]);
    });
  }

  test('gateway requests carry the client platform label', () async {
    final labels = <String?>[];
    h.handler = (request) async {
      labels.add(request.headers.value('X-Erebrus-Client'));
      await _reply(request, _payload('new', h.now));
    };
    await h.client.refreshSession('refresh-old');
    await h.client.fetchProfile('old');
    expect(labels, [
      GatewayAuthClient.clientLabel,
      GatewayAuthClient.clientLabel,
    ]);
    expect(labels.first, isIn(['android', 'ios', 'desktop']));
  });

  test('a suspended account signs out with a suspension message', () async {
    h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
    final controller = h.controller();
    h.refreshHandler = (request) => _error(request, 403, 'ACCOUNT_SUSPENDED');
    await controller.loadPersistedSession();
    expect(controller.isAuthenticated, isFalse);
    expect(controller.authError, kAccountSuspendedMessage);
    expect(controller.sessionExpiredRevision, 1);
    expect(h.refreshCount, 1);
    expect(h.store.session, isNull);
    controller.dispose();
  });

  test('a new engine takes over the lock left by a destroyed one', () async {
    // An Android activity recreated in a process kept alive by the foreground
    // service starts a new root isolate, but the name server still maps the
    // lock queue to the destroyed engine's port.
    SessionMutex.initialize();
    final dead = ReceivePort();
    IsolateNameServer.removePortNameMapping(SessionMutex.portName);
    IsolateNameServer.registerPortWithName(
      dead.sendPort,
      SessionMutex.portName,
    );
    dead.close();
    h.store.session = _stored('old', h.now);
    final repository = h.repository();

    await repository.restore().timeout(const Duration(seconds: 5));

    expect(repository.current?.token, 'old');
  });

  for (final status in [401, 403, 409, 429, 500, 503]) {
    test(
      'protected $status business/transport failure retains auth and account data',
      () async {
        h.store.session = _stored('old', h.now);
        final controller = h.controller();
        await controller.loadPersistedSession();
        final profile = controller.userProfile;
        final entitlement = controller.entitlement;
        h.protectedHandler = (request) =>
            _error(request, status, 'BUSINESS_ERROR');
        await controller.refreshProfile();
        await controller.refreshEntitlement();
        expect(controller.isAuthenticated, isTrue);
        expect(controller.userProfile, same(profile));
        expect(controller.entitlement, same(entitlement));
        expect(controller.sessionExpiredRevision, 0);
        expect(h.refreshCount, 0);
        controller.dispose();
      },
    );
  }

  for (final failure in ['offline', 'timeout', '500', '503', 'malformed']) {
    test(
      '$failure refresh uncertainty survives restart without replay',
      () async {
        h.store.session = _stored(
          'old',
          h.now.subtract(const Duration(days: 2)),
        );
        var calls = 0;
        final repository = h.repository(
          refresh: (_) async {
            calls++;
            if (failure == 'timeout') throw TimeoutException('fixture');
            if (failure == 'malformed') throw const FormatException('fixture');
            throw AuthException('fixture', statusCode: int.tryParse(failure));
          },
        );
        await repository.restore();
        await expectLater(repository.validSession('old'), throwsA(anything));
        expect(repository.current, isNotNull);
        expect(h.store.session!.renewalPending, isTrue);
        final restarted = h.repository(
          refresh: (_) async {
            calls++;
            return AuthSession.fromJson(_payload('new', h.now));
          },
        );
        await restarted.restore();
        await expectLater(
          restarted.validSession('old'),
          throwsA(_code('SESSION_LOGIN_REQUIRED')),
        );
        expect(calls, 1);
        expect(h.store.clearCount, 0);
      },
    );
  }

  test(
    'proven pre-send connection failure retains auth and allows a later renewal',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      var calls = 0;
      final repository = h.repository(
        refresh: (_) async {
          if (++calls == 1) {
            throw AuthException('No connection', requestMayHaveBeenSent: false);
          }
          return AuthSession.fromJson(_payload('new', h.now));
        },
      );
      await repository.restore();
      await expectLater(
        repository.validSession('old'),
        throwsA(isA<AuthException>()),
      );
      expect(h.store.session!.renewalPending, isFalse);
      expect(repository.current, isNotNull);
      expect((await repository.validSession('old')).token, 'new');
      expect(calls, 2);
    },
  );

  test(
    'connection lost after refresh submission never replays the consumed token',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final repository = h.repository();
      await repository.restore();
      h.refreshHandler = (request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      };
      await expectLater(
        repository.validSession('old'),
        throwsA(isA<AuthException>()),
      );
      expect(h.refreshCount, 1);
      expect(h.store.session!.renewalPending, isTrue);
      await expectLater(
        repository.validSession('old'),
        throwsA(_code('SESSION_LOGIN_REQUIRED')),
      );
      expect(h.refreshCount, 1);
    },
  );

  test(
    'replacement write failure retains pre-send journal and blocks replay',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final repository = h.repository();
      await repository.restore();
      h.store.failReplacement = true;
      await expectLater(repository.validSession('old'), throwsStateError);
      expect(h.store.session!.renewalPending, isTrue);
      expect(h.refreshCount, 1);
      await expectLater(
        repository.validSession('old'),
        throwsA(_code('SESSION_LOGIN_REQUIRED')),
      );
      expect(h.refreshCount, 1);
    },
  );

  for (final retryAfter in ['120', 'date']) {
    test(
      'refresh 429 honors $retryAfter Retry-After across restart and then allows renewal',
      () async {
        // HTTP-date uses the transport's wall clock; repository clock is aligned.
        h.now = DateTime.now().toUtc();
        h.store.session = _stored(
          'old',
          h.now.subtract(const Duration(days: 2)),
        );
        final repository = h.repository();
        await repository.restore();
        h.refreshHandler = (request) async {
          request.response.headers.set(
            HttpHeaders.retryAfterHeader,
            retryAfter == 'date'
                ? HttpDate.format(h.now.add(const Duration(seconds: 120)))
                : retryAfter,
          );
          await _error(request, 429, 'RATE_LIMITED');
        };
        await expectLater(
          repository.validSession('old'),
          throwsA(
            isA<AuthException>().having((e) => e.retryAt, 'retryAt', isNotNull),
          ),
        );
        expect(h.store.session!.renewalPending, isFalse);
        expect(h.store.session!.retryAt!.isAfter(h.now), isTrue);
        final restarted = h.repository(
          client: GatewayAuthClient(gatewayUrl: h.base),
        );
        await restarted.restore();
        await expectLater(
          restarted.validSession('old'),
          throwsA(
            isA<AuthException>().having((e) => e.statusCode, 'status', 429),
          ),
        );
        expect(h.refreshCount, 1);
        h.now = h.now.add(const Duration(seconds: 121));
        h.refreshHandler = null;
        expect((await restarted.validSession('old')).token, 'new');
        expect(h.refreshCount, 2);
      },
    );
  }

  test(
    'valid legacy bearer upgrades once; subsequent calls and restart use refresh session',
    () async {
      h.store.session = const StoredAuthSession(
        token: 'legacy',
        walletAddress: 'wallet',
        userId: 'user',
        role: 'user',
        authMethod: 'web',
      );
      final repository = h.repository();
      await repository.restore();
      await Future.wait(
        List.generate(5, (_) => repository.validSession('legacy')),
      );
      expect(h.upgradeCount, 1);
      expect(h.upgradeBearers, ['Bearer legacy']);
      expect(h.refreshCount, 0);
      final restarted = h.repository();
      await restarted.restore();
      await restarted.validSession('new');
      expect(h.upgradeCount, 1);
      expect(h.store.session!.authMethod, 'web');
    },
  );

  test(
    'manual legacy import adopts the gateway user identity on upgrade',
    () async {
      h.store.session = const StoredAuthSession(
        token: 'legacy',
        walletAddress: 'imported',
        userId: 'imported',
        role: 'user',
        authMethod: 'manual_paste',
      );
      final repository = h.repository();
      await repository.restore();
      final session = await repository.validSession('legacy');
      expect(session.userId, 'user');
      expect(session.refreshToken, 'refresh-new');
      expect(h.upgradeCount, 1);
    },
  );

  for (final status in [401, 409]) {
    test(
      'legacy $status requires one login, retains auth and never loops upgrade',
      () async {
        h.store.session = const StoredAuthSession(
          token: 'legacy',
          walletAddress: 'wallet',
          userId: 'user',
          role: 'user',
          authMethod: 'email',
        );
        h.upgradeHandler = (request) => _error(
          request,
          status,
          status == 409
              ? 'SESSION_ALREADY_REFRESHABLE'
              : 'ACCESS_TOKEN_EXPIRED',
        );
        final repository = h.repository();
        await repository.restore();
        await expectLater(
          repository.validSession('legacy'),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          repository.validSession('legacy'),
          throwsA(_code('SESSION_LOGIN_REQUIRED')),
        );
        expect(h.upgradeCount, 1);
        expect(repository.current, isNotNull);
        expect(h.store.clearCount, 0);
      },
    );
  }

  test(
    'logout during refresh revokes replacement and late refresh cannot restore account',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final started = Completer<void>();
      final release = Completer<void>();
      h.refreshHandler = (request) async {
        started.complete();
        await release.future;
        await _reply(request, _payload('new', h.now));
      };
      final repository = h.repository();
      await repository.restore();
      final request = repository.validSession('old');
      final rejected = expectLater(request, throwsA(_code('SESSION_CHANGED')));
      await started.future;
      final logout = repository.logout();
      expect(repository.current, isNull);
      release.complete();
      await rejected;
      expect(await logout, isTrue);
      expect(h.revoked, ['refresh-new']);
      expect(h.store.session, isNull);
      expect(repository.current, isNull);
    },
  );

  test(
    'account switch during refresh serializes revocation and rejects old/provider results',
    () async {
      h.store.session = _stored('old', h.now.subtract(const Duration(days: 2)));
      final started = Completer<void>();
      final release = Completer<AuthSession>();
      final repository = h.repository(
        refresh: (_) {
          started.complete();
          return release.future;
        },
      );
      await repository.restore();
      final oldGeneration = repository.generation;
      final renewal = repository.validSession('old');
      final rejected = expectLater(renewal, throwsA(_code('SESSION_CHANGED')));
      await started.future;
      final switchAccount = repository.install(
        AuthSession.fromJson(
          _payload('second', h.now)..['user_id'] = 'second-user',
        ),
        method: 'google',
        expectedGeneration: oldGeneration,
      );
      release.complete(AuthSession.fromJson(_payload('new', h.now)));
      await rejected;
      await switchAccount;
      expect(h.revoked, ['refresh-new']);
      expect(repository.current!.userId, 'second-user');
      await expectLater(
        repository.validSession('old'),
        throwsA(_code('SESSION_CHANGED')),
      );
      await expectLater(
        repository.install(
          AuthSession.fromJson(_payload('late', h.now)),
          method: 'email',
          expectedGeneration: oldGeneration,
        ),
        throwsA(_code('SESSION_CHANGED')),
      );
      expect(h.store.session!.token, 'second');
    },
  );

  test(
    'logout during a login storage write cannot publish the late account',
    () async {
      final repository = h.repository();
      final started = Completer<void>();
      final release = Completer<void>();
      h.store.beforeSave = (value) async {
        if (value.token == 'late-login') {
          started.complete();
          await release.future;
        }
      };
      final login = repository.install(
        AuthSession.fromJson(_payload('late-login', h.now)),
        method: 'email',
        expectedGeneration: repository.generation,
      );
      final rejected = expectLater(login, throwsA(_code('SESSION_CHANGED')));
      await started.future;
      final logout = repository.logout();
      release.complete();
      await rejected;
      expect(await logout, isTrue);
      expect(repository.current, isNull);
      expect(h.store.session, isNull);
      expect(h.revoked, ['refresh-late-login']);
    },
  );

  test('late protected response is discarded after logout', () async {
    h.store.session = _stored('old', h.now);
    final repository = h.repository();
    await repository.restore();
    final started = Completer<void>();
    final release = Completer<void>();
    h.protectedHandler = (request) async {
      started.complete();
      await release.future;
      await _reply(request, {'id': 'old-user'});
    };
    final request = h.client.fetchProfile('old');
    final rejected = expectLater(request, throwsA(_code('SESSION_CHANGED')));
    await started.future;
    await repository.logout();
    release.complete();
    await rejected;
  });

  test(
    'explicit offline logout clears persisted auth and reports revocation unconfirmed',
    () async {
      h.store.session = _stored('old', h.now);
      final repository = h.repository(
        revoke: (_) async => throw AuthException('offline'),
      );
      await repository.restore();
      expect(await repository.logout(), isFalse);
      expect(repository.current, isNull);
      expect(h.store.session, isNull);
    },
  );

  test(
    'background isolates coordinate rotation and use only the committed credential',
    () async {
      final store = _FileFixtureStore(
        '${h.directory.path}/session-fixture.json',
      );
      await store.save(_stored('old', h.now.subtract(const Duration(days: 2))));
      SessionMutex.initialize();
      final resultPort = ReceivePort();
      final messages = <dynamic>[];
      final completed = Completer<void>();
      final subscription = resultPort.listen((message) {
        messages.add(message);
        if (messages.length == 2) completed.complete();
      });
      for (var i = 0; i < 2; i++) {
        await Isolate.spawn(_backgroundRequest, [
          h.base,
          h.directory.path,
          resultPort.sendPort,
          h.now.millisecondsSinceEpoch,
        ]);
      }
      await completed.future.timeout(const Duration(seconds: 10));
      await subscription.cancel();
      resultPort.close();
      expect(messages, ['new', 'new']);
      expect(h.refreshCount, 1);
      expect((await store.read())!.refreshToken, 'refresh-new');
    },
  );
}

Matcher _code(String code) =>
    isA<AuthException>().having((error) => error.code, 'code', code);

Map<String, dynamic> _payload(String token, DateTime now) => {
  'access_token': token,
  'token': token,
  'token_type': 'Bearer',
  'expires_in': 86400,
  'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
  'refresh_token': 'refresh-$token',
  'refresh_expires_in': 2592000,
  'refresh_expires_at': now.add(const Duration(days: 30)).toIso8601String(),
  'session_id': 'session-1',
  'user_id': 'user',
  'role': 'user',
};

StoredAuthSession _stored(String token, DateTime now) =>
    StoredAuthSession.fromSession(
      AuthSession.fromJson(_payload(token, now)),
      authMethod: 'email',
      generation: 'account-1',
      walletAddress: 'wallet',
    );

Future<void> _reply(
  HttpRequest request,
  Object payload, {
  int status = 200,
}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  if (status != 204) request.response.write(jsonEncode(payload));
  await request.response.close();
}

Future<void> _error(HttpRequest request, int status, String code) =>
    _reply(request, {
      'error': {'code': code, 'message': 'Gateway fixture failure'},
    }, status: status);

typedef _Handler = Future<void> Function(HttpRequest);

class _Harness {
  _Harness(this.server, this.directory);
  final HttpServer server;
  final Directory directory;
  final _MemoryStore store = _MemoryStore();
  DateTime now = _epoch;
  int refreshCount = 0;
  int upgradeCount = 0;
  final refreshBodies = <dynamic>[];
  final refreshBearers = <String?>[];
  final upgradeBearers = <String?>[];
  final protectedTokens = <String?>[];
  final revoked = <String>[];
  _Handler? handler;
  _Handler? refreshHandler;
  _Handler? upgradeHandler;
  _Handler? protectedHandler;
  String get base => 'http://${server.address.host}:${server.port}';
  late final GatewayAuthClient client = GatewayAuthClient(gatewayUrl: base);
  SessionMutex get mutex => SessionMutex(lockDirectory: directory.path);

  static Future<_Harness> create() async {
    final h = _Harness(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      await Directory.systemTemp.createTemp('erebrus-auth-test-'),
    );
    h.server.listen((request) => unawaited(h._handle(request)));
    return h;
  }

  AuthSessionRepository repository({
    GatewayAuthClient? client,
    Future<AuthSession> Function(String)? refresh,
    Future<void> Function(String)? revoke,
  }) {
    final api = client ?? this.client;
    final repository = AuthSessionRepository(
      store: store,
      mutex: mutex,
      now: () => now,
      refresh: refresh ?? api.refreshSession,
      upgrade: api.upgradeSession,
      revoke: revoke ?? api.revokeSession,
    );
    api.sessionRepository = repository;
    return repository;
  }

  WalletAuthController controller() => WalletAuthController(
    authClient: client,
    store: store,
    sessionMutex: mutex,
    now: () => now,
  );
  Future<void> close() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (handler != null) return handler!(request);
    if (request.uri.path.endsWith('/auth/refresh')) {
      refreshCount++;
      refreshBodies.add(jsonDecode(await utf8.decodeStream(request)));
      refreshBearers.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      if (refreshHandler != null) return refreshHandler!(request);
      return _reply(request, _payload('new', now));
    }
    if (request.uri.path.endsWith('/auth/session')) {
      upgradeCount++;
      upgradeBearers.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      if (upgradeHandler != null) return upgradeHandler!(request);
      return _reply(request, _payload('new', now));
    }
    if (request.uri.path.endsWith('/auth/logout')) {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      revoked.add(body['refresh_token'] as String);
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      return _reply(request, {}, status: 204);
    }
    protectedTokens.add(request.headers.value(HttpHeaders.authorizationHeader));
    if (store.session?.token == 'new' && !store.session!.renewalPending) {
      store.publishedBeforeProtected = true;
    }
    if (protectedHandler != null) return protectedHandler!(request);
    return _reply(
      request,
      request.uri.path.endsWith('/profile')
          ? {'id': 'user'}
          : {'entitled': true, 'status': 'active'},
    );
  }
}

class _MemoryStore extends AuthSessionStore {
  StoredAuthSession? session;
  int clearCount = 0;
  bool publishedBeforeProtected = false;
  bool failReplacement = false;
  Future<void> Function(StoredAuthSession)? beforeSave;
  @override
  Future<StoredAuthSession?> read() async => session;
  @override
  Future<void> save(StoredAuthSession value) async {
    await beforeSave?.call(value);
    if (failReplacement && value.token == 'new') {
      throw StateError('fixture storage failure');
    }
    session = value;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    session = null;
  }
}

// Test-only file store contains synthetic credentials, allowing real isolates
// to exercise the production mutex and repository without platform channels.
class _FileFixtureStore extends AuthSessionStore {
  _FileFixtureStore(this.path);
  final String path;
  @override
  Future<StoredAuthSession?> read() async => StoredAuthSession.fromJson(
    jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
  );
  @override
  Future<void> save(StoredAuthSession value) =>
      File(path).writeAsString(jsonEncode(value.toJson()), flush: true);
}

Future<void> _backgroundRequest(List<dynamic> args) async {
  final port = args[2] as SendPort;
  try {
    final client = GatewayAuthClient(gatewayUrl: args[0] as String);
    final repo = AuthSessionRepository(
      store: _FileFixtureStore('${args[1]}/session-fixture.json'),
      mutex: SessionMutex(lockDirectory: args[1] as String),
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(args[3] as int, isUtc: true),
      refresh: client.refreshSession,
      upgrade: client.upgradeSession,
      revoke: client.revokeSession,
    );
    await repo.restore();
    final result = await repo.validSession(repo.current!.token);
    port.send(result.token);
  } catch (error) {
    port.send('failed: $error');
  }
}
