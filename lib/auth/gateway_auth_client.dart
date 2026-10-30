import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_config.dart';
import 'auth_exception.dart';
import 'auth_session.dart';
import 'auth_session_repository.dart';

export 'auth_exception.dart';
export 'auth_session.dart';
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
  AuthSessionRepository? sessionRepository;
  final Map<String, DateTime> _throttles = {};

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
    return AuthSession.fromJson({...map, 'wallet_address': publicKey});
  }

  /// `GET /api/v2/subscriptions` — requires bearer token.
  Future<void> validateImportedAccess(String token) async {
    await requestJson(
      'GET',
      Uri.parse('$_base/api/v2/subscriptions'),
      bearerToken: token,
      intercept: false,
    );
  }

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

  /// `POST /api/v2/orgs`.
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

  /// `POST /api/v2/referrals/redeem` — apply a referral / invite code after
  /// signup. Binds the caller's referrer (one per account, ever); once the
  /// caller has an active org membership, XP is awarded to both parties on the
  /// gateway. Returns the updated referral summary. Requires a bearer token.
  Future<ReferralSummary> redeemReferralCode({
    required String code,
    required String bearerToken,
  }) async {
    final map = await _postJson(Uri.parse('$_base/api/v2/referrals/redeem'), {
      'code': code.trim().toUpperCase(),
    }, bearerToken: bearerToken);
    return ReferralSummary.fromJson(map);
  }

  /// `GET /api/v2/referrals/me` — the caller's referral code, referrer, and
  /// recent referees.
  Future<ReferralSummary> fetchReferralSummary(String bearerToken) async {
    final map = await _getJson(
      Uri.parse('$_base/api/v2/referrals/me'),
      bearerToken: bearerToken,
    );
    return ReferralSummary.fromJson(Map<String, dynamic>.from(map as Map));
  }

  /// `GET /api/v2/rank/me` — the caller's XP standing. Lifetime XP is
  /// `xp_earned`; the account profile does not carry XP.
  Future<RankStanding> fetchRank(String bearerToken) async {
    final map = await _getJson(
      Uri.parse('$_base/api/v2/rank/me'),
      bearerToken: bearerToken,
    );
    return RankStanding.fromJson(Map<String, dynamic>.from(map as Map));
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
    final map =
        await _postJson(Uri.parse('$_base/api/v2/auth/email/login/verify'), {
          'email': email.trim().toLowerCase(),
          'code': code.replaceAll(RegExp(r'\D'), ''),
        });
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

  AuthSession _identitySession(Map<String, dynamic> map) =>
      AuthSession.fromJson(map);

  Future<AuthSession> refreshSession(String refreshToken) async =>
      AuthSession.fromJson(
        await _postJson(Uri.parse('$_base/api/v2/auth/refresh'), {
          'refresh_token': refreshToken,
        }, intercept: false),
      );

  Future<AuthSession> upgradeSession(String accessToken) async =>
      AuthSession.fromJson(
        await _postJson(
          Uri.parse('$_base/api/v2/auth/session'),
          const {},
          bearerToken: accessToken,
          intercept: false,
        ),
      );

  Future<void> revokeSession(String refreshToken) async {
    await _postJson(Uri.parse('$_base/api/v2/auth/logout'), {
      'refresh_token': refreshToken,
    }, intercept: false);
  }

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

  /// Platform label the gateway records in account activity and metrics.
  static String get clientLabel {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'desktop';
  }

  static const _connectTimeout = Duration(seconds: 15);
  static const _responseTimeout = Duration(seconds: 30);

  Future<dynamic> _getJson(Uri uri, {String? bearerToken}) =>
      requestJson('GET', uri, bearerToken: bearerToken);

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
    bool intercept = true,
  }) async => Map<String, dynamic>.from(
    await requestJson(
          'POST',
          uri,
          body: body,
          bearerToken: bearerToken,
          intercept: intercept,
        )
        as Map,
  );

  /// Shared transport for account, entitlement, referral and org endpoints.
  /// The encoded body and caller's headers (including idempotency keys) are
  /// captured once and reused verbatim for the single access-expiry retry.
  Future<dynamic> requestJson(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? bearerToken,
    Map<String, String> headers = const {},
    bool intercept = true,
  }) async {
    final encoded = body == null ? null : jsonEncode(body);
    final repository = sessionRepository;
    final excluded = const {
      '/api/v2/auth/refresh',
      '/api/v2/auth/logout',
      '/api/v2/auth/session',
    }.contains(uri.path);
    if (!intercept ||
        excluded ||
        repository == null ||
        bearerToken?.isNotEmpty != true) {
      return _rawRequest(method, uri, encoded, bearerToken, headers);
    }
    var session = await repository.validSession(bearerToken!);
    try {
      dynamic result;
      try {
        result = await _rawRequest(
          method,
          uri,
          encoded,
          session.token,
          headers,
        );
      } on AuthException catch (error) {
        if (error.statusCode != 401 || error.code != 'ACCESS_TOKEN_EXPIRED') {
          rethrow;
        }
        session = await repository.renewRejected(session);
        result = await _rawRequest(
          method,
          uri,
          encoded,
          session.token,
          headers,
        );
      }
      await repository.assertCurrent(session);
      return result;
    } on AuthException catch (error) {
      await repository.handleFailure(session, error);
      rethrow;
    }
  }

  Future<dynamic> _rawRequest(
    String method,
    Uri uri,
    String? body,
    String? bearerToken,
    Map<String, String> headers,
  ) async {
    final throttleKey = '$method $uri';
    final retryAt = _throttles[throttleKey];
    if (retryAt?.isAfter(DateTime.now()) == true) {
      throw AuthException(
        'The gateway asked us to wait before trying again.',
        statusCode: 429,
        retryAt: retryAt,
      );
    }
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    var submitted = false;
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_connectTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Erebrus-Client', clientLabel);
      headers.forEach(request.headers.set);
      if (bearerToken?.isNotEmpty == true) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        submitted = true;
        request.add(bytes);
      }
      submitted = true;
      final response = await request.close().timeout(_responseTimeout);
      final text = await utf8.decodeStream(response).timeout(_responseTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final deadline = _retryAt(
          response.headers.value(HttpHeaders.retryAfterHeader),
        );
        if (deadline != null) _throttles[throttleKey] = deadline;
        throw _apiError(response.statusCode, text, deadline);
      }
      return text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } on AuthException {
      rethrow;
    } on SocketException {
      throw AuthException(
        'Cannot reach the gateway. Check your connection.',
        requestMayHaveBeenSent: submitted,
      );
    } on TimeoutException {
      throw AuthException(
        'The gateway took too long to respond.',
        requestMayHaveBeenSent: submitted,
      );
    } on HandshakeException {
      throw AuthException(
        'Secure connection to the gateway failed.',
        requestMayHaveBeenSent: submitted,
      );
    } on HttpException {
      throw AuthException(
        'Gateway connection failed.',
        requestMayHaveBeenSent: submitted,
      );
    } on FormatException {
      throw AuthException('The gateway returned an unexpected response.');
    } finally {
      client.close(force: true);
    }
  }

  static DateTime? _retryAt(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return DateTime.now().toUtc().add(
        Duration(seconds: seconds < 0 ? 0 : seconds),
      );
    }
    try {
      return HttpDate.parse(value).toUtc();
    } catch (_) {
      return null;
    }
  }

  static AuthException _apiError(int status, String body, DateTime? retryAt) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final raw = json['error'];
        final message = raw is Map
            ? raw['message'] ?? json['message'] ?? json['detail']
            : json['message'] ?? json['detail'] ?? raw;
        final code = raw is Map
            ? raw['code'] ?? json['code'] ?? json['error_code']
            : json['code'] ?? json['error_code'] ?? raw;
        return AuthException(
          message?.toString() ?? 'Gateway error ($status)',
          statusCode: status,
          code: code?.toString(),
          retryAt: retryAt,
        );
      }
    } catch (_) {}
    return AuthException(
      'Gateway error ($status)',
      statusCode: status,
      retryAt: retryAt,
    );
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

