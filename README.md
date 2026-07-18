# Erebrus AI

**Run AI models locally and chat with them from any device on your network.**

Erebrus AI is a cross-platform local LLM runner. Download quantized GGUF models,
chat on-device, create custom personas, and expose an OpenAI-compatible API to
your LAN so phones and other computers can discover your desktop as a private
AI node.

- **Private by default** — inference runs on your hardware.
- **Wallet or social sign-in** — one Erebrus account across the ecosystem.
- **Desktop always-on node** — macOS, Windows, Linux can serve models in the
  background.
- **Mobile companion** — iOS and Android discover nodes and run small models
  while open.
- **Team workspaces** — join an organization to access shared models.

---

## Supported platforms

| Platform | Role | Where to get it |
| --- | --- | --- |
| **macOS** | Desktop server + client | Build from source — [docs/BUILD.md](docs/BUILD.md) |
| **Windows** | Desktop server + client | Build from source — [docs/BUILD.md](docs/BUILD.md) |
| **Linux** | Desktop server + client | Build from source — [docs/BUILD.md](docs/BUILD.md) |
| **Android** | Client + optional server | GitHub Releases (APK) / sideload |
| **iOS** | Client + in-app server | TestFlight / App Store (see [docs/BUILD.md](docs/BUILD.md)) |
| **Web** | Not supported | Browsers cannot run local LLMs in MVP |

---

## Quickstart

```bash
flutter pub get
flutter analyze      # No issues found!
flutter test         # All tests passed!
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

---

## Project layout

```
lib/
├── auth/        # Wallet/social sign-in, session, gateway, deep links
├── org/         # Organization / workspace client and state
├── platform/    # Secure storage and platform detection
├── screens/     # Chat, models, personas, settings, sign-in, shell
└── state/       # AppState wiring auth + org to the UI
```

---

## CI / Releases

- **CI:** Every PR/push to `main` runs `flutter analyze` and `flutter test`.
  See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- **Releases:** Trigger manually in GitHub Actions or push a `v*` tag.
  See [`.github/workflows/release.yml`](.github/workflows/release.yml).

---

Questions? [Open an issue](https://github.com/NetSepio/erebrus-ai/issues).
