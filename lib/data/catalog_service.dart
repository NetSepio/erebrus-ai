import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../auth/runtime_config.dart';
import 'catalog_entry.dart';
import 'model_catalog.dart' show modelCatalog;

/// Fetches and caches the remote model catalog published by Erebrus AI.
///
/// Falls back to the compiled-in [modelCatalog] if the network is unavailable,
/// the response cannot be parsed, or the env URL is empty.
class CatalogService {
  CatalogService._();

  static final _instance = CatalogService._();

  /// In-memory cache of the last successfully parsed catalog.
  List<CatalogEntry> _entries = [];

  /// Whether a fetch attempt has completed at least once.
  bool _loaded = false;

  DateTime? _lastFetch;
  static const _cacheTtl = Duration(minutes: 5);

  /// Returns the cached remote catalog, or the compiled-in fallback if the
  /// remote catalog has not been loaded yet.
  static List<CatalogEntry> get entries =>
      _instance._entries.isNotEmpty ? _instance._entries : modelCatalog;

  /// True once [fetch] has completed (success or failure).
  static bool get loaded => _instance._loaded;

  /// Fetches the catalog from [RuntimeConfig.modelsCatalogUrl] and caches it.
  ///
  /// Returns the cached catalog when it is fresh to avoid duplicate network
  /// calls; otherwise refreshes from the network.
  static Future<List<CatalogEntry>> fetch() => _instance._fetch();

  Future<List<CatalogEntry>> _fetch() async {
    final now = DateTime.now();
    if (_loaded &&
        _entries.isNotEmpty &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < _cacheTtl) {
      return entries;
    }

    final url = RuntimeConfig.modelsCatalogUrl;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
        }
        final text = await response.transform(utf8.decoder).join();
        final decoded = json.decode(text) as Map<String, dynamic>;
        final models = decoded['models'] as List<dynamic>? ?? [];
        _entries = models
            .map((m) => CatalogEntry.fromJson(m as Map<String, dynamic>))
            .where((e) => e.id.isNotEmpty && e.name.isNotEmpty)
            .toList();
        _loaded = true;
        _lastFetch = now;
        debugPrint('[Catalog] loaded ${_entries.length} models from $url');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[Catalog] failed to fetch $url: $e; using fallback catalog');
      _entries = [];
      _loaded = true;
      _lastFetch = now;
    }
    return entries;
  }

  /// Replaces the cached catalog with the compiled-in fallback.
  /// Useful for tests and offline recovery.
  static void useFallback() {
    _instance._entries = [];
    _instance._loaded = true;
    _instance._lastFetch = DateTime.now();
  }

  /// Injects a catalog directly (useful for tests).
  static void setEntries(List<CatalogEntry> entries) {
    _instance._entries = entries;
    _instance._loaded = true;
    _instance._lastFetch = DateTime.now();
  }
}
