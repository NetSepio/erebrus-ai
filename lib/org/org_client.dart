import '../auth/runtime_config.dart';
import '../auth/gateway_auth_client.dart';
import '../auth/auth_session_repository.dart';
import 'ai_org.dart';
import 'shared_model.dart';

/// Thin HTTP client for Erebrus AI organization endpoints.
class OrgClient {
  OrgClient({String? gatewayUrl})
    : _base = _normalizeBase(gatewayUrl ?? RuntimeConfig.gatewayUrl);

  final String _base;
  final GatewayAuthClient _transport = GatewayAuthClient();
  set sessionRepository(AuthSessionRepository value) =>
      _transport.sessionRepository = value;

  /// `GET /api/v2/orgs` — requires bearer token.
  Future<List<AiOrg>> fetchOrganizations(String bearerToken) async {
    final decoded = await _getJson(
      Uri.parse('$_base/api/v2/orgs'),
      bearerToken: bearerToken,
    );
    final list = decoded is List
        ? decoded
        : (decoded is Map
                  ? ((decoded['orgs'] ?? decoded['organizations']) as List?)
                  : null) ??
              const [];
    return list
        .map((e) => AiOrg.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((o) => o.id.isNotEmpty)
        .toList();
  }

  /// `GET /api/v2/organizations/{id}/models` — shared/private models in this org.
  Future<List<SharedModel>> fetchOrgModels(
    String orgId,
    String bearerToken,
  ) async {
    final decoded = await _getJson(
      Uri.parse('$_base/api/v2/organizations/$orgId/models'),
      bearerToken: bearerToken,
    );
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['models'] as List?) : null) ?? const [];
    return list
        .map((e) => SharedModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  /// `POST /api/v2/organizations/{id}/personas` — share a persona to the workspace.
  Future<void> sharePersona({
    required String orgId,
    required String personaId,
    required String bearerToken,
  }) async {
    await _postJson(Uri.parse('$_base/api/v2/organizations/$orgId/personas'), {
      'persona_id': personaId,
    }, bearerToken: bearerToken);
  }

  /// `POST /api/v2/organizations/{id}/invites` — invite a user by email/wallet.
  Future<void> inviteMember({
    required String orgId,
    required String recipient,
    required String role,
    required String bearerToken,
  }) async {
    await _postJson(Uri.parse('$_base/api/v2/organizations/$orgId/invites'), {
      'recipient': recipient,
      'role': role,
    }, bearerToken: bearerToken);
  }

  Future<dynamic> _getJson(Uri uri, {String? bearerToken}) =>
      _request('GET', uri, bearerToken: bearerToken);

  Future<dynamic> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) => _request('POST', uri, body: body, bearerToken: bearerToken);

  Future<dynamic> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    try {
      return await _transport.requestJson(
        method,
        uri,
        body: body,
        bearerToken: bearerToken,
      );
    } on AuthException catch (error) {
      throw OrgException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
        retryAt: error.retryAt,
      );
    }
  }

  static String _normalizeBase(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'https://gateway.erebrus.io';
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return withScheme.replaceAll(RegExp(r'/+$'), '');
  }
}

class OrgException implements Exception {
  OrgException(this.message, {this.statusCode, this.code, this.retryAt});
  final String message;
  final int? statusCode;
  final String? code;
  final DateTime? retryAt;
  String? get errorCode => code;

  @override
  String toString() => message;
}
