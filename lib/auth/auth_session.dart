/// Gateway credentials are opaque (including PASETO access tokens). Expiry is
/// taken exclusively from gateway metadata, never from decoding a token.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.role,
    required this.walletAddress,
    this.tokenType = 'Bearer',
    this.refreshToken,
    this.expiresIn,
    this.expiresAt,
    this.refreshExpiresIn,
    this.refreshExpiresAt,
    this.sessionId,
  });

  final String token;
  final String userId;
  final String role;
  final String walletAddress;
  final String tokenType;
  final String? refreshToken;
  final int? expiresIn;
  final DateTime? expiresAt;
  final int? refreshExpiresIn;
  final DateTime? refreshExpiresAt;
  final String? sessionId;

  factory AuthSession.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final received = (now ?? DateTime.now()).toUtc();
    final access = (json['access_token'] ?? json['token'] ?? '').toString();
    if (access.isEmpty) throw const FormatException('Missing access token');
    final expiresIn = _seconds(json['expires_in']);
    final refreshExpiresIn = _seconds(json['refresh_expires_in']);
    return AuthSession(
      token: access,
      userId: (json['user_id'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      walletAddress:
          (json['wallet_address'] ?? json['wallet'] ?? json['public_key'] ?? '')
              .toString(),
      tokenType: (json['token_type'] ?? 'Bearer').toString(),
      refreshToken: json['refresh_token']?.toString(),
      expiresIn: expiresIn,
      expiresAt:
          _expiry(json['expires_at']) ??
          (expiresIn == null
              ? null
              : received.add(Duration(seconds: expiresIn))),
      refreshExpiresIn: refreshExpiresIn,
      refreshExpiresAt:
          _expiry(json['refresh_expires_at']) ??
          (refreshExpiresIn == null
              ? null
              : received.add(Duration(seconds: refreshExpiresIn))),
      sessionId: json['session_id']?.toString(),
    );
  }

  bool get isRefreshable => refreshToken?.isNotEmpty == true;
  bool needsRefresh(DateTime now) =>
      expiresAt == null ||
      !expiresAt!.isAfter(now.add(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
    'access_token': token,
    'user_id': userId,
    'role': role,
    'wallet_address': walletAddress,
    'token_type': tokenType,
    'refresh_token': refreshToken,
    'expires_in': expiresIn,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'refresh_expires_in': refreshExpiresIn,
    'refresh_expires_at': refreshExpiresAt?.toUtc().toIso8601String(),
    'session_id': sessionId,
  };

  static int? _seconds(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static DateTime? _expiry(dynamic value) {
    if (value == null) return null;
    final epoch = value is num ? value : num.tryParse('$value');
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        (epoch * 1000).round(),
        isUtc: true,
      );
    }
    return DateTime.tryParse('$value')?.toUtc();
  }
}
