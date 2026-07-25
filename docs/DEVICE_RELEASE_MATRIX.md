# Erebrus on-device release matrix

This matrix records engineering targets and release gates. “Target” does not
mean a backend is currently packaged or certified.

| Platform class | Baseline | Strategic backend | Initial certification devices |
| --- | --- | --- | --- |
| Apple-silicon macOS | llama.cpp CPU, then Metal | MLX Swift | 8 GB M1, 16 GB M-series, 32 GB M-series |
| Intel macOS | llama.cpp CPU | none | 8 GB and 16 GB Intel Macs |
| iPhone | llama.cpp CPU | MLX Swift | 4 GB older supported device, 6 GB recent device, 8 GB recent Pro |
| iPad | llama.cpp CPU | MLX Swift | A-series 4/6 GB and M-series 8/16 GB |
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

Run the current llama.cpp CPU baseline with:

```sh
flutter test test/inference_benchmark_test.dart \
  --dart-define=BENCHMARK_MODEL=/absolute/path/model.gguf \
  --dart-define=BENCHMARK_VARIANT_ID=logical-variant-id \
  --dart-define=BENCHMARK_OUTPUT=/absolute/path/result.json
```

Optional defines control `BENCHMARK_CONTEXT`, `BENCHMARK_MAX_TOKENS`,
`BENCHMARK_ITERATIONS`, `BENCHMARK_GPU_LAYERS`, and `BENCHMARK_PROMPT`.
Results are JSON and must not be committed when they contain device-identifying
paths or user prompts.

## Current status

| Backend | Status | Honest application label |
| --- | --- | --- |
| llama.cpp CPU | Packaged; model load verifies usability | `llama.cpp · CPU` |
| llama.cpp Metal | Not packaged in the current Apple XCFramework | unavailable |
| MLX Swift | Contract and catalog schema only | unavailable |
| TurboQuant | Contract and selection policy only | unavailable |
| SpeechAnalyzer | Contract only | unavailable |
| whisper.cpp | Not packaged | unavailable |

Promotion from experimental to beta/stable requires release builds on the
representative matrix, no corrupt output, bounded memory behavior, and a tested
fallback before the first token is emitted.
