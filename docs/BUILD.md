# Build & run

From a fresh clone to a running app, in order.

---

## 1. Prerequisites

- **Flutter** stable SDK (`flutter doctor` should be green for your target
  platforms). See https://docs.flutter.dev/get-started/install.
- For mobile: Android Studio + SDK, or Xcode + a macOS host for iOS.
- For local inference: a `llama-server` binary for your platform (see below).

---

## 2. Install dependencies

```bash
flutter pub get
```

---

## 3. Configure environment

```bash
cp env.example .env
```

Edit `.env` and set at least:

- `REOWN_PROJECT_ID` — required for mobile wallet modal sign-in.
- `EREBRUS_WEB_ORIGIN` — required for desktop web login.
- `GATEWAY_URL` — defaults to `https://gateway.erebrus.io` if omitted.

For Google/Apple sign-in, also fill in the social OAuth variables.
See [AUTH.md](AUTH.md) for details.

---

## 4. Run UI-only (screens pass)

```bash
flutter analyze      # expect: No issues found!
flutter test         # expect: All tests passed!
flutter run          # desktop target by default on macOS/Windows/Linux
```

At this point the Flutter UI and auth/org integration screens run. **Local
inference** needs the `llama.cpp` server binary (next step).

---

## 5. Local inference binary (`llama-server`)

The app expects a `llama.cpp` server binary per platform. Binaries are not
committed; build or download them once.

| Platform | Expected path | How to obtain |
|----------|---------------|---------------|
| macOS arm64 | `assets/llama-bin/llama-server-darwin-arm64` | `./scripts/build-llama-macos.sh` |
| macOS x64 | `assets/llama-bin/llama-server-darwin-x64` | `./scripts/build-llama-macos.sh --x64` |
| Windows x64 | `assets/llama-bin/llama-server-windows-x64.exe` | `./scripts/build-llama-windows.sh` |
| Linux x64 | `assets/llama-bin/llama-server-linux-x64` | `./scripts/build-llama-linux.sh` |

> These scripts will be added as the inference service is implemented. Until
> then, place a prebuilt binary in the path above and add it to `pubspec.yaml`
> assets.

---

## 6. Platform-specific notes

### macOS

```bash
flutter run -d macos
```

- Sign-in uses **web login** (`erebrusai://auth` callback), not Reown.
- The app registers `erebrusai` as a URL scheme in `macos/Runner/Info.plist`.

### Windows / Linux

```bash
flutter run -d windows
flutter run -d linux
```

- Same web-login path as macOS.
- Linux needs the Flutter toolchain plus the plugins' system libraries
  (Ubuntu/Debian package names, as installed in CI):

  ```bash
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libblkid-dev liblzma-dev \
    libsecret-1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libayatana-appindicator3-dev
  ```

### iOS

```bash
flutter run -d <iphone-device-id>
```

- Reown / WalletConnect and social sign-in require the Apple Developer portal
  entitlements and reverse-domain URL scheme setup.
- Sign-in with Apple requires the bundle id and service id configured.

#### Building for TestFlight / App Store
To produce an archive or IPA for TestFlight distribution:

```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

Or open `ios/Runner.xcworkspace` in Xcode, select **Any iOS Device (arm64)**, and go to **Product > Archive**. Ensure your Apple Developer Team and Provisioning Profiles are selected under the **Signing & Capabilities** tab.

### Android

```bash
flutter run                         # debug, playstore flavor by default
```

- The `erebrusai://auth` intent filter is declared in
  `android/app/src/main/AndroidManifest.xml`.

Release builds use two signing flavors (see `android/key.properties.example`):

```bash
./scripts/build-android-release.sh                 # both stores
./scripts/build-android-release.sh playstore       # Google Play AAB
./scripts/build-android-release.sh dappstore       # Solana dApp Store APK
```

Artifacts (version from `pubspec.yaml`):

- `dist/ErebrusAI-android-playstore-vX.Y.Z.aab` — Play Console
- `dist/ErebrusAI-android-dappstore-vX.Y.Z.apk` — Solana dApp Store

```bash
flutter build appbundle --flavor playstore --release --target-platform android-arm64
flutter build apk --flavor dappstore --release --target-platform android-arm64
```
- Solana Mobile Wallet Adapter is detected at runtime on Seeker / Saga devices.

---

## 7. Icons

App icons are generated from `assets/icons/erebrus-ai-icon-1024.png` using
`flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons:main
```

---

## 8. CI and releases

Workflows live in `.github/workflows/`. CI (`ci.yml`) needs no secrets.

