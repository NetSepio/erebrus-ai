import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../auth/runtime_config.dart';
import 'catalog_entry.dart';

/// Fetches and caches the remote model catalog published by Erebrus AI.
///
/// The production Erebrus endpoint is authoritative; failures are surfaced to
/// the UI instead of silently replacing it with demo content.
class CatalogService {
  CatalogService._();

  static final _instance = CatalogService._();

  /// In-memory cache of the last successfully parsed catalog.
  List<CatalogEntry> _entries = [];

  /// Whether a fetch attempt has completed at least once.
  bool _loaded = false;
  String? _lastError;

  DateTime? _lastFetch;
  static const _cacheTtl = Duration(minutes: 5);

  static List<CatalogEntry> get entries =>
      List.unmodifiable(_instance._entries);
  static String? get lastError => _instance._lastError;

  /// True once [fetch] has completed (success or failure).
  static bool get loaded => _instance._loaded;

  /// Fetches the catalog from [RuntimeConfig.modelsCatalogUrl] and caches it.
  ///
  /// Returns the cached catalog when it is fresh to avoid duplicate network
  /// calls; otherwise refreshes from the network.
  static Future<List<CatalogEntry>> fetch() => _instance._fetch();

  @visibleForTesting
  static List<CatalogEntry> parsePayload(String text) {
    final decoded = json.decode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Catalog root must be a JSON object');
    }
    final schemaVersion = decoded['schema_version'] as String? ?? '';
    final schemaMajor = int.tryParse(schemaVersion.split('.').first);
    if (schemaMajor != 1) {
      throw FormatException('Unsupported catalog schema: $schemaVersion');
    }
    final models = decoded['models'];
    if (models is! List<dynamic> || models.isEmpty) {
      throw const FormatException('Catalog must contain at least one model');
    }

    final modelIds = <String>{};
    final variantIds = <String>{};
    final parsed = <CatalogEntry>[];
    for (final value in models) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Catalog model must be a JSON object');
      }
      final modelId = value['id'] as String? ?? '';
      if (modelId.isEmpty || !modelIds.add(modelId)) {
        throw FormatException('Invalid or duplicate model id: $modelId');
      }
      final variants = value['variants'];
      if (variants is! List<dynamic> || variants.isEmpty) {
        throw FormatException('$modelId has no runnable variants');
      }
      for (final candidate in variants) {
        if (candidate is! Map<String, dynamic>) {
          throw FormatException('$modelId contains an invalid variant');
        }
        final variantId =
            (candidate['variant_id'] as String?) ??
            (candidate['id'] as String?) ??
            '';
        if (variantId.isEmpty || !variantIds.add(variantId)) {
          throw FormatException('Invalid or duplicate variant id: $variantId');
        }
        final files = candidate['files'];
        if (files is! List<dynamic> || files.isEmpty) {
          throw FormatException('$variantId has no package files');
        }
        for (final item in files) {
          if (item is! Map<String, dynamic>) {
            throw FormatException('$variantId contains an invalid file');
          }
          if (item['required'] == false) continue;
          final revision = item['revision'] as String? ?? '';
          final sha256 = item['sha256'] as String? ?? '';
          final size = item['file_size_bytes'];
          final url = Uri.tryParse(item['download_url'] as String? ?? '');
          if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
              size is! int ||
              size <= 0 ||
              url == null ||
              url.scheme != 'https') {
            throw FormatException(
              '$variantId contains an unverified required file',
            );
          }
        }
      }
      final entry = CatalogEntry.fromJson(value);
      if (entry.name.isEmpty) {
        throw FormatException('$modelId has no display name');
      }
      parsed.add(entry);
    }
    return parsed;
  }

  Future<List<CatalogEntry>> _fetch() async {
    final now = DateTime.now();
    if (_loaded &&
        _entries.isNotEmpty &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < _cacheTtl) {
      return entries;
    }

    final url = RuntimeConfig.modelsCatalogUrl;
    _lastError = null;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(url),
          );
        }
        final text = await response.transform(utf8.decoder).join();
        _entries = parsePayload(text);
        _loaded = true;
        _lastFetch = now;
        debugPrint('[Catalog] loaded ${_entries.length} models from $url');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint(
        '[Catalog] failed to fetch $url: $e; retaining last valid catalog',
      );
      _lastError = e.toString();
      _loaded = true;
      _lastFetch = now;
    }
    return entries;
  }

  /// Clears the remote cache. Useful for tests and offline recovery.
  static void useFallback() {
    _instance._entries = [];
    _instance._loaded = true;
    _instance._lastFetch = DateTime.now();
  }

  /// Injects a catalog directly (useful for tests).
  static void setEntries(List<CatalogEntry> entries) {
    _instance._entries = entries;
    _instance._lastError = null;
    _instance._loaded = true;
    _instance._lastFetch = DateTime.now();
  }
}
