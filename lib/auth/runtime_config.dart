import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'auth_config.dart';

/// Loads secrets from the project-root `.env` bundled as an app asset.
/// Compile-time `--dart-define` still wins when set.
class RuntimeConfig {
  RuntimeConfig._();

  static final _values = <String, String>{};

  static String get reownProjectId =>
      _firstNonEmpty([kReownProjectId, _values['REOWN_PROJECT_ID']]);

  static bool get hasReownProjectId => reownProjectId.isNotEmpty;

  static String get gatewayUrl => _firstNonEmpty([_values['GATEWAY_URL'], '']);

  /// Single authoritative base for the Erebrus model catalog.
  static String get modelCatalogBaseUrl =>
      _firstNonEmpty([_values['MODEL_CATALOG_BASE_URL'], 'https://erebrus.io']);

  static String get modelsCatalogUrl {
    final base = modelCatalogBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/ai/models.json';
  }

  /// Erebrus webapp origin for desktop browser sign-in (`.env` may use localhost).
  static String get erebrusWebOrigin =>
      _firstNonEmpty([_values['EREBRUS_WEB_ORIGIN'], kErebrusWebOrigin]);

  /// Origin for Reown / MWA pairing metadata and `{origin}/ai/logo.png`.
  /// Localhost [erebrusWebOrigin] is ignored — wallets cannot reach loopback.
  static String get erebrusWalletOrigin {
    final origin = erebrusWebOrigin;
    if (_isUnreachableWalletOrigin(origin)) {
      return kErebrusProductionOrigin;
    }
    return origin;
  }

  /// WalletConnect / Reown metadata `url`.
  static String get erebrusSiteUrl =>
      erebrusSiteUrlFromOrigin(erebrusWalletOrigin);

  /// Absolute HTTPS icon for Reown / WalletConnect pairing metadata.
  static String get erebrusSiteIcon =>
      erebrusSiteIconFromOrigin(erebrusWalletOrigin);

  /// MWA authorize identity URI (`{origin}/ai/` + relative `logo.png`).
  static String get erebrusMwaIdentityUrl =>
      erebrusMwaIdentityUrlFromOrigin(erebrusWalletOrigin);

  /// Google server (web) client id for native Google sign-in.
  static String get googleServerClientId => _firstNonEmpty([
    _values['GOOGLE_SERVER_CLIENT_ID'],
    kGoogleServerClientId,
  ]);

  static bool get hasGoogleSignIn => googleServerClientId.isNotEmpty;

  /// Apple Services id for web/Android relay flow.
  static String get appleServiceId =>
      _firstNonEmpty([kAppleServiceId, _values['APPLE_SERVICE_ID']]);

  /// Apple redirect URI for the web relay.
  static String get appleRedirectUri =>
      _firstNonEmpty([_values['APPLE_REDIRECT_URI'], kAppleRedirectUri]);

  static bool _isUnreachableWalletOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return true;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host.endsWith('.local') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('172.');
  }

  static Future<void> load() async {
    if (kReownProjectId.isNotEmpty) {
      debugPrint('[Config] REOWN_PROJECT_ID from --dart-define');
    }
    await _loadDotEnvAsset('.env');
    final reown = _values['REOWN_PROJECT_ID'];
    if (reown != null && reown.isNotEmpty) {
      debugPrint('[Config] REOWN_PROJECT_ID loaded from bundled env');
    } else if (kReownProjectId.isEmpty) {
      debugPrint('[Config] REOWN_PROJECT_ID missing — add to .env and rebuild');
    }
  }

  static Future<void> _loadDotEnvAsset(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      _values.addAll(_parseDotEnv(raw));
    } catch (e) {
      debugPrint('[Config] could not load asset $path: $e');
    }
  }

  static Map<String, String> _parseDotEnv(String content) {
    final out = <String, String>{};
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final i = t.indexOf('=');
      if (i <= 0) continue;
      final key = t.substring(0, i).trim();
      var value = t.substring(i + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final v = c?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
}
