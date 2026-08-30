// Config: project-root `.env` (bundled into the app) or `--dart-define-from-file`.

/// Reown (WalletConnect) project id — Android / iOS wallet login.
const kReownProjectId = String.fromEnvironment('REOWN_PROJECT_ID');

/// True when [kReownProjectId] was passed via `--dart-define` / `.env`.
bool get hasReownProjectId => kReownProjectId.isNotEmpty;

/// Google Sign-In **server** (web) client id — its audience must be listed in the
/// gateway's `GOOGLE_CLIENT_IDS`. Client ids are public identifiers (never the
/// secret), so the production one is baked in; override via `--dart-define` for
/// a different Google Cloud project. Empty => Google sign-in is hidden (no
/// native call, no error).
const kGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '743089346496-15iub9ug9b4jkqonokg2js80ndjv8nba.apps.googleusercontent.com',
);
bool get hasGoogleSignIn => kGoogleServerClientId.isNotEmpty;

/// Apple Sign-In Services id + redirect, needed only for the web/Android relay
/// flow; on iOS/macOS native Apple sign-in uses the app's capability instead.
/// Absent (and not on Apple platforms) => Apple sign-in is hidden.
const kAppleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
const kAppleRedirectUri = String.fromEnvironment(
  'APPLE_REDIRECT_URI',
  defaultValue: 'https://gateway.erebrus.io/api/v2/auth/apple/callback',
);

/// Erebrus webapp origin (`EREBRUS_WEB_ORIGIN` in `.env` / `--dart-define`).
/// Wallet logo + MWA identity derive `{origin}/ai/logo.png` from this value.
const kErebrusWebOrigin = String.fromEnvironment(
  'EREBRUS_WEB_ORIGIN',
  defaultValue: 'https://erebrus.io',
);

/// Production origin used when [kErebrusWebOrigin] points at localhost — wallets
/// must fetch `…/ai/logo.png` over public HTTPS, not loopback.
const kErebrusProductionOrigin = 'https://erebrus.io';

/// Webapp route that performs wallet auth and redirects with a PASETO token.
const kErebrusDesktopAuthPath = '/auth';

/// Deep link the webapp redirects to after auth (`erebrusai://auth?token=…`).
const kErebrusAuthCallbackScheme = 'erebrusai';
const kErebrusAuthCallbackHost = 'auth';
const kErebrusAuthCallback = 'erebrusai://auth';

/// Gateway chain identifier for Solana wallet login.
const kSolanaChain = 'sol';

/// AI app path on the erebrus site (`/ai/logo.png`, `/ai/`, …).
const kErebrusAiBasePath = '/ai';
const kErebrusAiLogoFile = 'logo.png';
const kErebrusAiLogoPath = '$kErebrusAiBasePath/$kErebrusAiLogoFile';

String _erebrusOriginBase(String webOrigin) =>
    webOrigin.replaceAll(RegExp(r'/+$'), '');

/// Trailing-slash site URL for WalletConnect / Reown metadata (`url` field).
String erebrusSiteUrlFromOrigin(String webOrigin) =>
    '${_erebrusOriginBase(webOrigin)}/';

/// Absolute HTTPS icon for Reown / WalletConnect pairing metadata.
String erebrusSiteIconFromOrigin(String webOrigin) =>
    '${_erebrusOriginBase(webOrigin)}$kErebrusAiLogoPath';

/// MWA identity URI — the `/ai/` base so the icon can be a simple filename
/// (`logo.png`), matching the pattern wallets expect.
String erebrusMwaIdentityUrlFromOrigin(String webOrigin) =>
    '${_erebrusOriginBase(webOrigin)}$kErebrusAiBasePath/';

/// Mobile Wallet Adapter icon filename relative to [erebrusMwaIdentityUrlFromOrigin].
const kErebrusMwaIconRelative = kErebrusAiLogoFile;

/// Native deep link — wallets return here after connect/sign (`erebrusai://…`).
const kErebrusNativeRedirect = 'erebrusai://';

/// Universal link placeholder for Reown metadata (host assetlinks when ready).
const kErebrusUniversalRedirect = 'https://erebrus.io/ai';

/// Shown when Reown init runs without a project id in the build environment.
const kReownProjectIdMissingMessage =
    'REOWN_PROJECT_ID is not set. Add it to .env in the project root '
    '(cp env.example .env), then rebuild the app.';

/// macOS / iOS bundle id — sent to the webapp as `client_id`.
const kErebrusBundleId = 'com.erebrus.ai';

/// Linux APPLICATION_ID.
const kErebrusLinuxApplicationId = 'com.erebrus.erebrus_ai';

/// Removes every query parameter and fragment before an authentication URL is
/// written to logs. Parameter allowlists are intentionally avoided because new
/// OAuth providers may introduce sensitive fields under unexpected names.
String redactedAuthUrlForLog(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.isEmpty) return '[unparseable-auth-url]';
  if (uri.hasAuthority) return '${uri.scheme}://${uri.authority}${uri.path}';
  return '${uri.scheme}:${uri.path}';
}

String reownOriginNotAllowedMessage(String relayOrigin) =>
    'Reown relay rejected this app (origin not allowed). In cloud.reown.com → '
    'your project → Allowlist, add: $relayOrigin and https://erebrus.io — then '
    'wait ~15 minutes and restart the app.';
