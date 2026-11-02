# Erebrus AI

**Run AI models locally and chat with them from any device on your network.**

Erebrus AI is a cross-platform local LLM runner. Download quantized GGUF models,
chat on-device, create custom personas, and expose an OpenAI-compatible API to
your LAN so phones and other computers can discover your desktop as a private
AI node.

- **Private by default** — inference runs on your hardware.
- **Wallet or social sign-in** — one Erebrus account across the ecosystem.
- **Desktop always-on node** — macOS, Windows, and Linux live in the system
  tray while serving models in the background. Closing the window hides it;
  use the tray icon to reopen or quit the app.
- **Mobile companion** — iOS and Android discover nodes and run small models
  while open.
- **Team workspaces** — join an organization to access shared models.
- **Catalog-driven model browser** — inspect compatible GGUF and MLX packages,
  capabilities, provenance, licenses, and local storage from one screen.
  Recommendations follow the catalog's per-device picks for phones, laptops,
  desktops and gaming rigs, and only offer packages that fit the device.
  Uncensored community builds are labelled, rank after official and
  experimental models, and ask for confirmation before download.

---

## Supported platforms

| Platform | Role | Where to get it |
| --- | --- | --- |
| **macOS** | Desktop server + client | Build from source — [docs/BUILD.md](docs/BUILD.md) |
| **Windows** | Desktop server + client | [GitHub Releases](https://github.com/NetSepio/erebrus-ai/releases) or build from source |
| **Linux** | Desktop server + client | [GitHub Releases](https://github.com/NetSepio/erebrus-ai/releases) (x64) or build from source |
| **Android** | Client + optional server | [GitHub Releases](https://github.com/NetSepio/erebrus-ai/releases) (Play Store + dApp Store builds) |
| **iOS** | Client + in-app server | Build from source; TestFlight signing pending |
| **Web** | Not supported | Browsers cannot run local LLMs in MVP |

---

## Quickstart

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # desktop or connected device
```

Copy `env.example` to `.env` and fill in the variables before using sign-in
flows — see [docs/AUTH.md](docs/AUTH.md).

---

## Docs

| Topic | File |
|-------|------|
| Build, signing, troubleshooting | [docs/BUILD.md](docs/BUILD.md) |
| Architecture & state flow | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Auth, orgs, and environment | [docs/AUTH.md](docs/AUTH.md) |
| Platform status & open work | [docs/STATUS.md](docs/STATUS.md) |
| Release history | [CHANGELOG.md](CHANGELOG.md) |

---

## Project layout

```
lib/
├── auth/        # Wallet/social sign-in, session, gateway, deep links
├── data/        # Model catalog, persona repository, transcription sessions
├── navigation/  # Adaptive responsive navigation shell and routing
├── org/         # Organization / workspace client and state
├── platform/    # Secure storage and platform detection
├── screens/     # Chat, models, personas, settings, sign-in, onboarding
├── services/    # Inference coordinator, backends, download manager, HTTP server, mDNS
├── state/       # AppState wiring auth + org to the UI
├── theme/       # Design system tokens, colors, typography, glassmorphism
└── widgets/     # Reusable glass cards, thought bubbles, controls, status indicators
```

---

## CI / Releases

- **CI** ([`ci.yml`](.github/workflows/ci.yml)) runs on every pull request and
  push to `main`: a gitleaks history scan, `flutter analyze`, the benchmark
  gate, and `flutter test`, then release builds for macOS (arm64 + x86_64,
  unsigned), iOS (unsigned), Windows, Linux, and Android, with checks on the
  packaged llama.cpp, Whisper, and TurboQuant runtimes.
- **Releases** ([`release.yml`](.github/workflows/release.yml)) run when a
  `v*` tag that matches `pubspec.yaml` is pushed (`version: 1.1.1+3` → tag
  `v1.1.1`), and need a `## 1.1.1+3` section in [CHANGELOG.md](CHANGELOG.md).
  The workflow builds signed Play Store (APK + AAB) and dApp Store (APK)
  Android artifacts, verifies each signing certificate, packages Windows and
  Linux, and publishes a GitHub Release with a manifest and SHA-256 checksums.
  A manual run builds the same artifacts without publishing.
- Required secrets, variables, and the macOS signing gate are listed in
  [docs/BUILD.md](docs/BUILD.md#8-ci-and-releases).

---

Questions? [Open an issue](https://github.com/NetSepio/erebrus-ai/issues).
