# Authentication & Organizations

This doc covers how Erebrus AI signs users in and how organization / workspace
models are shared. It is meant for developers integrating or debugging auth.

---

## Supported sign-in methods

The app picks the right path at runtime based on `PlatformCapabilities`:

| Platform | Primary method | Notes |
|----------|----------------|-------|
| Solana Mobile (Seeker / Saga) | Mobile Wallet Adapter (MWA) | Native wallet selector, signed challenge. |
| Desktop (macOS / Windows / Linux) | Web login (`erebrusai://auth`) | Browser opens erebrus.io; PASETO returns via deep link. |
| Other mobile | Reown AppKit modal | Solana or EVM wallet modal. |
| All platforms | Social (Google / Apple) | Used when the gateway advertises those methods. |

---

## Environment variables

Copy `env.example` to `.env` and set the values before running:

```bash
cp env.example .env
```

| Variable | Required for | Description |
|----------|--------------|-------------|
| `REOWN_PROJECT_ID` | Reown modal | Your Reown / WalletConnect project id. |
| `EREBRUS_WEB_ORIGIN` | Desktop web login | Allowed origin for web auth (e.g. `https://erebrus.io`). |
| `GOOGLE_SERVER_CLIENT_ID` | Google sign-in | Server-side OAuth client id. |
| `APPLE_SERVICE_ID` | Apple sign-in | Apple service identifier. |
| `APPLE_REDIRECT_URI` | Apple sign-in | Apple redirect URI. |
| `GATEWAY_URL` | Gateway client | Erebrus gateway base URL. Defaults to `https://gateway.erebrus.io`. |

`.env` is bundled as a Flutter asset and parsed by `RuntimeConfig` at startup.
For CI or release builds you can also pass these as `--dart-define` values.
OAuth client IDs and redirect URLs are public configuration identifiers, not
client secrets. The repository contains production defaults where applicable;
explicit `.env` values override them for development and alternate deployments.

---

## Deep links

- **Scheme:** `erebrusai`
- **Host:** `auth`
- **iOS / macOS:** registered in `CFBundleURLTypes`.
- **Android:** registered as a `VIEW` intent filter for `erebrusai://auth`.

`DeepLinkHandler` receives the URL and either:

1. routes it to `WalletAuthController.handleWebAuthCallback()` for desktop web
   auth, or
2. dispatches it to `ReownAppKitModal.dispatchEnvelope()` for mobile Reown
   callbacks.

### Desktop web login flow

1. `DesktopWebAuth.buildLoginUrl()` creates a URL with a random `state`.
2. `url_launcher` opens the URL in the system browser.
3. User authenticates on `erebrus.io`.
4. Browser redirects to `erebrusai://auth?token=...&state=...`.
5. `DeepLinkHandler` parses and validates the state.
6. `WalletAuthController` persists the session.

---

## Session persistence

`AuthSessionStore` uses `flutter_secure_storage`:

- `erebrus_ai_gateway_token`
- `erebrus_ai_wallet_address`
- `erebrus_ai_user_id`
- `erebrus_ai_user_role`
- `erebrus_ai_auth_method`
- `erebrus_ai_mwa_auth_token`

The token is read at startup in `WalletAuthController.initialize()`.

---

## Organizations

`OrgState` fetches the user's organizations from the gateway and, for the
selected organization, lists shared models.

- `OrgClient.fetchOrganizations(token)` — list orgs the user belongs to.
- `OrgClient.fetchOrgModels(token, orgId)` — list models shared in the org.
- `OrgClient.inviteMember(...)` — invite a wallet/email to an org.
- `OrgClient.sharePersona(token, orgId, personaId)` — share a persona.

The UI surfaces org data in:

- `SettingsScreen` — account card, org card, pending invites.
- `ModelsScreen` — signed-in users see an org node card with shared models.
- `PersonaEditor` — share toggle shows the selected org name.

---

## Gateway API v2

`GatewayAuthClient` covers:

- `fetchFlowId(walletAddress, chain)` — start wallet login.
- `authenticate(...)` — complete login with signature.
- `fetchSubscription(token)` — entitlement status.
- `fetchProfile(token)` — user profile.
- `fetchAccountOrgInvites(token)` — pending org invites.
- `createOrganization(...)` — create a new org.

Base URL is configured by `GATEWAY_URL` (default `https://gateway.erebrus.io`).

---

## Testing auth in widget tests

Real wallet / social plugins cannot run under `flutter test`. The smoke tests in
`test/screens_smoke_test.dart` inject auth/org controllers and toggle
`AppState.signedIn` directly to verify the signed-in UI surfaces.
