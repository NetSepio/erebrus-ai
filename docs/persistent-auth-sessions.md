# Native gateway sessions

`WalletAuthController` remains the UI's auth state. `AuthSessionRepository`
owns credentials and rotation; `GatewayAuthClient.requestJson` is the shared
protected transport for account, subscription, referral, and organization APIs.
Existing wallet, email, Google, Apple, and desktop sign-in entry points feed the
same repository. Tokens remain opaque; expiry comes from gateway metadata.

## Storage and concurrency

A single `erebrus_ai_session_v2` secure-storage item commits the complete session,
expiry metadata, app-local generation, wallet adapter state, and renewal journal.
The legacy access-token keys migrate into this record. Logout writes a tombstone
before deleting legacy keys so partial cleanup cannot resurrect a login.

Apple storage uses an app-specific service, no shared access group or iCloud
sync, and `first_unlock_this_device` accessibility. Android uses an app-specific
Keystore-backed namespace with backup/device-transfer exclusions. The Android
`auth_storage/flush` channel commits only the plugin's encrypted backing files;
no credentials enter that channel. This is needed because the installed secure
storage plugin acknowledges asynchronous disk writes. Storage errors propagate
without resetting or deleting a session.

`SessionMutex.initialize()` runs on the main isolate. Its named-port queue
serializes Flutter isolates; an OS lock additionally serializes native lock
holders. The name server outlives engines: when Android recreates the activity
in a process the foreground service kept alive, the new root isolate replaces
the destroyed engine's port instead of queueing on it forever. A repository re-reads secure storage while holding the lock, including
when another isolate has already rotated the token. Background isolates must use
the same repository and initialize `BackgroundIsolateBinaryMessenger` with the
main isolate's `RootIsolateToken` before accessing platform storage. Independent
apps must never import this app's refresh credentials or share its namespace.

## Renewal and recovery

Startup restores local credentials before background account checks. Resume
re-reads the committed record. Every protected request checks access expiry with
a 60-second margin. Concurrent requests share renewal and wait until the entire
replacement is saved. `401 ACCESS_TOKEN_EXPIRED` gets one retry, using an already
rotated token if available. The encoded body and caller headers, including any
idempotency key, are retained. Refresh, logout, and upgrade bypass interception.

Before submitting a single-use refresh token (or legacy upgrade), the repository
persists a pending marker. A lost response, timeout after submission, 5xx,
malformed success, process death, or failed replacement write leaves that marker
intact. Such credentials are never automatically replayed, including after
restart: local auth/data remain, and Settings offers **Sign in again**. A proven
connection failure before submission can be retried later. Explicit 429 responses
persist `Retry-After` (seconds or HTTP-date), with a 60-second fallback. No timer
is needed while the app is suspended.

Only `REFRESH_TOKEN_INVALID`, `REFRESH_TOKEN_REUSED`, `SESSION_REVOKED`, and
`403 ACCOUNT_SUSPENDED` (returned by refresh and upgrade once an admin suspends
the account) clear auth automatically; suspension shows its own message instead
of "session expired". Other authorization/business errors retain account data.
Legacy `/auth/session` upgrades are attempted once when successful; expired
legacy bearers and `409 SESSION_ALREADY_REFRESHABLE` without a refresh token
require another login. Browser callback/import paths carry access credentials
only and never copy another app's refresh token.

Logout/account switching invalidates in-flight UI/provider work immediately and
serializes storage/revocation behind renewal. Cancellation during rotation
revokes the returned replacement rather than publishing the old account.
Explicit logout clears local storage even when remote revocation fails; the UI
reports revocation as unconfirmed. Late protected responses are discarded.

## Platforms and verification

The configured targets are Android, iOS, macOS, Windows, and Linux. There is no
Flutter Web target. Native session storage explicitly rejects Web; adding that
target requires a server-side browser session using secure HTTP-only cookies,
not storing refresh credentials in browser storage.

`auth_session_expiry_test.dart` exercises the real HTTP transport against a
local synthetic gateway, clock-driven expiry, rotation persistence, separate
repositories and background isolates, legacy upgrades, error handling, and
logout/account-switch races. `sign_in_navigation_test.dart` covers provider
completion, retained-session recovery, and actual app lifecycle resume dispatch.
Secure-storage unit tests mock the platform backend; physical Keychain/Keystore
and process-kill behavior still require device smoke testing with test accounts.
