#!/usr/bin/env zsh
set -euo pipefail

download_if_missing=0
if [[ "${1:-}" == "--download" ]]; then
  download_if_missing=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--download]" >&2
  exit 1
fi

find_runtime_id() {
  xcrun simctl list runtimes | awk '
    /^iOS / && $0 !~ /unavailable/ {
      if (match($0, /com\.apple\.CoreSimulator\.SimRuntime\.iOS[-0-9A-Za-z.]*/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  '
}

find_runtime_name() {
  xcrun simctl list runtimes | awk '
    /^iOS / && $0 !~ /unavailable/ {
      if (match($0, /^iOS [0-9.]+/)) {
        print substr($0, RSTART, RLENGTH)
      } else {
        print $1 " " $2
      }
      exit
    }
  '
}

runtime_id="$(find_runtime_id || true)"
if [[ -n "${runtime_id}" ]]; then
  echo "iOS Simulator runtime is available: ${runtime_id}"
  exit 0
fi

if [[ "${download_if_missing}" -ne 1 ]]; then
  echo "No iOS Simulator runtime found. Run: make setup-ios-runtime" >&2
  exit 1
fi

echo "No iOS Simulator runtime found. Downloading platform runtime..."
xcodebuild -downloadPlatform iOS

runtime_id="$(find_runtime_id || true)"
if [[ -z "${runtime_id}" ]]; then
  echo "Failed to detect iOS Simulator runtime after download." >&2
  exit 1
fi

runtime_name="$(find_runtime_name || true)"
echo "iOS Simulator runtime installed: ${runtime_name} (${runtime_id})"
