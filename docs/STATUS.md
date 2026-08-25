# Platform status

Current implementation status across all subsystems. Updated regularly to match the active codebase.

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
| Social sign-in (Google / Apple) | Integrated | Wrappers present; configured via platform OAuth IDs. |
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
| Android foreground service | Implemented | `ForegroundTaskCoordinator` keeps inference alive during background tasks. |
| Speech transcription engine | Implemented | `WhisperCppBackend` & Apple `SpeechAnalyzer` plugin with local audio saving and timecodes. |

---

## Platform matrix

| Platform | UI | Auth | Local server | Network node | Priority |
|---|---|---|---|---|---|
| macOS | Ready | Ready | Ready | Ready | Primary |
| Windows | Ready | Ready | Ready | Ready | Primary |
| Linux | Ready | Ready | Ready | Ready | Primary |
| Android | Ready | Ready | Ready | Ready | Primary |
| iOS | Ready | Ready | Ready | Ready | Primary |

---

## Roadmap & future work

1. Automated iOS App Store / TestFlight signing pipeline in CI.
2. GPU acceleration flags (`-ngl`, CUDA / Metal / Vulkan) fine-tuning per architecture.
3. RAG / document ingestion and semantic search.
4. Cloud model proxy for hybrid local/cloud inference.
5. Org model sharing and per-model access control policies.
