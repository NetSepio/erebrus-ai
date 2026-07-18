# Erebrus AI — One-Shot Build Plan

Package: `com.erebrus.ai`  
Repository: new repo `NetSepio/erebrus-ai` (Flutter multi-platform project)  
Primary targets: **macOS, Windows, Linux** (desktop always-on node)  
Secondary targets: **iOS, Android** (portable node + client)

---

## 1. Product Definition

Erebrus AI is a cross-platform local LLM runner. A user can download, load, and chat with quantized models. The app exposes an OpenAI-compatible API on the local network, and other devices can discover the node via mDNS and use its models. It supports prompt/persona engineering and user-created personas.

### Core user stories

- As a user, I want to download models from HuggingFace so I can run them locally.
- As a user, I want to chat with a model using a persona so the responses are styled.
- As a user, I want to create, edit, and delete personas.
- As a user, I want my desktop app to stay alive in the tray and serve models on the LAN.
- As a mobile user, I want to discover models on my desktop and chat with them.
- As a mobile user, I want to run small models on my phone while the app is open.
- As a developer, I want to call the local node with the OpenAI API from any device.

---

## 2. MVP Scope

### In scope

- Model download from curated HuggingFace GGUF URLs.
- Local model storage and loading.
- Chat UI with streaming responses.
- Persona presets + user-created personas.
- OpenAI-compatible server powered by `llama.cpp`.
- mDNS service registration and discovery.
- Desktop tray/background mode.
- Mobile discovery of local and network models.
- API key authentication.

### Out of scope for MVP

- Fine-tuning.
- RAG / document ingestion.
- Remote cloud models.
- Model quantization in-app.
- GPU acceleration beyond what `llama.cpp` auto-detects.
- iOS background server (server runs only while app is open).

---

## 3. Supported Platforms

