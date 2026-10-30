import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../platform/secure_storage.dart';
import 'auth_session.dart';

/// One Keychain/Keystore item is the commit boundary for a complete session.
/// All access must be serialized by AuthSessionRepository, including migration.
class AuthSessionStore {
  AuthSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? ErebrusSecureStorage.sessions,
      _legacyStorage = storage ?? ErebrusSecureStorage.instance;

  final FlutterSecureStorage _storage;
  final FlutterSecureStorage _legacyStorage;
  static const kSession = 'erebrus_ai_session_v2';
  static const kToken = 'erebrus_ai_gateway_token';
  static const kWallet = 'erebrus_ai_wallet_address';
  static const kUserId = 'erebrus_ai_user_id';
  static const kRole = 'erebrus_ai_user_role';
  static const kAuthMethod = 'erebrus_ai_auth_method';
  static const kMwaToken = 'erebrus_ai_mwa_auth_token';

  Future<StoredAuthSession?> read() async {
    _requireNative();
    // Storage unavailability (e.g. a locked Keychain) must never erase auth.
    final encoded = await _storage.read(key: kSession);
    if (encoded != null) {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final session = json['session'];
      return session == null
          ? null
          : StoredAuthSession.fromJson(
              Map<String, dynamic>.from(session as Map),
            );
    }
    final token = await _legacyStorage.read(key: kToken);
    if (token == null || token.isEmpty) return null;
    final legacy = StoredAuthSession(
      token: token,
      walletAddress: await _legacyStorage.read(key: kWallet) ?? '',
      userId: await _legacyStorage.read(key: kUserId) ?? '',
      role: await _legacyStorage.read(key: kRole) ?? 'user',
      authMethod: await _legacyStorage.read(key: kAuthMethod) ?? 'reown',
      mwaAuthToken: await _legacyStorage.read(key: kMwaToken),
      generation: const Uuid().v4(),
    );
    await save(legacy);
    await _removeLegacy();
    return legacy;
  }

  Future<void> save(StoredAuthSession session) async {
    _requireNative();
    await _storage.write(
      key: kSession,
      value: jsonEncode({'version': 2, 'session': session.toJson()}),
    );
    await _flush();
  }

  /// Retained for existing integrations; modern callers use [save].
  Future<void> write({
    required String token,
    required String walletAddress,
    required String userId,
    required String role,
    required String authMethod,
    String? mwaAuthToken,
  }) => save(
    StoredAuthSession(
      token: token,
      walletAddress: walletAddress,
      userId: userId,
      role: role,
      authMethod: authMethod,
      mwaAuthToken: mwaAuthToken,
    ),
  );

  Future<void> clear() async {
    _requireNative();
    // A tombstone prevents a partial legacy cleanup from resurrecting a login.
    await _storage.write(
      key: kSession,
      value: jsonEncode({'version': 2, 'session': null}),
    );
    await _flush();
    await _removeLegacy();
  }

  Future<void> _flush() async {
    // flutter_secure_storage 10.3.1 encrypts with Keystore-backed keys but
    // Android uses apply(), which completes before disk persistence. This
    // native barrier commits the plugin's ciphertext; no secret crosses it.
    if (!kIsWeb && Platform.isAndroid) {
      await const MethodChannel(
        'com.erebrus.ai/auth_storage',
      ).invokeMethod<void>('flush');
    }
  }

  Future<void> _removeLegacy() async {
    for (final key in [
      kToken,
      kWallet,
      kUserId,
      kRole,
      kAuthMethod,
      kMwaToken,
    ]) {
      try {
        await _legacyStorage.delete(key: key);
      } catch (_) {
        // The v2 item/tombstone is already committed and takes precedence.
      }
    }
  }

  void _requireNative() {
    if (kIsWeb) {
      throw UnsupportedError(
        'Browser authentication requires a server-side session',
      );
    }
  }
}

class StoredAuthSession extends AuthSession {
  const StoredAuthSession({
    required super.token,
    required super.walletAddress,
    required super.userId,
    required super.role,
    required this.authMethod,
    this.mwaAuthToken,
    super.tokenType,
    super.refreshToken,
    super.expiresIn,
    super.expiresAt,
    super.refreshExpiresIn,
    super.refreshExpiresAt,
    super.sessionId,
    this.generation = 'legacy',
    this.renewalPending = false,
    this.loginRequired = false,
    this.retryAt,
  });

  final String authMethod;
  final String? mwaAuthToken;
  final String generation;
  // Written BEFORE sending a single-use credential. Survives process death,
  // lost HTTP responses, and a failed replacement write. Never replay it.
  final bool renewalPending;
  final bool loginRequired;
  final DateTime? retryAt;

  factory StoredAuthSession.fromJson(Map<String, dynamic> json) =>
      StoredAuthSession.fromSession(
        AuthSession.fromJson(json),
        authMethod: json['auth_method'] as String? ?? 'reown',
        mwaAuthToken: json['mwa_auth_token'] as String?,
        generation: json['generation'] as String? ?? 'legacy',
        renewalPending: json['renewal_pending'] == true,
        loginRequired: json['login_required'] == true,
        retryAt: DateTime.tryParse('${json['retry_at']}')?.toUtc(),
      );

  factory StoredAuthSession.fromSession(
    AuthSession session, {
    required String authMethod,
    required String generation,
    String? mwaAuthToken,
    bool renewalPending = false,
    bool loginRequired = false,
    DateTime? retryAt,
    String? walletAddress,
  }) => StoredAuthSession(
    token: session.token,
    walletAddress: walletAddress ?? session.walletAddress,
    userId: session.userId,
    role: session.role,
    authMethod: authMethod,
    mwaAuthToken: mwaAuthToken,
    tokenType: session.tokenType,
    refreshToken: session.refreshToken,
    expiresIn: session.expiresIn,
    expiresAt: session.expiresAt,
    refreshExpiresIn: session.refreshExpiresIn,
    refreshExpiresAt: session.refreshExpiresAt,
    sessionId: session.sessionId,
    generation: generation,
    renewalPending: renewalPending,
    loginRequired: loginRequired,
    retryAt: retryAt,
  );

  StoredAuthSession withRenewal({
    bool pending = false,
    bool requiresLogin = false,
    DateTime? retryAt,
  }) => StoredAuthSession.fromSession(
    this,
    authMethod: authMethod,
    mwaAuthToken: mwaAuthToken,
    generation: generation,
    renewalPending: pending,
    loginRequired: requiresLogin,
    retryAt: retryAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'auth_method': authMethod,
    'mwa_auth_token': mwaAuthToken,
    'generation': generation,
    'renewal_pending': renewalPending,
    'login_required': loginRequired,
    'retry_at': retryAt?.toUtc().toIso8601String(),
  };
}
