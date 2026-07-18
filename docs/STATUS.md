# Platform status

What works today vs what is still in progress. Updated as the MVP evolves.

---

## UI & navigation

| Feature | Status | Notes |
|---|---|---|
| Chat screen | UI ready | Mock data; local inference not wired yet. |
| Model browser (Local / Network tabs) | UI ready | Local models from mock data; network tab merges mock nodes + org models. |
| Persona editor | UI ready | Preset + user personas from mock data. |
| Settings | UI ready | Local server toggles, account/org cards wired to auth/org state. |
| Sign-in | Integrated | WalletAuthController + platform-aware routing in place. |
| Responsive shell | Ready | Bottom nav on mobile, sidebar on desktop. |

---

## Auth & org

| Feature | Status | Notes |
|---|---|---|
| Wallet auth (Reown / MWA / web) | Integrated | Erebrus account layer adapted for AI. |
| Social sign-in (Google / Apple) | Integrated | Wrappers present; requires OAuth config. |
| Session persistence | Ready | `flutter_secure_storage`. |
| Deep link `erebrusai://auth` | Configured | Schemes registered on iOS / macOS / Android. |
| Desktop web login | Ready | Browser opens erebrus.io, callback parsed. |
| Org / workspace models | Partial | `OrgClient` + `OrgState` ready; UI wired, backend endpoint live required. |
| Pending org invites | Partial | UI shows invites from `WalletAuthController`. |

---

## Local inference (pending)

| Feature | Status | Notes |
|---|---|---|
| `llama.cpp` server spawning | Not started | Binary loading + `Process` wrapper. |
| Model download | Not started | Catalog + resumable download. |
| OpenAI-compatible API | Not started | Local server exposes `/v1/models` and `/v1/chat/completions`. |
| mDNS service (`_erebrus-ai._tcp`) | Not started | Desktop publishes, mobile browses. |
| Desktop tray / background | Not started | `window_manager` + `tray_manager`. |
| Android foreground service | Not started | Keep server alive in background. |

---

## Platform matrix

| Platform | UI | Auth | Local server | Network node | Priority |
|---|---|---|---|---|---|
| macOS | Ready | Ready | Pending | Pending | Primary |
| Windows | Ready | Ready | Pending | Pending | Primary |
| Linux | Ready | Ready | Pending | Pending | Primary |
| Android | Ready | Ready | Pending | Pending | Secondary |
| iOS | Ready | Ready | Pending | Pending | Secondary |

---

## Open work

### Ship MVP

1. Local `llama.cpp` server integration on desktop.
2. Model download manager and GGUF catalog.
3. Chat streaming via `POST /v1/chat/completions`.
4. mDNS publish/browse for desktop and mobile nodes.
5. Desktop tray / background mode.
6. CI release builds for macOS, Windows, Linux, Android, iOS.

### Future / optional

1. GPU acceleration flags (`-ngl`, CUDA / Metal / Vulkan).
2. RAG / document ingestion.
3. Cloud model proxy (not local).
4. Fine-tuning and model training capabilities.
5. Org model sharing and per-model access policies.