/// The caller's referral standing (`GET /api/v2/referrals/me` and the response
/// of `POST /api/v2/referrals/redeem`). XP is not part of this payload — read
/// lifetime XP from [RankStanding.xpEarned] instead.
class ReferralSummary {
  const ReferralSummary({
    this.code = '',
    this.referredCount = 0,
    this.referralBound = false,
    this.referredBy,
    this.recent = const [],
  });

  /// The caller's own shareable referral code.
  final String code;

  /// How many users this caller has referred.
  final int referredCount;

  /// True once a referrer has been bound to this account (one-shot, immutable).
  final bool referralBound;

  /// Truncated wallet of whoever referred the caller, when bound.
  final String? referredBy;

  /// Most recent referees (wallets truncated by the gateway).
  final List<ReferralReferee> recent;

  factory ReferralSummary.fromJson(Map<String, dynamic> j) {
    final recentRaw = j['recent'];
    return ReferralSummary(
      code: (j['code'] ?? '').toString(),
      referredCount: j['referred_count'] is int
          ? j['referred_count'] as int
          : 0,
      referralBound: j['referral_bound'] == true,
      referredBy: (j['referred_by'] as String?)?.trim().isNotEmpty == true
          ? j['referred_by'] as String
          : null,
      recent: recentRaw is List
          ? recentRaw
                .whereType<Map>()
                .map(
                  (e) => ReferralReferee.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
    );
  }
}

/// One recent referee inside a [ReferralSummary].
class ReferralReferee {
  const ReferralReferee({
    this.wallet = '',
    this.qualified = false,
    this.joinedAt,
  });

  final String wallet;
  final bool qualified;
  final DateTime? joinedAt;

  factory ReferralReferee.fromJson(Map<String, dynamic> j) => ReferralReferee(
    wallet: (j['wallet'] ?? '').toString(),
    qualified: j['qualified'] == true,
    joinedAt: DateTime.tryParse((j['joined_at'] ?? '').toString())?.toUtc(),
  );
}

/// The caller's XP standing (`GET /api/v2/rank/me`). Lifetime XP is [xpEarned].
class RankStanding {
  const RankStanding({
    this.xpEarned = 0,
    this.xpClaimed = 0,
    this.xpClaimable = 0,
    this.tier = 0,
    this.tierName,
    this.nextTierAt,
  });

  final int xpEarned;
  final int xpClaimed;
  final int xpClaimable;
  final int tier;
  final String? tierName;
  final int? nextTierAt;

  static const zero = RankStanding();

  factory RankStanding.fromJson(Map<String, dynamic> j) => RankStanding(
    xpEarned: _asInt(j['xp_earned']),
    xpClaimed: _asInt(j['xp_claimed']),
    xpClaimable: _asInt(j['xp_claimable']),
    tier: _asInt(j['tier']),
    tierName: j['tier_name']?.toString(),
    nextTierAt: j['next_tier_at'] == null ? null : _asInt(j['next_tier_at']),
  );

  static int _asInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
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