Apple builds need Xcode 26 or newer (`erebrus_speech` uses `SpeechAnalyzer`);
the workflows select the newest stable Xcode 26+ on the runner and install its
Metal toolchain, a separate component since Xcode 26 that `mlx-swift` needs
for its shaders (locally: `xcodebuild -downloadComponent MetalToolchain`).
After every `flutter pub get`, `scripts/pin-spm-platforms.sh` pins the
generated plugin Swift package to iOS 17 / macOS 14
(`scripts/build-all-release.sh` calls it too).

Build steps run through `scripts/ci-annotate.sh`, which repeats a failed
step's error lines as workflow annotations. Annotations can be read without
signing in to GitHub, for example:
`curl -s https://api.github.com/repos/NetSepio/erebrus-ai/check-runs/<job id>/annotations`.

### Cutting a release

1. Bump `version:` in `pubspec.yaml` (for example `1.1.1+3`) and add a
   `## 1.1.1+3 — YYYY-MM-DD` section to `CHANGELOG.md`.
2. Commit, then push the commit and an annotated `v1.1.1` tag together:
   `git push --atomic origin main v1.1.1`.
3. `release.yml` fails fast if the tag does not match `pubspec.yaml` or the
   changelog section is missing, then publishes the GitHub Release.

Release assets:

| Asset | Use |
|-------|-----|
| `erebrus-ai-playstore-vX.Y.Z.aab` | Play Console upload |
| `erebrus-ai-playstore-vX.Y.Z.apk` | Sideload (Play Store key) |
| `erebrus-ai-dappstore-vX.Y.Z.apk` | Solana dApp Store (dApp Store key) |
| `erebrus-ai-windows-vX.Y.Z.zip` | Windows x64 |
| `erebrus-ai-linux-vX.Y.Z.tar.gz` | Linux x64 (built on Ubuntu 24.04) |
| `erebrus-ai-macos-vX.Y.Z.zip` | Only when `ENABLE_MACOS_BUILD=true` |
| `erebrus-ai-r8-mapping-vX.Y.Z.zip` | R8 mapping files for both flavors, to deobfuscate APK stack traces |
| `erebrus-ai-manifest-vX.Y.Z.json`, `erebrus-ai-sha256sums-vX.Y.Z.txt` | Sizes, SHA-256, signing certificates |

Android release builds are arm64-only, like `scripts/build-all-release.sh`.
They are shrunk and obfuscated with R8 (Flutter's default). App-specific keep
rules live in `android/app/proguard-rules.pro`. The App Bundle carries its own
mapping file, which the Play Console uses automatically. If a plugin breaks only
in release builds (a missing class or `TypeToken` error), add a keep rule
there; `flutter build apk --no-shrink` confirms that R8 is the cause.

### Secrets and variables

| Name | Kind | Purpose |
|------|------|---------|
| `PLAYSTORE_KEYSTORE_BASE64`, `PLAYSTORE_STORE_PASSWORD`, `PLAYSTORE_KEY_ALIAS`, `PLAYSTORE_KEY_PASSWORD` | Secret | Play Store signing key (`base64 -i erebrus-ai-playstore.jks`) |
| `DAPPSTORE_KEYSTORE_BASE64`, `DAPPSTORE_STORE_PASSWORD`, `DAPPSTORE_KEY_ALIAS`, `DAPPSTORE_KEY_PASSWORD` | Secret | dApp Store signing key; must be a different certificate |
| `REOWN_PROJECT_ID` | Secret or variable | Required; wallet sign-in |
| `GOOGLE_SERVER_CLIENT_ID`, `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI` | Secret or variable | Optional; app defaults apply when unset |
| `GATEWAY_URL`, `EREBRUS_WEB_ORIGIN`, `MODEL_CATALOG_BASE_URL` | Variable | Optional; default to production |
| `ENABLE_MACOS_BUILD` | Variable | `true` once CI can sign for team `76KW3AMAW5`; until then the macOS release job is skipped |

`scripts/write-ci-env.sh` writes these values to `.env` (bundled as an asset
and passed with `--dart-define-from-file`), skipping empty ones so app
defaults still apply.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `No .env file found` | Copy `env.example` to `.env` and set the variables. |
| Reown modal shows "project id missing" | Set `REOWN_PROJECT_ID` in `.env` or as `--dart-define`. |
| Desktop web login doesn't return | Ensure `erebrusai` URL scheme is registered for the platform. |
| `flutter test` fails on sign-in test | Real auth plugins don't run in tests; the smoke tests toggle `AppState.signedIn` directly. |
| Android build fails with secure storage | Make sure `minSdkVersion` is at least the value required by `flutter_secure_storage` (21). |
