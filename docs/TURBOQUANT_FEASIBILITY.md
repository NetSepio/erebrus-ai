# TurboQuant feasibility record

## Selected Phase 0 reference

- Repository: `TheTom/llama-cpp-turboquant`
- Branch: `feature/turboquant-kv-cache`
- Pinned commit: `c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea`
- Commit date: 18 July 2026
- License at the pinned commit: MIT
- Status: pinned CPU runtime integrated for Windows and Linux; CUDA/HIP
  candidates require accelerator-runner certification before release

This fork was selected because it exercises Turbo-style KV compression inside
llama.cpp with the same GGUF model weights and exposes CPU, Metal, CUDA, HIP,
Vulkan, and SYCL implementation work. It remains explicitly work in progress
and is not upstream llama.cpp.

The first Erebrus candidate mode is the fork's asymmetric `q8_0` key /
`turbo3` value cache. In this implementation, `turbo3` uses Walsh–Hadamard
rotation plus a 3-bit polar codebook. It is a community “TurboQuant+” mode, not
an exact implementation of the paper's full `TURBOQUANTprod` two-stage
MSE-plus-QJL construction. Erebrus must use that exact disclosure anywhere the
experimental mode is shown.

## Production integration

Erebrus packages the pinned fork as a static `llama-server` sidecar through
`third_party/erebrus_turboquant`. The source archive is immutable and verified
by SHA-256 during CMake configuration. The app refuses to advertise the
backend unless the executable and generated provenance manifest agree on the
commit, archive hash, accelerator, and `q8_0/turbo3` cache modes.

The sidecar is deliberately separate from `lib_llama_cpp_ffi`. The fork adds
`n_outputs_max` to `llama_context_params`, making it ABI-incompatible with the
current `lib_llama_cpp_ffi` 0.7.3 structure layout. Loading the fork under the
existing Dart bindings would risk field corruption. Instead, Erebrus:

- binds the process to IPv4 loopback on an ephemeral port;
- generates a per-process bearer token;
- disables the web UI, slots endpoint, and prompt RAM cache;
- streams the OpenAI-compatible endpoint into the common inference contract;
- stops or falls back to upstream llama.cpp only before the first token; and
- reuses the exact same installed GGUF file for fallback.

CPU is the default package. A release builder selects `CUDA` or `HIP` with
`EREBRUS_TURBOQUANT_ACCELERATOR`; the accelerator is embedded in the manifest
and shown by backend diagnostics. The manual accelerator-certification
workflow requires correspondingly labelled self-hosted hardware, so a
toolchain-only compile cannot be mistaken for runtime certification.

Validated TurboQuant desktops receive a larger, bounded context preset:
4K below 8 GB RAM, 8K below 16 GB, 16K below 32 GB, and 32K at 32 GB or more.
Other backends retain their own memory policy.

## Reproduction

Run:

```sh
tool/turboquant_reference_spike.sh /absolute/path/model.gguf
```

The script checks out the exact reference commit, disables `ccache` and native
host tuning for reproducibility, builds the CPU CLI and quantization tests,
runs the test suite, and compares `f16/f16` with `q8_0/turbo3` at a 16,384-token
context. It intentionally requires a caller-supplied model and does not place
weights in the repository.

The automated quality threshold is:

```sh
tool/turboquant_quality_gate.sh \
  /absolute/path/llama-perplexity \
  /absolute/path/model.gguf \
  /absolute/path/evaluation-corpus.txt \
  4096 \
  5
```

It compares `f16/f16` and `q8_0/turbo3` perplexity with the same model, corpus,
context, and CPU execution and fails if the relative increase exceeds the
specified percentage. Release candidates should use a pinned, redistribution-
approved corpus rather than repository prose.

The Metal configuration also compiled successfully on Apple silicon with:

```sh
cmake -S . -B build \
  -DGGML_METAL=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_CCACHE=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --target llama-cli test-quantize-fns -j 8
```

## Phase 0 observations

Test model: `SmolLM2-135M-Instruct-Q8_0.gguf`.

| Mode | 16K K cache | 16K V cache | Total KV | Short decode |
| --- | ---: | ---: | ---: | ---: |
| `f16/f16` | 180.00 MiB | 180.00 MiB | 360.00 MiB | 331.7 tok/s |
| `q8_0/turbo3` | 95.62 MiB | 70.31 MiB | 165.94 MiB | 308.1 tok/s |

The asymmetric candidate reduced total KV allocation by 53.9% (2.17× smaller)
and short decode throughput by about 7.1%. This tiny prompt/model run proves
the code path and memory effect only. It does not establish long-context
quality, energy, or production speed.

The fork's generic quantization suite passed. Turbo2/3/4 are marked skipped by
that suite because they require rotated-domain KV tests; the end-to-end
`llama-cli` run supplied that basic execution coverage.

## Phase 5 integration verification

On 26 July 2026, the production package definition built `llama-server`
successfully from the pinned archive source. The executable reported
`version: 1 (c26cbdf)`. An authenticated loopback smoke test loaded
`SmolLM2-135M-Instruct-Q8_0.gguf` with a 4K `q8_0/turbo3` cache, returned a
healthy status, streamed chat-completion chunks, emitted usage/timing data,
and shut down cleanly. The short generation measured 587.57 prompt tokens/s
and 136.66 decode tokens/s on an Apple M4 Pro CPU build; this validates the
transport and cache code path, not Windows/Linux performance.

A small deterministic PPL plumbing smoke test over 768 README tokens at a
256-token context measured:

| Cache | PPL |
| --- | ---: |
| `f16/f16` | 19.0700 |
| `q8_0/turbo3` | 19.7284 |

That is a 3.45% relative increase and passes the provisional 5% script
threshold. It is not a release-quality language evaluation.

Flutter analysis and the full 50-test suite pass, including TurboQuant
capability, same-GGUF compatibility, retained load, reload, stream mapping,
provenance refusal, and memory-policy tests.

## Remaining promotion gates

- Add deterministic rotated-domain unit vectors and cross-backend conformance.
- Compare perplexity, LongBench-style tasks, and needle retrieval against f16,
  q8, and upstream llama.cpp quantized KV.
- Measure long-context prefill/decode, resident memory, energy, and repeated
  sessions on the release matrix.
- Run the committed Windows/Linux CPU release jobs and runtime smoke tests.
- Run the committed CUDA and HIP package jobs on labelled physical runners,
  then add only passing accelerator artifacts to a release.
- Keep Vulkan and Android behind explicit allowlists until correctness and
  driver stability pass.
- Complete dependency, patent, and redistribution review.

The app automatically selects TurboQuant only when a packaged runtime passes
its local provenance probe. CPU packages may now advertise it. CUDA and HIP
artifacts must not be published until their physical-runner gates pass.

## Android expansion

Phase 6 adds a reproducible Android ARM64 CPU cross-build and a checksum-pinned
NEON WHT patch, but does not package or advertise the fork on Android. The
fork's context-parameter ABI differs from the current Dart binding, no Android
device is attached for runtime/thermal certification, and the production
device allowlist is therefore empty. Vulkan/OpenCL remain disabled. Full
evidence and promotion criteria are in `docs/ANDROID_TURBOQUANT.md`.
