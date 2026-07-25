#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_URL="https://github.com/TheTom/llama-cpp-turboquant.git"
readonly REFERENCE_COMMIT="c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea"
readonly NEON_PATCH_SHA256="532760b3237979ee7a536ec9ca87e95fb9da069b9b2d4f431233941833b93123"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
readonly NEON_PATCH="$REPOSITORY_ROOT/third_party/erebrus_turboquant/patches/android-neon-fwht.patch"
readonly ACCELERATOR="${1:-CPU}"
readonly CHECKOUT_PATH="${2:-/private/tmp/erebrus-turboquant-android-source}"
readonly BUILD_PATH="${3:-/private/tmp/erebrus-turboquant-android-arm64}"

if [[ "$ACCELERATOR" != "CPU" && "$ACCELERATOR" != "VULKAN" ]]; then
  echo "Accelerator must be CPU or VULKAN" >&2
  exit 64
fi
if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME must name an installed Android NDK" >&2
  exit 69
fi

actual_patch_hash="$(shasum -a 256 "$NEON_PATCH" | awk '{print $1}')"
if [[ "$actual_patch_hash" != "$NEON_PATCH_SHA256" ]]; then
  echo "Android NEON patch checksum mismatch" >&2
  exit 65
fi

if [[ ! -d "$CHECKOUT_PATH/.git" ]]; then
  if [[ -e "$CHECKOUT_PATH" ]]; then
    echo "Refusing to replace non-git path: $CHECKOUT_PATH" >&2
    exit 73
  fi
  git clone --filter=blob:none --no-checkout "$REPOSITORY_URL" "$CHECKOUT_PATH"
fi

if [[ -n "$(git -C "$CHECKOUT_PATH" status --short)" ]]; then
  echo "Refusing to alter a dirty TurboQuant checkout: $CHECKOUT_PATH" >&2
  exit 65
fi
if [[ "$(git -C "$CHECKOUT_PATH" rev-parse HEAD)" != "$REFERENCE_COMMIT" ]]; then
  git -C "$CHECKOUT_PATH" fetch --depth 1 origin "$REFERENCE_COMMIT"
  git -C "$CHECKOUT_PATH" checkout --detach "$REFERENCE_COMMIT"
fi
git -C "$CHECKOUT_PATH" apply --check "$NEON_PATCH"
git -C "$CHECKOUT_PATH" apply "$NEON_PATCH"
git -C "$CHECKOUT_PATH" diff --check

case "$(uname -s)" in
  Darwin) readonly NDK_HOST="darwin-x86_64" ;;
  Linux) readonly NDK_HOST="linux-x86_64" ;;
  *)
    echo "Unsupported Android build host" >&2
    exit 69
    ;;
esac

readonly NDK_TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
readonly NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST/bin"
if [[ ! -f "$NDK_TOOLCHAIN" || ! -x "$NDK_BIN/llvm-readelf" ]]; then
  echo "Android NDK toolchain is incomplete: $ANDROID_NDK_HOME" >&2
  exit 69
fi

cmake_args=(
  -G Ninja
  "-DCMAKE_TOOLCHAIN_FILE=$NDK_TOOLCHAIN"
  -DANDROID_ABI=arm64-v8a
  -DANDROID_PLATFORM=android-28
  -DANDROID_STL=c++_shared
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DGGML_NATIVE=OFF
  -DGGML_CCACHE=OFF
  -DGGML_OPENMP=OFF
  -DGGML_METAL=OFF
  -DGGML_OPENCL=OFF
  -DLLAMA_BUILD_TESTS=ON
  -DLLAMA_BUILD_EXAMPLES=ON
  -DLLAMA_BUILD_SERVER=OFF
  -DLLAMA_BUILD_TOOLS=ON
  -DLLAMA_CURL=OFF
  -DLLAMA_OPENSSL=OFF
)

if [[ "$ACCELERATOR" == "VULKAN" ]]; then
  readonly VULKAN_INCLUDE="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST/sysroot/usr/include"
  readonly VULKAN_LIBRARY="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST/sysroot/usr/lib/aarch64-linux-android/28/libvulkan.so"
  glslc_path="$(find "$ANDROID_NDK_HOME/shader-tools" -type f -name glslc -perm -111 -print -quit)"
  spirv_headers_dir="${SPIRV_HEADERS_DIR:-}"
  if [[ -z "$spirv_headers_dir" && -n "${VULKAN_SDK:-}" ]]; then
    spirv_headers_dir="$VULKAN_SDK/share/cmake/SPIRV-Headers"
  fi
  if [[ ! -f "$VULKAN_LIBRARY" || -z "$glslc_path" ||
        ! -f "$spirv_headers_dir/SPIRV-HeadersConfig.cmake" ]]; then
    echo "Vulkan requires the NDK library/glslc and SPIRV_HEADERS_DIR" >&2
    exit 69
  fi
  cmake_args+=(
    -DGGML_VULKAN=ON
    "-DVulkan_INCLUDE_DIR=$VULKAN_INCLUDE"
    "-DVulkan_LIBRARY=$VULKAN_LIBRARY"
    "-DVulkan_GLSLC_EXECUTABLE=$glslc_path"
    "-DSPIRV-Headers_DIR=$spirv_headers_dir"
  )
else
  cmake_args+=(-DGGML_VULKAN=OFF)
fi

cmake -S "$CHECKOUT_PATH" -B "$BUILD_PATH" "${cmake_args[@]}"
cmake --build "$BUILD_PATH" --target llama-simple test-quantize-fns -j 8

readonly SIMPLE="$BUILD_PATH/bin/llama-simple"
readonly QUANT_TEST="$BUILD_PATH/bin/test-quantize-fns"
"$NDK_BIN/llvm-readelf" -h "$SIMPLE" |
  awk '/Machine:.*AArch64/ { found = 1 } END { exit !found }'
"$NDK_BIN/llvm-nm" "$SIMPLE" |
  awk '/quantize_row_turbo3_0_ref/ { found = 1 } END { exit !found }'
"$NDK_BIN/llvm-nm" "$SIMPLE" |
  awk '/dequantize_row_turbo3_0/ { found = 1 } END { exit !found }'
"$NDK_BIN/llvm-objdump" -d "$SIMPLE" |
  awk '/[[:space:]](fmla|fadd|fsub|fmul|addv|uzp1)[[:space:]]/ { found = 1 } END { exit !found }'

echo "TurboQuant Android candidate built successfully"
echo "Base revision: $REFERENCE_COMMIT"
echo "NEON patch SHA-256: $NEON_PATCH_SHA256"
echo "Accelerator: $ACCELERATOR"
shasum -a 256 "$SIMPLE" "$QUANT_TEST"
echo "Runtime execution still requires a physical allowlisted Android ARM64 device"
