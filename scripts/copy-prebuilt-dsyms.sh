#!/usr/bin/env bash
#
# Ensure App Store / Organizer archives include dSYMs for prebuilt llama
# frameworks. Upstream Metal/CPU prebuilts ship stripped binaries without
# companion dSYMs; validation rejects archives whose embedded UUIDs lack a
# matching DWARF file in the archive's dSYMs folder.
#
# Invoked from the Runner Xcode projects (macOS + iOS) after frameworks are
# embedded. Safe for non-archive builds when DWARF_DSYM_FOLDER_PATH is unset.
#
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Release" && "${CONFIGURATION:-}" != "Profile" ]]; then
  exit 0
fi

if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
  exit 0
fi

mkdir -p "${DWARF_DSYM_FOLDER_PATH}"

# Always resolve from this script (repo/scripts/…) so SRCROOT layout differences
# between macos/ and ios/ Xcode projects cannot break the search.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

uuid_set() {
  dwarfdump --uuid "$1" 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' '
}

find_binary() {
  local name="$1"
  local candidates=(
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-Frameworks}/${name}.framework/Versions/A/${name}"
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-Frameworks}/${name}.framework/${name}"
    "${TARGET_BUILD_DIR:-}/${FULL_PRODUCT_NAME:-}/${name}.app/Contents/Frameworks/${name}.framework/Versions/A/${name}"
    "${TARGET_BUILD_DIR:-}/${FULL_PRODUCT_NAME:-}/Contents/Frameworks/${name}.framework/Versions/A/${name}"
    "${TARGET_BUILD_DIR:-}/${FULL_PRODUCT_NAME:-}/Contents/Frameworks/${name}.framework/${name}"
    "${TARGET_BUILD_DIR:-}/${FULL_PRODUCT_NAME:-}/Frameworks/${name}.framework/${name}"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  # Last resort: search the built product tree.
  if [[ -n "${TARGET_BUILD_DIR:-}" && -d "${TARGET_BUILD_DIR}" ]]; then
    find "${TARGET_BUILD_DIR}" -path "*/${name}.framework/*/${name}" -type f 2>/dev/null | head -1
  fi
}

find_vendored_dsym() {
  local name="$1"
  local pattern="*/${name}.xcframework/*/dSYMs/${name}.framework.dSYM"
  # Prefer package under third_party (vendored prebuilt).
  local found
  found="$(find "${ROOT}/third_party" -path "${pattern}" -type d 2>/dev/null | head -1 || true)"
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return 0
  fi
  # Plugin symlink tree used by Flutter.
  if [[ -d "${SRCROOT:-}/Flutter/ephemeral/.symlinks/plugins" ]]; then
    found="$(find "${SRCROOT}/Flutter/ephemeral/.symlinks/plugins" -path "${pattern}" -type d 2>/dev/null | head -1 || true)"
    if [[ -n "${found}" ]]; then
      echo "${found}"
      return 0
    fi
  fi
  return 1
}

ensure_dsym() {
  local name="$1"
  local dest="${DWARF_DSYM_FOLDER_PATH}/${name}.framework.dSYM"
  local binary
  binary="$(find_binary "${name}" || true)"
  if [[ -z "${binary}" ]]; then
    echo "note: ${name} not embedded in this product — skipping dSYM"
    return 0
  fi

  if [[ -d "${dest}" ]]; then
    local bin_uuids dsym_uuids
    bin_uuids="$(uuid_set "${binary}")"
    dsym_uuids="$(uuid_set "${dest}")"
    if [[ -n "${bin_uuids}" && "${bin_uuids}" == "${dsym_uuids}" ]]; then
      echo "note: ${name} dSYM already present (UUIDs match)"
      return 0
    fi
    rm -rf "${dest}"
  fi

  local vendored=""
  vendored="$(find_vendored_dsym "${name}" || true)"
  if [[ -n "${vendored}" && -d "${vendored}" ]]; then
    # Prefer a vendored dSYM whose UUIDs match this binary.
    local v_uuids b_uuids
    v_uuids="$(uuid_set "${vendored}")"
    b_uuids="$(uuid_set "${binary}")"
    if [[ -n "${b_uuids}" && "${b_uuids}" == "${v_uuids}" ]]; then
      echo "note: copying vendored dSYM for ${name}"
      cp -R "${vendored}" "${dest}"
    else
      echo "note: vendored dSYM UUID mismatch for ${name}; regenerating with dsymutil"
      dsymutil "${binary}" -o "${dest}"
    fi
  else
    echo "note: generating dSYM for stripped prebuilt ${name}"
    dsymutil "${binary}" -o "${dest}"
  fi

  echo "✓ ${name} dSYM → ${dest}"
  dwarfdump --uuid "${dest}" || true
}

# macOS prebuilt
ensure_dsym "lib_llama_cpp_macos"
# iOS prebuilt
ensure_dsym "lib_llama_cpp_ios"
