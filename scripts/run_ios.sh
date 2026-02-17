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
device_name="${IOS_DEVICE_NAME:-iPhone 17}"
device_type_identifier="${IOS_DEVICE_TYPE_IDENTIFIER:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}"

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

device_udid="$(xcrun simctl list devices \
  | awk -v target_name="${device_name}" '
      $0 ~ "^[[:space:]]*" target_name " \\(" && $0 !~ /unavailable/ {
        if (match($0, /\(([0-9A-F-]{36})\)/)) {
          print substr($0, RSTART + 1, RLENGTH - 2)
          exit
        }
      }
    ' || true)"

if [[ -z "${device_udid}" ]]; then
  echo "Creating simulator device: ${device_name} (${device_type_identifier})"
  device_udid="$(xcrun simctl create "${device_name}" "${device_type_identifier}" "${runtime_id}")"
fi

xcrun simctl shutdown all >/dev/null 2>&1 || true
open -a Simulator >/dev/null 2>&1 || true
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
xcrun simctl launch "${device_udid}" "${bundle_id}"
