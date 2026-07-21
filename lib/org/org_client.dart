import 'dart:convert';
import 'dart:io';

import '../auth/runtime_config.dart';
import 'ai_org.dart';
import 'shared_model.dart';

/// Thin HTTP client for Erebrus AI organization endpoints.
class OrgClient {
  OrgClient({String? gatewayUrl})
    : _base = _normalizeBase(gatewayUrl ?? RuntimeConfig.gatewayUrl);

  final String _base;

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
    await _postJson(
      Uri.parse('$_base/api/v2/organizations/$orgId/personas'),
      {'persona_id': personaId},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/organizations/{id}/invites` — invite a user by email/wallet.
  Future<void> inviteMember({
    required String orgId,
    required String recipient,
    required String role,
    required String bearerToken,
  }) async {
    await _postJson(
      Uri.parse('$_base/api/v2/organizations/$orgId/invites'),
      {'recipient': recipient, 'role': role},
      bearerToken: bearerToken,
    );
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
        throw OrgException(_errorMessage(res.statusCode, text));
      }
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw OrgException('Cannot reach gateway ($_base): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> _postJson(
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
        throw OrgException(_errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw OrgException('Cannot reach gateway ($_base): ${e.message}');
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
    if (trimmed.isEmpty) return 'https://gateway.erebrus.io';
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return withScheme.replaceAll(RegExp(r'/+$'), '');
  }
}

class OrgException implements Exception {
  OrgException(this.message);
  final String message;

  @override
  String toString() => message;
}
