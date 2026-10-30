#!/usr/bin/env bash
# Runs a CI build command and, if it fails, repeats its error lines as
# workflow annotations. Annotations are public through the GitHub API, while
# step logs need a signed-in account, so failures stay diagnosable.
#
# Usage: scripts/ci-annotate.sh <command> [args...]
set -uo pipefail

log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [[ "$status" -ne 0 ]]; then
  # GitHub shows at most 10 error annotations per step.
  grep -E '(^|[^A-Za-z])(error|Error|ERROR|fatal|FAILED|Exception)([: ]|$)' "$log" |
    grep -v '^::' | tail -n 10 |
    while IFS= read -r line; do
      line="${line//'%'/%25}"
      printf '::error title=%s::%s\n' "$1 failed" "${line:0:500}"
    done
fi
rm -f "$log"
exit "$status"
