# Platform status

Implementation status across the active codebase. “Implemented” means the code
path exists and is covered where practical by automated tests; it does not mean
that every platform has completed release signing or physical-device certification.

---

## UI & navigation

| Feature | Status | Notes |
|---|---|---|
| Chat screen | Implemented | Streaming tokens, thought block collapse, backend switching, and multi-session persistence. |
| Model browser (Local / Network tabs) | Implemented | Catalog-driven GGUF & MLX downloads, imported model inspector, and mDNS LAN peer discovery. |
| Persona editor | Implemented | System prompt customization, inference parameters (temperature, top-p, penalties), preset & custom personas. |
| Settings | Implemented | Local server lifecycle & API keys, storage directories, model memory budget, telemetry consent, and auth state. |
| Sign-in | Integrated | WalletAuthController (Reown, Solana MWA, Web) and social OAuth routing. |
| Responsive shell | Implemented | Adaptive navigation: bottom navigation on mobile, compact rail on medium windows, expanded sidebar on desktop. |
| Audio transcription | Implemented | On-device SpeechAnalyzer on iOS/macOS 26+ and cross-platform `whisper.cpp` fallback with session history. |

---

## Auth & org

| Feature | Status | Notes |
|---|---|---|
| Wallet auth (Reown / MWA / web) | Integrated | Erebrus account layer adapted for AI. |
| Social sign-in (Google / Apple) | Needs configuration | Wrappers are present; each release needs registered OAuth IDs and redirect URLs. |
| Session persistence | Implemented | Encrypted with `flutter_secure_storage` (`ErebrusSecureStorage`). |
| Deep link `erebrusai://auth` | Implemented | Schemes registered across iOS / macOS / Android with sensitive token redaction in logs. |
| Desktop web login | Implemented | Browser opens erebrus.io, callback parsed. |
| Org / workspace models | Partial | `OrgClient` + `OrgState` wired to UI; syncs with gateway org endpoint. |
| Pending org invites | Partial | UI displays and manages invites from `WalletAuthController`. |

---

## Local inference & networking

| Feature | Status | Notes |
|---|---|---|
| Multi-backend coordinator | Implemented | `InferenceCoordinator` orchestrates MLX, TurboQuant, and `llama.cpp` runtimes with fallback. |
| Model downloader | Implemented | `ModelDownloadService` & `ModelPackageService` with SHA-256 validation, resume, and rollback. |
| OpenAI-compatible API | Implemented | `LocalServerService` exposes authenticated `POST /v1/chat/completions`, `GET /v1/models`, and public `GET /health` with rate limiting. |
| mDNS LAN discovery (`_erebrusai._tcp`) | Implemented | Desktop & mobile nodes advertise capabilities and browse peers on the local network. |
| Desktop tray / background | Implemented | AI menu-bar/system-tray icon with window controls and background persistence. |
| Android foreground service | Implemented | `ForegroundTaskCoordinator` is wired; sustained physical-device validation remains pending. |
| Speech transcription engine | Implemented | `WhisperCppBackend` & Apple `SpeechAnalyzer` plugin with local audio saving and timecodes. |

---

## Platform matrix

| Platform | UI | Auth | Local server | Network node | Release validation |
|---|---|---|---|---|---|
| macOS | Implemented | Config required | Implemented | Implemented | Signing/notarization pending |
| Windows | Implemented | Config required | Implemented | Implemented | Release bundle validation pending |
| Linux | Implemented | Config required | Implemented | Implemented | Release bundle validation pending |
| Android | Implemented | Config required | Implemented | Implemented | Physical-device and production-signing validation pending |
| iOS | Implemented | Config required | Implemented | Implemented | Physical-device and TestFlight validation pending |

---

## Roadmap & future work

1. Production Android signing and automated iOS App Store / TestFlight signing.
2. Cross-platform release-bundle and physical-device certification.
3. GPU acceleration flags (`-ngl`, CUDA / Metal / Vulkan) fine-tuning per architecture.
4. RAG / document ingestion and semantic search.
5. Cloud model proxy for hybrid local/cloud inference.
6. Org model sharing and per-model access control policies.
