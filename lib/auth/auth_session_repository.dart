import 'package:uuid/uuid.dart';

import 'auth_exception.dart';
import 'auth_session.dart';
import 'auth_session_store.dart';
import 'session_mutex.dart';

/// The only owner of native gateway credentials. Every operation re-reads the
/// committed record under a cross-isolate/process lock. Waiting requests share
/// the committed replacement, never a second use of a refresh credential.
class AuthSessionRepository {
  AuthSessionRepository({
    required this.store,
    required this.refresh,
    required this.upgrade,
    required this.revoke,
    SessionMutex? mutex,
    DateTime Function()? now,
  }) : _mutex = mutex ?? SessionMutex(),
       _now = now ?? DateTime.now;

  final AuthSessionStore store;
  final SessionMutex _mutex;
  final DateTime Function() _now;
  final Future<AuthSession> Function(String) refresh;
  final Future<AuthSession> Function(String) upgrade;
  final Future<void> Function(String) revoke;
  void Function(StoredAuthSession?)? onChanged;
  void Function(AuthException reason)? onTerminated;
  StoredAuthSession? current;
  final Map<String, String> _tokenGenerations = {};
  final Map<String, Future<StoredAuthSession>> _flights = {};
  bool? _cancelledRevocationConfirmed;
  int _generation = 0;
  int get generation => _generation;

  void _publish(StoredAuthSession? value) {
    if (value?.generation != current?.generation) _tokenGenerations.clear();
    current = value;
    if (value != null) _tokenGenerations[value.token] = value.generation;
    onChanged?.call(value);
  }

  Future<void> restore() {
    final operation = _generation;
    return _mutex.synchronized(() async {
      final stored = await store.read();
      if (operation == _generation) {
        if (stored?.generation != current?.generation) ++_generation;
        _publish(stored);
      }
    });
  }

  Future<void> install(
    AuthSession session, {
    required String method,
    String? mwaToken,
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != _generation) throw _changed();
    // Immediately invalidate older in-flight UI/provider operations.
    final operation = ++_generation;
    await _mutex.synchronized(() async {
      if (operation != _generation) throw _changed();
      final previous = await store.read();
      if (previous != null) {
        // Account switching follows the same serialized revocation as logout.
        await store.clear();
        _publish(null);
        await _tryRevoke(previous);
      }
      if (operation != _generation) throw _changed();
      final stored = StoredAuthSession.fromSession(
        session,
        authMethod: method,
        mwaAuthToken: mwaToken,
        generation: const Uuid().v4(),
      );
      await store.save(stored);
      if (operation != _generation) {
        await store.clear();
        _cancelledRevocationConfirmed = await _tryRevoke(stored);
        throw _changed();
      }
      _publish(stored);
    });
  }

  /// Capture the account before sending a request. A token from a retired
  /// account cannot cause a request to be sent as the newly signed-in account.
  Future<StoredAuthSession> validSession(String suppliedToken) {
    final expected = _tokenGenerations[suppliedToken] ?? current?.generation;
    final operation = _generation;
    return _share(
      'valid:$operation:$suppliedToken',
      () => _mutex.synchronized(() async {
        if (operation != _generation) throw _changed();
        final session = await store.read();
        if (operation != _generation) throw _changed();
        if (session == null ||
            (expected != null && session.generation != expected)) {
          throw _changed();
        }
        if (suppliedToken != session.token &&
            _tokenGenerations[suppliedToken] != session.generation) {
          throw _changed();
        }
        _publish(session);
        return _renewLocked(session, operation: operation);
      }),
    );
  }

  Future<StoredAuthSession> renewRejected(StoredAuthSession rejected) {
    final operation = _generation;
    return _share(
      'rejected:$operation:${rejected.token}',
      () => _mutex.synchronized(() async {
        if (operation != _generation) throw _changed();
        final session = await store.read();
        if (operation != _generation) throw _changed();
        if (session == null || session.generation != rejected.generation) {
          throw _changed();
        }
        _publish(session);
        // A concurrent request already replaced the rejected access token.
        if (session.token != rejected.token) return session;
        return _renewLocked(session, force: true, operation: operation);
      }),
    );
  }

  Future<StoredAuthSession> _share(
    String key,
    Future<StoredAuthSession> Function() action,
  ) {
    final active = _flights[key];
    if (active != null) return active;
    late final Future<StoredAuthSession> future;
    future = action().whenComplete(() {
      if (identical(_flights[key], future)) _flights.remove(key);
    });
    _flights[key] = future;
    return future;
  }

