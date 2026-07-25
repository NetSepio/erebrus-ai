# TurboQuant Android engineering record

## Current release decision

TurboQuant is **not enabled or packaged in the Android app yet**. Android
continues to use the verified upstream llama.cpp ARM64 CPU library and the same
GGUF models. Compiling a fork is not evidence that its output, thermals, or GPU
kernels are safe on a phone.

The production allowlist is empty. Settings report the candidate as
uncertified, and no code path can silently select it.

## Pinned ARM64 CPU candidate

The candidate uses the same audited base as desktop:

- repository: `TheTom/llama-cpp-turboquant`;
- revision: `c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea`;
- cache policy: `q8_0` keys and `turbo3` values;
- Android ABI: `arm64-v8a`;
- API level: 28;
- NDK used locally: 28.2.13676358;
- NEON patch:
  `third_party/erebrus_turboquant/patches/android-neon-fwht.patch`;
- NEON patch SHA-256:
  `532760b3237979ee7a536ec9ca87e95fb9da069b9b2d4f431233941833b93123`.

The patch vectorizes contiguous sign/scale passes and all WHT butterfly stages
of width four or greater with ARM64 NEON while keeping a scalar fallback. It
does not change the cache format or numerical order within a butterfly.

Build it with:

```sh
export ANDROID_NDK_HOME=/absolute/path/to/android-ndk
tool/build_turboquant_android.sh CPU
```

The script refuses a dirty source checkout, checks out the exact base commit,
verifies and applies the exact patch, cross-compiles the candidate and generic
quantization test, then verifies AArch64, TurboQuant symbols, and vector
instructions in the ELF output.

On 26 July 2026 the CPU build passed locally. The resulting `llama-simple`
binary was an Android AArch64 PIE and contained
`quantize_row_turbo3_0_ref`, `dequantize_row_turbo3_0`, and NEON instructions.
The generic quantization suite cross-compiled. It cannot execute on the macOS
build host, so it is not counted as Android runtime certification.

The same patched source passed the native ARM generic quantization suite and
the existing end-to-end PPL gate. The provisional PPL comparison remained
19.0700 for `f16/f16` and 19.7284 for `q8_0/turbo3` (3.45% relative increase).
That verifies the patch did not change this fixture's result; it is not a
substitute for Android device quality testing.

## Why the candidate is not linked into Flutter

The fork inserts `n_outputs_max` into `llama_context_params`. The current
`lib_llama_cpp_ffi` 0.7.3 binding does not have that field, so passing its Dart
struct to the fork would shift every later field and risk corrupted output or
a crash. Android therefore retains the upstream library until Erebrus has an
ABI-stable primitive/JSON wrapper or an independently generated fork binding,
plus physical-device tests.

## Vulkan and OpenCL

The Vulkan cross-build route is present in
`tool/build_turboquant_android.sh VULKAN`. It requires the Android NDK Vulkan
loader and shader compiler plus a `SPIRV-Headers` CMake package. The local host
had the NDK components but not `SPIRV-Headers`, so configuration stopped
without producing an artifact.

More importantly, a successful cross-build would still remain disabled.
Upstream discussion includes a concrete report of `turbo3` Vulkan corrupt
output and crashes on AMD hardware. Android Vulkan must pass deterministic
output, PPL/retrieval, repeated-session, cancellation, memory, battery, and
thermal tests for an exact device, OS build, GPU, and driver before promotion.

OpenCL is not enabled. The pinned fork exposes experimental OpenCL work, but
Android has no uniform public OpenCL support contract and Erebrus has no
certified driver matrix. CPU is evaluated first; Vulkan follows only on
allowlisted devices.

## Device and thermal policy

`AndroidAccelerationService` reads only system build/hardware facts, ABI,
Vulkan feature version, and Android thermal status. No identifier is uploaded.
A certification matches:

- manufacturer, device, and hardware;
- SDK range;
- a non-empty build-fingerprint prefix; and
- minimum Vulkan version when GPU execution is approved.

An OS/driver build change invalidates the match. Severe or worse thermal status
disables TurboQuant. Moderate pressure caps a certified session to a 2K context
and 384 output tokens.

Certified CPU context presets remain bounded:

| RAM | Maximum context |
| --- | ---: |
| below 6 GB | 1K |
| 6–8 GB | 2K |
| 8–12 GB | 4K |
| 12 GB or more | 8K |

## Promotion checklist

For each candidate device:

1. package an ABI-stable runtime without replacing upstream llama.cpp;
2. run the generic and rotated-domain quantization tests on-device;
3. compare deterministic output, PPL, retrieval, and long-context tasks;
4. measure peak RSS, time to first token, sustained decode, energy, and thermal
   state across repeated 15/30-minute sessions;
5. test cancellation, background/foreground transitions, and low-memory kill;
6. test same-GGUF fallback before the first token;
7. record exact device, OS fingerprint, GPU/driver, base revision, and patch
   hash; and
8. add a narrow certification entry only after all gates pass.

## Fork maintenance and upstreaming

The Android patch stays as one checksum-pinned delta over the desktop base.
Each rebase must apply cleanly, rebuild CPU and Vulkan candidates, and rerun
the shared quality gates. The NEON change should be proposed upstream after
physical ARM64 benchmarks demonstrate a sustained benefit with equivalent
outputs. Erebrus will not carry device-specific correctness work as an
unreviewed binary-only patch.

References:

- [TurboQuant llama.cpp fork](https://github.com/TheTom/llama-cpp-turboquant)
- [Reported TurboQuant Vulkan corrupt output/crash](https://github.com/ggml-org/llama.cpp/issues/22842)
- [Android thermal status API](https://developer.android.com/reference/android/os/PowerManager#getCurrentThermalStatus())
