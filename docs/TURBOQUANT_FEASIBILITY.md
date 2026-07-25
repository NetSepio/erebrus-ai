# TurboQuant feasibility record

## Selected Phase 0 reference

- Repository: `TheTom/llama-cpp-turboquant`
- Branch: `feature/turboquant-kv-cache`
- Pinned commit: `c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea`
- Commit date: 18 July 2026
- License at the pinned commit: MIT
- Status: executable research reference; not packaged in Erebrus

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

## Promotion blockers

- Vendor or package a reviewed, minimal pinned source set.
- Add deterministic rotated-domain unit vectors and cross-backend conformance.
- Compare perplexity, LongBench-style tasks, and needle retrieval against f16,
  q8, and upstream llama.cpp quantized KV.
- Measure long-context prefill/decode, resident memory, energy, and repeated
  sessions on the release matrix.
- Validate CPU first on Linux and Windows, then CUDA and ROCm.
- Keep Vulkan and Android behind explicit allowlists until correctness and
  driver stability pass.
- Preserve standard GGUF fallback and switch only before the first token.
- Complete dependency, patent, and redistribution review.

Until those gates pass, `BackendProbeService` must continue to report
TurboQuant as unavailable in production builds.
