# Architecture

How the Erebrus AI app is put together, from the UI down to the local inference
and auth backend. If you're new to the codebase, read this first.

---

## The big idea: one app, local inference + network inference

Erebrus AI runs quantized GGUF models locally through `llama.cpp` and also lets
mobile or secondary devices use a desktop node over the LAN. The user sees a
single model browser with two tabs:

- **Local** — models downloaded to this device.
- **Network** — models discovered on `_erebrus-ai._tcp` mDNS nodes.

When a user picks a model, the chat layer routes the request to either the local
`llama.cpp` server or the remote node's OpenAI-compatible endpoint.

---

## Data flow

```
┌────────────────────────────────────────────────────────────────┐
│  Flutter UI (chat, model browser, persona editor, settings)   │
│  `AppState` wires `WalletAuthController` + `OrgState`          │
├────────────────────────────────────────────────────────────────┤
│  `lib/services/*` (inference, model manager, discovery)        │
│  `lib/auth/*` + `lib/org/*` (account, orgs, shared models)     │
├────────────────────────────────────────────────────────────────┤
│  Local `llama.cpp` server binary (desktop / mobile)            │
│  GGUF model cache in app documents directory                   │
│  Persona / chat store (SQLite / Hive / shared_preferences)    │
├────────────────────────────────────────────────────────────────┤
│  mDNS service registration / discovery                         │
│  OpenAI-compatible HTTP API on configurable port               │
│  Erebrus gateway v2 (auth, entitlements, org invites)          │
└────────────────────────────────────────────────────────────────┘
```

---

## Dart layers

### `lib/state/app_state.dart`

The UI's single source of truth. It listens to both `WalletAuthController` and
`OrgState` and exposes a flat API:

- `signedIn`, `onboarded`
- `walletAddress`, `userProfile`, `pendingInvites`
- `orgs`, `selectedOrg`, `orgModels`
- local node toggles: `serving`, `serveOnNetwork`, `startAtLogin`
- chat selections: `selectedModel`, `selectedPersona`

### `lib/auth/`

Authentication uses the shared Erebrus account layer and is adapted for the AI context.

- **`wallet_auth_controller.dart`** — the main controller. Picks the right login
  path based on the platform:
  - **Solana Mobile** (Seeker / Saga) → Mobile Wallet Adapter.
  - **Desktop** → browser-based web login (`erebrusai://auth` callback).
  - **Other mobile** → Reown AppKit modal (Solana / EVM wallets).
- **`gateway_auth_client.dart`** — HTTP client for the Erebrus gateway v2 auth,
  subscription, profile, and org invite endpoints.
- **`auth_session_store.dart`** — persists token, wallet, user id, and MWA state
  in `flutter_secure_storage`.
- **`deep_link_handler.dart`** — routes `erebrusai://` callbacks to either the
  desktop web auth flow or the Reown modal envelope handler.
- **`social_login.dart`** — thin wrappers for native Google and Apple sign-in,
  used when the gateway advertises those methods.
- **`desktop_web_auth.dart`** — builds the web login URL, validates the state
  parameter, and parses the `erebrusai://auth?token=...` callback.

### `lib/org/`

Organization support for shared workspace models.

- **`org_state.dart`** — reactive state for orgs and shared models.
- **`org_client.dart`** — HTTP client for org endpoints.
- **`ai_org.dart`** — organization model + role helpers.
- **`shared_model.dart`** — a model shared inside an organization.

### `lib/platform/`

- **`secure_storage.dart`** — `FlutterSecureStorage` singleton with Android
  reset-on-error options.
- **`platform_capabilities.dart`** — runtime flags for web/mobile/desktop and
  Solana Mobile detection.

### `lib/screens/`

- **`chat/`** — chat screen, model picker, persona picker.
- **`models/`** — local/network model browser.
- **`personas/`** — persona list and editor.
- **`settings/`** — local server config, account/org cards, sign-out.
- **`auth/sign_in.dart`** — platform-aware sign-in launcher.
- **`shell.dart`** — responsive shell (bottom nav on mobile, sidebar/tabs on
  desktop).

---

## Authentication flow

```
SignInPage
   │
   ├── Solana Mobile device ──▶ WalletAuthController.signInWithSolanaMobile()
   │                            └── Solana Mobile Wallet Adapter
   │                                └── sign challenge → gateway auth
   │
   ├── Desktop platform ──────▶ WalletAuthController.openWebSignIn()
   │                            └── Browser opens erebrus.io
   │                                └── deep link erebrusai://auth?token=...
   │                                    └── handleWebAuthCallback()
   │
   └── Other mobile ──────────▶ WalletAuthController.openWalletModal()
                                └── Reown AppKit modal
                                    └── wallet signature → gateway auth
```

After a successful gateway auth the controller persists the session, refreshes
entitlements, fetches the user profile, and loads pending org invites.
`OrgState` then fetches the user's organizations and shared models.

---

## Local inference (planned)

The local `llama.cpp` server is spawned as a subprocess by the Dart service
layer (not yet implemented in the current screens pass). It binds to a
configurable port and exposes:

- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/completions`

Desktop publishes `_erebrus-ai._tcp` via mDNS. Mobile browses the same service
type and merges discovered models into the network tab.

---

## Project layout

```
lib/
├── main.dart
├── app.dart
├── auth/
│   ├── wallet_auth_controller.dart
│   ├── gateway_auth_client.dart
│   ├── auth_session_store.dart
│   ├── deep_link_handler.dart
│   ├── desktop_web_auth.dart
│   ├── social_login.dart
│   ├── solana_mobile_wallet.dart
│   ├── user_profile.dart
│   ├── user_org_invite.dart
│   └── runtime_config.dart
├── org/
│   ├── org_state.dart
│   ├── org_client.dart
│   ├── ai_org.dart
│   └── shared_model.dart
├── platform/
│   ├── secure_storage.dart
│   └── platform_capabilities.dart
├── screens/
│   ├── auth/sign_in.dart
│   ├── chat/
│   ├── models/
│   ├── personas/
│   ├── settings/
│   └── shell.dart
├── state/
│   └── app_state.dart
├── theme/
└── data/
```

---

## State management

All state is `ChangeNotifier` based:

- `WalletAuthController` owns auth, entitlements, profile, and invites.
- `OrgState` owns orgs and shared models.
- `AppState` listens to both and exposes the flat fields the UI currently uses.

This matches the existing Erebrus account pattern and avoids pulling in an
external state framework for the auth/org integration.
