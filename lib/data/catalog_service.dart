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
      debugPrint('[Catalog] failed to fetch $url: $e; catalog unavailable');
      _entries = [];
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