| Platform | Role | Notes |
| --- | --- | --- |
| macOS | Desktop server + client | Primary target; Metal GPU support. |
| Windows | Desktop server + client | Primary target; CUDA/Vulkan optional. |
| Linux | Desktop server + client | Primary target; CUDA/Vulkan optional. |
| Android | Client + optional server | Server via foreground service or in-app. |
| iOS | Client + in-app server only | Server stops when app closes or locks. |
| Web | Not in MVP | Cannot run local models in browser. |

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter UI (chat, model browser, persona editor)   │
│  Dart service layer                                 │
├─────────────────────────────────────────────────────┤
│  llama.cpp server binary (per platform/arch)        │
│  GGUF model cache in app documents directory        │
│  Persona/chat store (SQLite/Isar/Hive)              │
├─────────────────────────────────────────────────────┤
│  mDNS service registration / discovery              │
│  OpenAI-compatible HTTP API on configurable port    │
└─────────────────────────────────────────────────────┘
```

### Desktop

- Starts `llama.cpp` server on login or user toggle.
- Runs in system tray with start/stop/quit menu.
- Publishes `_erebrus-ai._tcp` mDNS service.
- Binds to `0.0.0.0:<port>` so LAN clients can connect.

### Mobile

- Browses mDNS for `_erebrus-ai._tcp` nodes.
- Queries each node with `GET /v1/models`.
- Shows unified list of local and network models.
- Can start a local `llama.cpp` server with a small model while the app is open.
- Publishes its own `_erebrus-ai._tcp` service when hosting.

---

## 5. Tech Stack

### Flutter / Dart

- **Flutter SDK:** `^3.24.0`
- **State management:** `Get` or `Riverpod`. Use `Get` if reusing Erebrus VPN patterns.
- **HTTP client:** `dio`
- **Local DB:** `isar` or `drift` for personas/chat history; `hive` for settings.
- **File system:** `path_provider`, `file_picker`
- **Process management:** `dart:io` `Process` for spawning `llama.cpp` server.
- **Window/tray:** `window_manager`, `tray_manager` (desktop).
- **mDNS:** `bonsoir` (iOS/macOS), `nsd` (Android), custom platform channel for Windows/Linux.
- **Network info:** `network_info_plus`
- **Markdown rendering:** `flutter_markdown`
- **Shared preferences:** `shared_preferences`
- **Secure storage:** `flutter_secure_storage` for API keys.

### Native backend

- `llama.cpp` server binary built per platform.
- Binaries bundled at build time for desktop; downloaded on first run for mobile (optional) or bundled.

---

## 6. Project Structure

```
erebrus-ai/
├── android/
├── ios/
├── linux/
├── macos/
├── windows/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── di/
│   │   └── service_locator.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── app_colors.dart
│   ├── models/
│   │   ├── ai_model.dart
│   │   ├── persona.dart
│   │   ├── chat_message.dart
│   │   ├── chat_session.dart
│   │   ├── ai_node.dart
│   │   └── openai/
│   │       ├── chat_completion_request.dart
│   │       ├── chat_completion_response.dart
│   │       └── models_response.dart
│   ├── services/
│   │   ├── inference_service.dart
│   │   ├── model_manager.dart
│   │   ├── persona_store.dart
│   │   ├── chat_store.dart
│   │   ├── mdn_service.dart
│   │   ├── node_discovery_service.dart
│   │   ├── openai_client.dart
│   │   └── settings_service.dart
│   ├── view/
│   │   ├── chat/
│   │   ├── models/
│   │   ├── personas/
│   │   ├── settings/
│   │   └── shell/
│   └── platform/
│       ├── native_binary_helper.dart
│       ├── desktop_tray.dart
│       └── mobile_process_helper.dart
├── assets/
│   └── llama-bin/
│       ├── llama-server-darwin-arm64
│       ├── llama-server-darwin-x64
│       ├── llama-server-linux-x64
│       ├── llama-server-windows-x64.exe
│       └── mobile-config.json
├── scripts/
│   ├── build-llama-all.sh
│   ├── setup-mobile-binaries.sh
│   └── release.sh
├── bin/                              # downloaded models at runtime (gitignored)
├── docs/
│   └── EREbrus_AI_PLAN.md
├── pubspec.yaml
└── README.md
```

---

## 7. Data Models

### `AiModel`

```dart
class AiModel {
  final String id;                 // unique slug, e.g. "qwen3.5-0.8b-q4_k_m"
  final String displayName;
  final String family;             // qwen, gemma, bonsai, llama, etc.
  final String parameters;         // "0.8B", "27B"
  final String quantization;       // "Q4_K_M", "Q8_0"
  final String sourceUrl;          // HuggingFace direct GGUF URL
  final String? localPath;         // path on device after download
  final int? fileSizeBytes;
  final DownloadStatus status;
  final double? downloadProgress;
  final List<String>? availableOnNodeIds; // network nodes hosting this model
}
```

### `Persona`

```dart
class Persona {
  final String id;
  final String name;
  final String systemPrompt;
  final String? userMessageTemplate;
  final double temperature;
  final double topP;
  final int maxTokens;
  final double repeatPenalty;
  final String? stopSequences;
  final bool isBuiltIn;
  final Map<String, dynamic>? extraParams;
}
```

### `ChatSession`

```dart
class ChatSession {
  final String id;
  final String title;
  final String modelId;
  final String? nodeId;            // null = local / this device
  final String personaId;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### `ChatMessage`

```dart
class ChatMessage {
  final String id;
  final String role;               // system, user, assistant
  final String content;
  final DateTime timestamp;
  final bool isStreaming;
}
```

### `AiNode`

```dart
class AiNode {
  final String id;                 // service instance name, e.g. "Erebrus AI on MacBook-Pro"
  final String name;
  final String host;               // resolved IP
  final int port;
  final String? apiKey;
  final DateTime lastSeen;
  final List<AiModel> models;
}
```

---

## 8. API Contracts

### Server endpoints (provided by `llama.cpp` server)

- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `POST /v1/embeddings` (optional)

All endpoints support `Authorization: Bearer <api-key>` when enabled.

### mDNS service

- Service type: `_erebrus-ai._tcp`
- TXT records:
  - `version=1`
  - `api-key-hash=<sha256(apiKey).substring(0,16)>`
  - `platform=macos|windows|linux|ios|android`
  - `model-count=3` (optional hint)

### Node-to-node model query

Mobile discovers a node, then:

```
GET http://<host>:<port>/v1/models
Authorization: Bearer <api-key>
```

The response is merged into the model browser.

---

## 9. Key Services

### `InferenceService`

- Finds the correct `llama-server` binary for the platform.
- Starts/stops the server with a selected model.
- Builds the CLI args: `-m`, `--port`, `--host`, `--ctx-size`, `-ngl`, `--api-key`, `--chat-template`.
- Exposes a stream of server status: `idle`, `starting`, `ready`, `error`.
- On desktop, auto-starts on launch if setting is enabled.

### `ModelManager`

- Maintains a JSON catalog of built-in recommended models.
- Downloads models with resumable `dio` requests.
- Stores models in `getApplicationDocumentsDirectory()/models`.
- Deletes local models.
- Maps network model discovery results into `AiModel` objects.

### `PersonaStore`

- CRUD for personas.
- Built-in presets shipped with the app.
- Applies persona to each chat request (system prompt + sampler params).

### `NodeDiscoveryService`

- Registers `_erebrus-ai._tcp` when the local server starts.
- Unregisters when the server stops.
- Browses `_erebrus-ai._tcp` continuously or on pull-to-refresh.
- Polls each node's `/v1/models` endpoint.

### `OpenAIClient`

- Sends `POST /v1/chat/completions` with `stream: true`.
- Parses SSE chunks.
- Supports cancellation via `CancelToken`.

---

## 10. UI Screens

### `ChatView`

- Message list (user/assistant bubbles).
- Input field with send button.
- Model + persona selector in the app bar.
- Streaming text rendering.
- Regenerate / copy / share actions.

### `ModelBrowserView`

- Tabs: **Local** and **Network**.
- Search bar.
- Download progress and actions (load, delete, download, cancel).
- Network model list grouped by node.

### `PersonaEditorView`

- Name and system prompt fields.
- Sampler sliders: temperature, top_p, max tokens, repeat penalty.
- Stop sequences input.
- Save / delete / duplicate actions.

### `SettingsView`

- Server port and API key.
- Auto-start on login (desktop).
- Context size and GPU layers defaults.
- Theme and notification preferences.

### `Shell`

- Bottom navigation for mobile.
- Sidebar or tabbed layout for desktop.
- Tray integration for desktop.

---

## 11. Implementation Phases

### Phase 0: Bootstrap

1. Create Flutter project `com.erebrus.ai`.
2. Add dependencies.
3. Set up folder structure.
4. Configure desktop support: `window_manager`, `tray_manager`.
5. Build or download `llama-server` for macOS, Windows, Linux.
6. Add binaries to `assets/llama-bin/` and wire platform-specific loading.

### Phase 1: Local Inference on Desktop

1. Implement `InferenceService` to spawn `llama-server`.
2. Hardcode one small model URL for initial testing.
3. Implement `ModelManager` download with progress.
4. Create `ChatView` and `OpenAIClient` with streaming.
5. Verify a chat works end-to-end on desktop.

### Phase 2: Personas

1. Implement `PersonaStore` with built-in presets.
2. Build `PersonaEditorView`.
3. Apply selected persona to chat requests.

### Phase 3: mDNS and Network Discovery

1. Implement `NodeDiscoveryService`.
2. Register service on desktop when server starts.
3. Implement `ModelBrowserView` with network tab.
4. Test mobile discovering desktop node.

### Phase 4: Mobile Server (In-App)

1. Build or download `llama-server` for iOS and Android.
2. Implement `MobileProcessHelper` to start server while app is open.
3. Register mDNS service on mobile.
4. Allow mobile to load a small model and chat locally.

### Phase 5: Android Foreground Service

1. Add Android foreground service for always-on server.
2. Persistent notification with stop action.
3. Register mDNS when service starts.

### Phase 6: Polish

1. Settings screen.
2. Tray menu (desktop).
3. API key setup and QR-code pairing.
4. Error handling, logging, and diagnostics screen.
5. CI/CD builds for all desktop platforms.

---

## 12. Build & Release

### Binary builds

- Build `llama.cpp` server from source for each platform in CI.
- Matrix:
  - macOS: `arm64`, `x64`
  - Windows: `x64` (MSVC), optional `cuda`
  - Linux: `x64` (gcc), optional `cuda`
  - iOS: `arm64` (device), `simulator` (not for distribution)
  - Android: `arm64-v8a`, `x86_64`

### CI/CD

- GitHub Actions workflow similar to `erebrus-vpn` `ci.yml` and `release.yml`.
- Jobs:
  - `lint` and `test`
  - `build-llama-binaries`
  - `build-desktop` (macOS, Windows, Linux)
  - `build-mobile` (Android, iOS)
  - `release` on tag push

### Code signing

- macOS: notarize the app and sign `llama-server` binary.
- Windows: sign `.exe` with certificate.
- iOS/Android: standard app signing.

---

## 13. Security & Privacy

- All inference stays local. No cloud telemetry by default.
- API key is generated randomly on first launch.
- LAN exposure requires the key; mobile clients must enter or scan the key.
- Do not ship models in the installer; download on demand.
- Store API key in secure storage (`flutter_secure_storage`).

---

## 14. Definition of Done for One-Shot Build

The "one-shot build" is complete when:

- [ ] A new Flutter project exists at `NetSepio/erebrus-ai` with package `com.erebrus.ai`.
- [ ] Desktop builds run on macOS, Windows, and Linux.
- [ ] `llama-server` binaries are bundled and loaded per platform.
- [ ] User can download at least one model and chat with it locally.
- [ ] Persona presets exist and users can create/edit personas.
- [ ] Desktop app runs in tray and serves on a port.
- [ ] mDNS service is published by desktop server.
- [ ] Mobile app discovers desktop nodes and lists their models.
- [ ] Mobile app can chat with a network model.
- [ ] Mobile app can run a small local model while open (iOS/Android).
- [ ] Android foreground service can keep the server alive.
- [ ] All endpoints are OpenAI-compatible and tested with `curl`.
- [ ] README includes build instructions for each platform.

---

## 15. First Command to Run

When you say "build it", the first step is:

```bash
git clone git@github.com:NetSepio/erebrus-ai.git
cd erebrus-ai
flutter create --org com.erebrus --project-name erebrus_ai .
```

Then apply this plan phase by phase.
