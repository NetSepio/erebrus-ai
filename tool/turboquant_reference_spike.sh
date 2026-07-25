#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_URL="https://github.com/TheTom/llama-cpp-turboquant.git"
readonly REFERENCE_COMMIT="c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea"
readonly DEFAULT_CHECKOUT="/private/tmp/erebrus-llama-turboquant"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /absolute/model.gguf [checkout-directory]" >&2
  exit 64
fi

readonly MODEL_PATH="$1"
readonly CHECKOUT_PATH="${2:-$DEFAULT_CHECKOUT}"

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model does not exist: $MODEL_PATH" >&2
  exit 66
fi

if [[ ! -d "$CHECKOUT_PATH/.git" ]]; then
  if [[ -e "$CHECKOUT_PATH" ]]; then
    echo "Refusing to replace non-git path: $CHECKOUT_PATH" >&2
    exit 73
  fi
  git clone --filter=blob:none --no-checkout "$REPOSITORY_URL" "$CHECKOUT_PATH"
fi

git -C "$CHECKOUT_PATH" fetch --depth 1 origin "$REFERENCE_COMMIT"
git -C "$CHECKOUT_PATH" checkout --detach "$REFERENCE_COMMIT"

cmake -S "$CHECKOUT_PATH" -B "$CHECKOUT_PATH/build-erebrus-cpu" \
  -DGGML_METAL=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_CCACHE=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_TESTS=ON \
  -DLLAMA_BUILD_EXAMPLES=ON
cmake --build "$CHECKOUT_PATH/build-erebrus-cpu" \
  --target llama-cli test-quantize-fns -j 8
"$CHECKOUT_PATH/build-erebrus-cpu/bin/test-quantize-fns"

readonly CLI="$CHECKOUT_PATH/build-erebrus-cpu/bin/llama-cli"
readonly COMMON_ARGS=(
  -m "$MODEL_PATH"
  -p "Write one short sentence about private local AI."
  -n 32
  --temp 0
  --seed 42
  -c 16384
  -ngl 0
  -st
  --simple-io
  -v
)

echo "=== f16/f16 reference ==="
"$CLI" "${COMMON_ARGS[@]}" --cache-type-k f16 --cache-type-v f16

echo "=== q8_0/turbo3 experimental candidate ==="
"$CLI" "${COMMON_ARGS[@]}" \
  --cache-type-k q8_0 \
  --cache-type-v turbo3 \
  -fa on
