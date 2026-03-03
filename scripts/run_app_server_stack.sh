#!/usr/bin/env zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

app_listen_host="${APP_SERVER_LISTEN_HOST:-127.0.0.1}"
app_port="${APP_SERVER_PORT:-18081}"

app_listen_url="ws://${app_listen_host}:${app_port}"

logs_dir="${project_root}/.build/logs"
mkdir -p "${logs_dir}"
app_log="${logs_dir}/app-server.log"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

assert_port_available() {
  local port="$1"
  local label="$2"
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "${label} port is already in use: ${port}" >&2
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >&2 || true
    exit 1
  fi
}

cleanup() {
  local exit_code=$?
  trap - INT TERM EXIT
  if [[ -n "${app_pid:-}" ]] && kill -0 "${app_pid}" >/dev/null 2>&1; then
    kill "${app_pid}" >/dev/null 2>&1 || true
  fi
  wait "${app_pid:-}" >/dev/null 2>&1 || true
  exit "${exit_code}"
}

require_command codex

assert_port_available "${app_port}" "App server"

: > "${app_log}"

codex app-server --listen "${app_listen_url}" >>"${app_log}" 2>&1 &
app_pid=$!

sleep 0.4
if ! kill -0 "${app_pid}" >/dev/null 2>&1; then
  echo "Failed to start codex app-server. See log: ${app_log}" >&2
  tail -n 60 "${app_log}" >&2 || true
  exit 1
fi

trap cleanup INT TERM EXIT

echo "App server is running."
echo "  app-server: ${app_listen_url}"
echo "  iOS URL:    ws://<reachable-ip>:${app_port}"
echo "  logs:       ${app_log}"
echo "Press Ctrl+C to stop."

while true; do
  if ! kill -0 "${app_pid}" >/dev/null 2>&1; then
    echo "codex app-server stopped unexpectedly. See: ${app_log}" >&2
    exit 1
  fi
  sleep 1
done
