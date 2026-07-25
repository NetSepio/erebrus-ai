# Erebrus on-device release matrix

This matrix records engineering targets and release gates. “Target” does not
mean a backend is currently packaged or certified.

The pinned MLX Swift LM 3.31.3 package requires iOS 17 and macOS 14. Erebrus
therefore raises its Apple deployment targets to those versions for the native
MLX integration. SpeechAnalyzer remains runtime-gated to iOS/macOS 26+.

| Platform class | Baseline | Strategic backend | Initial certification devices |
| --- | --- | --- | --- |
| Apple-silicon macOS | llama.cpp Metal | MLX Swift | 8 GB M1, 16 GB M-series, 32 GB M-series |
| Intel macOS | llama.cpp CPU | none | 8 GB and 16 GB Intel Macs |
| iPhone | llama.cpp Metal | MLX Swift | 4 GB older supported device, 6 GB recent device, 8 GB recent Pro |
| iPad | llama.cpp Metal | MLX Swift | A-series 4/6 GB and M-series 8/16 GB |
| Android ARM64 | llama.cpp CPU | TurboQuant CPU, allowlisted Vulkan later | 4 GB low tier, 6/8 GB mid tier, 12/16 GB flagship |
| Windows x86-64 | llama.cpp CPU/GPU | TurboQuant CPU/CUDA/ROCm | CPU-only, NVIDIA, AMD |
| Linux x86-64 | llama.cpp CPU/GPU | TurboQuant CPU/CUDA/ROCm | CPU-only, NVIDIA, AMD |

## Required inference measurements

Every backend/model/device result records:

- model load time;
- time to first token;
- prompt and decode throughput;
- peak resident memory;
- context size and cache mode;
- cancellation and repeated-session behavior;
- battery/energy and sustained thermal behavior on mobile;
- deterministic correctness and task-quality results;
- packaged backend, accelerator, build revision, and fallback reason.

Run the packaged llama.cpp CPU baseline on macOS with:

```sh
flutter test integration_test/llama_cpp_benchmark_test.dart -d macos \
  --dart-define=BENCHMARK_MODEL=/absolute/path/model.gguf \
  --dart-define=BENCHMARK_VARIANT_ID=logical-variant-id \
  --dart-define=BENCHMARK_OUTPUT=/absolute/path/result.json
```

Optional defines control `BENCHMARK_CONTEXT`, `BENCHMARK_MAX_TOKENS`,
`BENCHMARK_ITERATIONS`, `BENCHMARK_GPU_LAYERS`, and `BENCHMARK_PROMPT`.
Results are JSON and must not be committed when they contain device-identifying
paths or user prompts. On sandboxed macOS builds, `BENCHMARK_MODEL` and
`BENCHMARK_OUTPUT` must resolve inside the app container or another location
the app has explicitly been granted access to.

The first packaged-runtime CPU baseline on 25 July 2026 used
SmolLM2-135M-Instruct Q8_0, a 2,048-token context, 64 generated tokens,
`gpuLayerCount: 0`, and three debug-build runs on an Apple-silicon Mac running
macOS 26.5. The averages were:

- model load: 210 ms;
- time to first token: 341 ms;
- decode: 85.4 tokens/second.

The cold first run was slower (369 ms load, 492 ms first token, 61.8 tok/s)
than the two warm filesystem-cache runs. These figures establish the current
CPU compatibility baseline; they are not release-build or sustained thermal
results, and the current bridge does not yet report prompt speed or peak RSS.

Run the packaged Metal path by adding:

```sh
--dart-define=BENCHMARK_GPU_LAYERS=99
```

The verified Metal package uses the official `lib_llama_cpp` 0.7.3 Metal
release asset, pinned by release tag, source revision, archive size, and
SHA-256 in `third_party/lib_llama_cpp_macos/PREBUILT_PROVENANCE.md`. On the
same Apple-silicon Mac and SmolLM2-135M-Instruct Q8_0 fixture, three debug
runs averaged 360.4 tokens/second. The cold run loaded in 7,555 ms and decoded
at 304.9 tok/s while Metal pipelines and caches were initialized. The next two
runs loaded in 48–49 ms, reached the first token in 64–65 ms, and decoded at
373.1–403.2 tok/s. This verifies packaging and materially faster execution; it
does not replace release-build, memory, energy, or representative-device
certification.

Run the native MLX bridge smoke test on macOS with a complete local MLX package:

```sh
flutter test integration_test/mlx_streaming_test.dart -d macos \
  --dart-define=MLX_TEST_MODEL=/absolute/path/to/mlx-model-directory
```

The production package was verified on 25 July 2026 with the exact
revision-pinned SmolLM2-135M-Instruct BF16 files published by the catalog. A
cold debug run loaded in 338 ms and emitted its first token in 1,308 ms; a warm
minimal-package run loaded in 327 ms and emitted its first token in 51 ms. This
proves the complete catalog-download-to-native-stream path; it is not a
release-performance or model-quality certification.

Run the Apple SpeechAnalyzer capability test with:

```sh
flutter test integration_test/speech_analyzer_probe_test.dart -d macos
```

The prototype uses one microphone buffer stream for both consumers: it writes
the original capture format to a per-session CAF file and converts that same
buffer to SpeechAnalyzer's preferred format for transcription. It requests and
installs only Apple's system-managed locale assets. Microphone and speech
permissions remain mandatory; no audio or transcript leaves the device.

## Current status

| Backend | Status | Honest application label |
| --- | --- | --- |
| llama.cpp CPU | Packaged; model load verifies usability | `llama.cpp · CPU` |
| llama.cpp Metal | Packaged and runtime-verified on Apple-silicon macOS; universal framework contains arm64 and x86-64 slices | `llama.cpp · Metal` after a successful capability probe |
| llama.cpp Metal (iOS) | Device and simulator XCFramework packaged; unsigned release build verified | `llama.cpp · Metal` after a successful capability probe |
| MLX Swift | Packaged on iOS 17+/macOS 14+; macOS runtime and unsigned iOS release build verified | `mlx · Metal` only after a successful runtime probe |
| TurboQuant | Contract and selection policy only | unavailable |
| SpeechAnalyzer | Native live-capture, streamed transcription, and session-audio prototype packaged; runtime-gated to iOS/macOS 26+ | `SpeechAnalyzer · on-device` only after a successful locale/asset probe |
| whisper.cpp ASR | Exact-pinned 1.8.3 runtime packaged; Android, universal macOS, and unsigned iOS release builds verified; Windows/Linux build gates run in CI | `whisper.cpp · on-device` only after the verified Tiny model is installed |

Promotion from experimental to beta/stable requires release builds on the
representative matrix, no corrupt output, bounded memory behavior, and a tested
fallback before the first token is emitted.

CI builds macOS release artifacts on both `macos-15` arm64 and
`macos-15-intel`, tests the platform resolver, verifies both framework slices,
and checks the exported Metal initialization symbol. Runtime performance and
thermal certification still require the physical device classes listed above.
The iOS CI job likewise verifies device/simulator Metal slices and builds an
unsigned release app containing MLX Swift. A signed build on physical iPhones
is still required before declaring any device tier certified.

The offline ASR path records 16 kHz mono WAV before file-based transcription,
keeps the chat LLM unloaded during constrained-device ASR, and verifies the
revision-pinned Whisper Tiny model by exact size and SHA-256. See
`docs/OFFLINE_TRANSCRIPTION.md` for provenance, session evidence, and current
build coverage. Android, universal macOS, and unsigned iOS builds pass; Windows
and Linux are implementation-complete but remain CI/physical-runtime gates.
