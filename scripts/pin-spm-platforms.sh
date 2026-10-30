#!/usr/bin/env bash
#
# Pins the generated plugin Swift package to the Runner deployment targets.
#
# `flutter pub get` regenerates FlutterGeneratedPluginSwiftPackage at the tool
# defaults (.iOS("15.0") / .macOS("12.0")), but erebrus_mlx and erebrus_speech
# require iOS 17 / macOS 14 like Runner, so Swift package resolution fails on a
# fresh checkout. Run after every `flutter pub get` and before Apple builds.
#
#   scripts/pin-spm-platforms.sh            # both platforms
#   scripts/pin-spm-platforms.sh ios        # one platform
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_MIN="${EREBRUS_IOS_MIN:-17.0}"
MACOS_MIN="${EREBRUS_MACOS_MIN:-14.0}"

pin() {
  local platform="$1" token="$2" version="$3"
  local pkg="${ROOT_DIR}/${platform}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
  if [[ ! -f "${pkg}" ]]; then
    echo "▸ ${platform}: no generated plugin package (run flutter pub get first)"
    return 0
  fi
  if grep -qF ".${token}(\"${version}\")" "${pkg}"; then
    echo "✓ ${platform}: plugin package already at ${version}"
    return 0
  fi
  /usr/bin/perl -pi -e "s/\\.${token}\\(\"[0-9.]+\"\\)/.${token}(\"${version}\")/g" "${pkg}"
  grep -qF ".${token}(\"${version}\")" "${pkg}" \
    || { echo "✗ ${platform}: could not pin ${pkg}" >&2; exit 1; }
  echo "✓ ${platform}: plugin package pinned → ${version}"
}

targets=("$@")
[[ "${#targets[@]}" -gt 0 ]] || targets=(ios macos)
for target in "${targets[@]}"; do
  case "${target}" in
    ios) pin ios iOS "${IOS_MIN}" ;;
    macos) pin macos macOS "${MACOS_MIN}" ;;
    *) echo "Usage: $0 [ios] [macos]" >&2; exit 1 ;;
  esac
done