  Future<StoredAuthSession> _renewLocked(
    StoredAuthSession session, {
    bool force = false,
    required int operation,
  }) async {
    if (session.loginRequired || session.renewalPending) {
      throw AuthException(
        'Sign in again to renew this session safely.',
        code: 'SESSION_LOGIN_REQUIRED',
      );
    }
    if (session.retryAt?.isAfter(_now()) == true) {
      throw AuthException(
        'The gateway asked us to wait before trying again.',
        statusCode: 429,
        retryAt: session.retryAt,
      );
    }
    if (session.isRefreshable && !force && !session.needsRefresh(_now())) {
      return session;
    }

    // Also journals legacy upgrades: a lost upgrade response may already have
    // converted the bearer to a refreshable session we cannot recover.
    await store.save(session.withRenewal(pending: true));
    if (operation != _generation) throw _changed();
    try {
      final replacement = session.isRefreshable
          ? await refresh(session.refreshToken!)
          : await upgrade(session.token);
      if (!replacement.isRefreshable ||
          replacement.expiresAt == null ||
          replacement.refreshExpiresAt == null ||
          replacement.sessionId?.isNotEmpty != true ||
          (session.sessionId != null &&
              session.sessionId != replacement.sessionId) ||
          (session.userId.isNotEmpty &&
              session.userId != 'imported' &&
              replacement.userId != session.userId)) {
        throw const FormatException(
          'Incomplete or mismatched session replacement',
        );
      }
      final stored = StoredAuthSession.fromSession(
        replacement,
        authMethod: session.authMethod,
        mwaAuthToken: session.mwaAuthToken,
        generation: session.generation,
        walletAddress: replacement.walletAddress.isEmpty
            ? session.walletAddress
            : null,
      );
      // Logout/account switching waits for this lock. If it arrived during
      // HTTP, revoke the replacement instead of publishing the retired account.
      if (operation == _generation) await store.save(stored);
      if (operation != _generation) {
        await store.clear();
        _cancelledRevocationConfirmed = await _tryRevoke(stored);
        throw _changed();
      }
      _publish(stored);
      return stored;
    } on AuthException catch (error) {
      if (error.code == 'SESSION_CHANGED') rethrow;
      if (error.terminatesSession) {
        await store.clear();
        if (operation == _generation) {
          _publish(null);
          onTerminated?.call(error);
        }
      } else if (error.statusCode == 429) {
        // An explicit throttle response did not accept the credential. Do not
        // sleep/retry here; persist the server's deadline across app restarts.
        final retryAt =
            error.retryAt ?? _now().add(const Duration(seconds: 60));
        final retained = session.withRenewal(retryAt: retryAt);
        await store.save(retained);
        if (operation == _generation) _publish(retained);
      } else if (!error.requestMayHaveBeenSent ||
          (error.statusCode != null && error.statusCode! < 500)) {
        final retained = session.withRenewal(
          requiresLogin:
              !session.isRefreshable &&
              (error.statusCode == 401 ||
                  error.code == 'SESSION_ALREADY_REFRESHABLE'),
        );
        await store.save(retained);
        if (operation == _generation) _publish(retained);
      } else if (operation == _generation) {
        _publish(session.withRenewal(pending: true));
      }
      // Network/timeout/5xx/malformed-success/write failures leave the durable
      // pending marker intact. Replaying after an uncertain result is unsafe.
      rethrow;
    } catch (_) {
      if (operation == _generation) {
        _publish(session.withRenewal(pending: true));
      }
      rethrow;
    }
  }

  Future<void> assertCurrent(StoredAuthSession requestSession) =>
      _mutex.synchronized(() async {
        final stored = await store.read();
        if (stored == null ||
            stored.generation != requestSession.generation ||
            current?.generation != requestSession.generation) {
          throw _changed();
        }
      });

  Future<void> handleFailure(
    StoredAuthSession session,
    AuthException error,
  ) async {
    if (!error.terminatesSession) return;
    await _mutex.synchronized(() async {
      final stored = await store.read();
      if (stored?.generation != session.generation) return;
      await store.clear();
      _publish(null);
      onTerminated?.call(error);
    });
  }

  /// Local auth disappears immediately; storage clearing and remote revocation
  /// serialize behind any refresh. False explicitly means revocation unconfirmed.
  Future<bool> logout() {
    ++_generation;
    _publish(null);
    return _mutex.synchronized(() async {
      final stored = await store.read();
      await store.clear();
      final confirmed =
          (stored == null || await _tryRevoke(stored)) &&
          (_cancelledRevocationConfirmed ?? true);
      _cancelledRevocationConfirmed = null;
      return confirmed;
    });
  }

  Future<bool> _tryRevoke(StoredAuthSession session) async {
    if (!session.isRefreshable) return false;
    try {
      await revoke(session.refreshToken!);
      return true;
    } on AuthException catch (error) {
      return error.code == 'SESSION_REVOKED' ||
          error.code == 'REFRESH_TOKEN_REUSED';
    } catch (_) {
      return false;
    }
  }

  AuthException _changed() =>
      AuthException('The signed-in account changed.', code: 'SESSION_CHANGED');
}
