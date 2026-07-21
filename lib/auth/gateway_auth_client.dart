import 'dart:convert';
import 'dart:io';

import 'auth_config.dart';
import 'entitlement_state.dart';
import 'runtime_config.dart';
import 'user_org_invite.dart';
import 'user_profile.dart';

/// Default Erebrus gateway for local / dev testing.
const kDefaultGatewayUrl = 'https://gateway.erebrus.io';

/// Wallet auth + account data against the Erebrus gateway (v2).
class GatewayAuthClient {
  GatewayAuthClient({String? gatewayUrl})
    : _base = _normalizeBase(gatewayUrl ?? RuntimeConfig.gatewayUrl);

  final String _base;

  /// Start wallet login — `GET /api/v2/auth`.
  Future<AuthChallenge> fetchFlowId({
    required String walletAddress,
    String chain = kSolanaChain,
  }) async {
    final uri = Uri.parse('$_base/api/v2/auth').replace(
      queryParameters: {'wallet_address': walletAddress, 'chain': chain},
    );
    final map = await _getJson(uri);
    return AuthChallenge(
      flowId: (map['flow_id'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
    );
  }

  /// Complete wallet login — `POST /api/v2/auth`.
  Future<AuthSession> authenticate({
    required String flowId,
    required String signature,
    required String publicKey,
  }) async {
    final map = await _postJson(Uri.parse('$_base/api/v2/auth'), {
      'flow_id': flowId,
      'signature': signature,
      'public_key': publicKey,
    });
    return AuthSession(
      token: (map['token'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      role: (map['role'] ?? 'user').toString(),
      walletAddress: publicKey,
    );
  }

  /// `GET /api/v2/subscriptions` — requires bearer token.
  Future<EntitlementState> fetchSubscription(String bearerToken) async {
    final map = await _getJson(
      Uri.parse('$_base/api/v2/subscriptions'),
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson(map);
  }

  /// `POST /api/v2/subscriptions/trial` — one-time free trial.
  Future<EntitlementState> startTrial(String bearerToken) async {
    final map = await _postJson(
      Uri.parse('$_base/api/v2/subscriptions/trial'),
      const {},
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson({
      'entitled': true,
      'status': map['status'],
      'plan_id': map['plan_id'],
      'source': map['source'] ?? 'trial',
      'current_period_end': map['current_period_end'],
    });
  }

  /// `GET /api/v2/account/profile`.
  Future<UserProfile> fetchProfile(String bearerToken) async {
    final map = await _getJson(
      Uri.parse('$_base/api/v2/account/profile'),
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `GET /api/v2/account/org-invites`.
  Future<List<UserOrgInvite>> fetchAccountOrgInvites(String bearerToken) async {
    final decoded = await _getJson(
      Uri.parse('$_base/api/v2/account/org-invites'),
      bearerToken: bearerToken,
    );
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['invites'] as List?) : null) ?? const [];
    return list
        .map((e) => UserOrgInvite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// `POST /api/v2/account/org-invites/{id}/accept`.
  Future<void> acceptAccountOrgInvite(
    String inviteId,
    String bearerToken,
  ) async {
    await _postJson(
      Uri.parse('$_base/api/v2/account/org-invites/$inviteId/accept'),
      const {},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/account/org-invites/{id}/decline`.
  Future<void> declineAccountOrgInvite(
    String inviteId,
    String bearerToken,
  ) async {
    await _postJson(
      Uri.parse('$_base/api/v2/account/org-invites/$inviteId/decline'),
      const {},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/organizations`.
  Future<Map<String, dynamic>> createOrg({
    required String name,
    required String slug,
    required String bearerToken,
  }) async {
    return await _postJson(Uri.parse('$_base/api/v2/orgs'), {
      'name': name,
      'slug': slug,
    }, bearerToken: bearerToken);
  }

  Future<void> emailLoginStart(String email) async {
    await _postJson(Uri.parse('$_base/api/v2/auth/email/login/start'), {
      'email': email.trim().toLowerCase(),
      'app': 'Erebrus AI',
    });
  }

  Future<AuthSession> emailLoginVerify({
    required String email,
    required String code,
  }) async {
    final map = await _postJson(
      Uri.parse('$_base/api/v2/auth/email/login/verify'),
      {
        'email': email.trim().toLowerCase(),
        'code': code.replaceAll(RegExp(r'\D'), ''),
      },
    );
    return _identitySession(map);
  }

  Future<AuthSession> googleLogin(String idToken) async {
    final map = await _postJson(Uri.parse('$_base/api/v2/auth/google'), {
      'id_token': idToken,
    });
    return _identitySession(map);
  }

  Future<AuthSession> appleLogin({
    required String idToken,
    required String authorizationCode,
    required String nonce,
    required String state,
  }) async {
    final map = await _postJson(Uri.parse('$_base/api/v2/auth/apple'), {
      'id_token': idToken,
      'authorization_code': authorizationCode,
      'nonce': nonce,
      'state': state,
    });
    return _identitySession(map);
  }

  AuthSession _identitySession(Map<String, dynamic> map) => AuthSession(
    token: (map['token'] ?? '').toString(),
    userId: (map['user_id'] ?? '').toString(),
    role: (map['role'] ?? 'user').toString(),
    walletAddress:
        (map['wallet_address'] ?? map['wallet'] ?? map['public_key'] ?? '')
            .toString(),
  );

  /// `GET /api/v2/auth/methods` — which login methods the gateway has configured.
  Future<AuthMethods> fetchAuthMethods() async {
    try {
      final map = await _getJson(Uri.parse('$_base/api/v2/auth/methods'));
      return AuthMethods(
        email: map['email'] == true,
        google: map['google'] == true,
        apple: map['apple'] == true,
        wallet: map['wallet'] == true,
      );
    } catch (_) {
      return AuthMethods.unknown;
    }
  }

  Future<dynamic> _getJson(Uri uri, {String? bearerToken}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(_errorMessage(res.statusCode, text));
      }
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($_base): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(_errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($_base): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static String _errorMessage(int status, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final msg = j['error'] ?? j['message'] ?? j['detail'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return 'Gateway error ($status)';
  }

  static String _normalizeBase(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return kDefaultGatewayUrl;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return withScheme.replaceAll(RegExp(r'/+$'), '');
  }
}

class AuthChallenge {
  const AuthChallenge({required this.flowId, required this.message});
  final String flowId;
  final String message;
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.role,
    required this.walletAddress,
  });
  final String token;
  final String userId;
  final String role;
  final String walletAddress;
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Which login methods the gateway has configured.
class AuthMethods {
  const AuthMethods({
    required this.email,
    required this.google,
    required this.apple,
    required this.wallet,
  });

  final bool email;
  final bool google;
  final bool apple;
  final bool wallet;

  static const unknown = AuthMethods(
    email: true,
    google: true,
    apple: true,
    wallet: true,
  );
}
