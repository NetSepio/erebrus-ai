class AuthException implements Exception {
  AuthException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAt,
    this.requestMayHaveBeenSent = true,
  });
  final String message;
  final int? statusCode;
  final String? code;
  final DateTime? retryAt;

  /// False only when transport proves failure before writing the request.
  final bool requestMayHaveBeenSent;
  String? get errorCode => code;

  /// An admin suspended the account; refresh and session upgrade return 403.
  bool get accountSuspended => code == 'ACCOUNT_SUSPENDED';
  bool get terminatesSession => const {
    'REFRESH_TOKEN_INVALID',
    'REFRESH_TOKEN_REUSED',
    'SESSION_REVOKED',
    'ACCOUNT_SUSPENDED',
  }.contains(code);

  @override
  String toString() => message;
}
