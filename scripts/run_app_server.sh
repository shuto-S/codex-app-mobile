#!/usr/bin/env zsh
set -euo pipefail

listen_url="${CODEX_APP_SERVER_URL:-ws://127.0.0.1:18081}"

case "${listen_url}" in
  ws://*|wss://*|stdio://*|unix://*|off)
    ;;
  *)
    echo "Invalid CODEX_APP_SERVER_URL: ${listen_url}" >&2
    echo "Expected ws://, wss://, stdio://, unix://, or off." >&2
    exit 1
    ;;
esac

echo "Starting codex app-server on ${listen_url}"
echo "Keep this process running while the iOS app is connected."
exec codex app-server --listen "${listen_url}"
