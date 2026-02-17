#!/usr/bin/env zsh
set -euo pipefail

action="${1:-run}"
if [[ "${action}" != "run" && "${action}" != "test" ]]; then
  echo "Usage: $0 [run|test]" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
project_path="${project_root}/HelloWorldApp.xcodeproj"
scheme="HelloWorldApp"
bundle_id="com.example.HelloWorldApp"
derived_data_path="${project_root}/.build/DerivedData"
device_name="${IOS_DEVICE_NAME:-HelloWorldApp iPhone 17}"
device_type_identifier="${IOS_DEVICE_TYPE_IDENTIFIER:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}"
lock_dir="${project_root}/.build/locks/run-ios.lock"

mkdir -p "$(dirname "${lock_dir}")"
if ! mkdir "${lock_dir}" 2>/dev/null; then
  echo "Another run-ios/test-ios process is already running." >&2
  exit 1
fi
trap 'rmdir "${lock_dir}" >/dev/null 2>&1 || true' EXIT

"${script_dir}/ensure_ios_runtime.sh"

runtime_id="$(xcrun simctl list runtimes | awk '
  /^iOS / && $0 !~ /unavailable/ {
    if (match($0, /com\.apple\.CoreSimulator\.SimRuntime\.iOS[-0-9A-Za-z.]*/)) {
      print substr($0, RSTART, RLENGTH)
      exit
    }
  }
')"

if [[ -z "${runtime_id}" ]]; then
  echo "No available iOS runtime found." >&2
  exit 1
fi

list_matching_device_udids() {
  xcrun simctl list devices | awk -v target_name="${device_name}" '
      $0 ~ "^[[:space:]]*" target_name " \\(" && $0 !~ /unavailable/ {
        if (match($0, /\(([0-9A-F-]{36})\)/)) {
          print substr($0, RSTART + 1, RLENGTH - 2)
        }
      }
    '
}

device_udid="$(list_matching_device_udids | head -n 1 || true)"

if [[ -z "${device_udid}" ]]; then
  echo "Creating simulator device: ${device_name} (${device_type_identifier})"
  device_udid="$(xcrun simctl create "${device_name}" "${device_type_identifier}" "${runtime_id}")"
fi

duplicate_udids="$(list_matching_device_udids | tail -n +2 || true)"
if [[ -n "${duplicate_udids}" ]]; then
  while IFS= read -r duplicate_udid; do
    [[ -n "${duplicate_udid}" ]] || continue
    xcrun simctl delete "${duplicate_udid}" >/dev/null 2>&1 || true
  done <<< "${duplicate_udids}"
fi

xcrun simctl shutdown all >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "${device_udid}" >/dev/null 2>&1 || true
xcrun simctl boot "${device_udid}" >/dev/null 2>&1 || true

boot_ready=0
for _ in {1..90}; do
  state_line="$(xcrun simctl list devices | grep -F "(${device_udid})" || true)"
  if [[ "${state_line}" == *"(Booted)"* ]]; then
    if xcrun simctl spawn "${device_udid}" launchctl print system >/dev/null 2>&1; then
      boot_ready=1
      break
    fi
  fi
  sleep 2
done

if [[ "${boot_ready}" -ne 1 ]]; then
  echo "Simulator failed to become ready: ${device_udid}" >&2
  exit 1
fi

booted_other_udids="$(xcrun simctl list devices | awk -v keep_udid="${device_udid}" '
  /\(Booted\)/ {
    if (match($0, /\(([0-9A-F-]{36})\)/)) {
      udid = substr($0, RSTART + 1, RLENGTH - 2)
      if (udid != keep_udid) {
        print udid
      }
    }
  }
')"

if [[ -n "${booted_other_udids}" ]]; then
  while IFS= read -r other_udid; do
    [[ -n "${other_udid}" ]] || continue
    xcrun simctl shutdown "${other_udid}" >/dev/null 2>&1 || true
  done <<< "${booted_other_udids}"
fi

booted_count="$(xcrun simctl list devices | awk '/\(Booted\)/ {count++} END {print count + 0}')"
if [[ "${booted_count}" -ne 1 ]]; then
  echo "Expected exactly one booted simulator, found ${booted_count}." >&2
  exit 1
fi

if [[ "${action}" == "test" ]]; then
  xcodebuild \
    -project "${project_path}" \
    -scheme "${scheme}" \
    -configuration Debug \
    -destination "id=${device_udid}" \
    -derivedDataPath "${derived_data_path}" \
    test
  exit 0
fi

xcodebuild \
  -project "${project_path}" \
  -scheme "${scheme}" \
  -configuration Debug \
  -destination "id=${device_udid}" \
  -derivedDataPath "${derived_data_path}" \
  build

app_path="${derived_data_path}/Build/Products/Debug-iphonesimulator/HelloWorldApp.app"
if [[ ! -d "${app_path}" ]]; then
  echo "Built app not found: ${app_path}" >&2
  exit 1
fi

xcrun simctl install "${device_udid}" "${app_path}"
xcrun simctl launch --terminate-running-process --stdout=/dev/null --stderr=/dev/null "${device_udid}" "${bundle_id}"
