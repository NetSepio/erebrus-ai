#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  echo "Usage: $0 /absolute/llama-perplexity /absolute/model.gguf /absolute/corpus.txt [context] [max-ppl-increase-percent]" >&2
  exit 64
fi

readonly PERPLEXITY="$1"
readonly MODEL="$2"
readonly CORPUS="$3"
readonly CONTEXT="${4:-4096}"
readonly MAX_INCREASE_PERCENT="${5:-5}"

for path in "$PERPLEXITY" "$MODEL" "$CORPUS"; do
  if [[ ! -f "$path" ]]; then
    echo "Required file does not exist: $path" >&2
    exit 66
  fi
done

readonly RESULT_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$RESULT_DIRECTORY"' EXIT

run_ppl() {
  local output_file="$1"
  shift
  "$PERPLEXITY" \
    --model "$MODEL" \
    --file "$CORPUS" \
    --ctx-size "$CONTEXT" \
    --batch-size "$CONTEXT" \
    --n-gpu-layers 0 \
    --device none \
    --ppl-output-type 1 \
    "$@" 2>&1 | tee "$output_file" >&2
  awk '
    /Final estimate: PPL =/ {
      for (field = 1; field <= NF; field++) {
        if ($field == "=") value = $(field + 1)
      }
    }
    END {
      if (value == "") exit 1
      print value
    }
  ' "$output_file"
}

BASELINE_PPL="$(
  run_ppl "$RESULT_DIRECTORY/f16.log" \
    --cache-type-k f16 \
    --cache-type-v f16
)"
readonly BASELINE_PPL
CANDIDATE_PPL="$(
  run_ppl "$RESULT_DIRECTORY/turboquant.log" \
    --cache-type-k q8_0 \
    --cache-type-v turbo3 \
    --flash-attn on
)"
readonly CANDIDATE_PPL
INCREASE_PERCENT="$(
  awk -v baseline="$BASELINE_PPL" -v candidate="$CANDIDATE_PPL" \
    'BEGIN { printf "%.4f", ((candidate / baseline) - 1) * 100 }'
)"
readonly INCREASE_PERCENT

echo "f16/f16 PPL: $BASELINE_PPL"
echo "q8_0/turbo3 PPL: $CANDIDATE_PPL"
echo "PPL increase: $INCREASE_PERCENT%"
echo "Allowed increase: $MAX_INCREASE_PERCENT%"

awk \
  -v increase="$INCREASE_PERCENT" \
  -v maximum="$MAX_INCREASE_PERCENT" \
  'BEGIN { exit !(increase <= maximum) }'
