#!/bin/bash
# macOS's built-in Bash 3.2 is sufficient. No remote code or package manager.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=simulator
TEAM=""
BUNDLE=""
DEVICE=""
RUN_TESTS=1
OPEN_UI=1
DOWNLOAD_RUNTIME=1

usage() {
  cat <<'USAGE'
Worklog setup and build
  bash Build-Worklog.command [options]

  --mode simulator|device|archive  Default: test, build and launch Simulator
  --team ABC123DE45               Apple development team ID (saved locally)
  --bundle-id au.yourname.worklog Unique app identifier (saved locally)
  --device IPHONE_UDID            Paired iPhone hardware UDID (from Xcode)
  --no-tests                     Explicitly skip simulator XCTest gate
  --no-open                      Do not open Xcode or Simulator windows
  --no-download                  Fail instead of downloading a missing iOS runtime
  --help                         Show this help

Device and archive modes require your Apple account in Xcode and a team ID.
The script never uploads to App Store Connect. Logs and products are in build/.
USAGE
}
die() { printf '\nWorklog: %s\n' "$*" >&2; exit 1; }
need_value() { [ "$#" -ge 2 ] && [ -n "$2" ] || die "Missing value for $1"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) need_value "$@"; MODE="$2"; shift 2 ;;
    --team) need_value "$@"; TEAM="$2"; shift 2 ;;
    --bundle-id) need_value "$@"; BUNDLE="$2"; shift 2 ;;
    --device) need_value "$@"; DEVICE="$2"; shift 2 ;;
    --no-tests) RUN_TESTS=0; shift ;;
    --no-open) OPEN_UI=0; shift ;;
    --no-download) DOWNLOAD_RUNTIME=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1. Use --help." ;;
  esac
done
case "$MODE" in simulator|device|archive) ;; *) die "Mode must be simulator, device or archive." ;; esac
[ "$(uname -s)" = Darwin ] || die "Building iOS requires a Mac with full Xcode. The source files can be read on any computer."

# Select Xcode for this process only. Do not alter the Mac's system-wide setting.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  SELECTED="$(xcode-select -p 2>/dev/null || true)"
  if [ -d "$SELECTED/Platforms/iPhoneOS.platform" ]; then
    export DEVELOPER_DIR="$SELECTED"
  elif [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    die "Install full Xcode from the Mac App Store, open it once and install iOS support. Command Line Tools alone are insufficient. Then rerun this command."
  fi
fi
xcodebuild -version || die "Xcode is not ready. Open Xcode and complete its first-launch setup."
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || die "Open Xcode once to review its licence and finish installing components, then rerun."
xcrun --sdk iphoneos --show-sdk-path >/dev/null || die "Install iOS platform support in Xcode Settings > Components."

mkdir -p "$ROOT/build"
if ! mkdir "$ROOT/build/.worklog-build-lock" 2>/dev/null; then
  die "Another build may be running. If it stopped, remove build/.worklog-build-lock and rerun."
fi
trap 'rmdir "$ROOT/build/.worklog-build-lock" 2>/dev/null || true' EXIT
LOG="$ROOT/build/build-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee -a "$LOG") 2>&1
trap 'rc=$?; printf "\nBuild stopped (exit %s). Read %s\n" "$rc" "$LOG"; exit "$rc"' ERR
printf '\nWorklog project: %s\nBuild mode: %s\n' "$ROOT" "$MODE"

LOCAL="$ROOT/Config/Local.xcconfig"
if [ -f "$LOCAL" ]; then
  [ -n "$BUNDLE" ] || BUNDLE="$(sed -n 's/^WORKLOG_BUNDLE_ID *= *\([^ ]*\) *$/\1/p' "$LOCAL" | head -n 1)"
  [ -n "$TEAM" ] || TEAM="$(sed -n 's/^WORKLOG_TEAM *= *\([^ ]*\) *$/\1/p' "$LOCAL" | head -n 1)"
fi
if [ -z "$BUNDLE" ]; then
  TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-12)"
  BUNDLE="au.worklog.personal.w$TOKEN"
fi
[[ "$BUNDLE" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$ ]] || die "Use a reverse-domain bundle identifier such as au.yourname.worklog."
if [ -n "$TEAM" ]; then
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || die "The Apple team ID must contain 10 uppercase letters/numbers."
fi
if [ "$MODE" != simulator ]; then
  [ -n "$TEAM" ] || die "Add your Apple account in Xcode Settings > Accounts, then rerun with --team YOURTEAMID. See Docs/QUICK-START.md."
fi
if [ "$MODE" = device ] && [ -z "$DEVICE" ]; then
  xcrun xctrace list devices
  die "Connect, trust and unlock your iPhone; enable Developer Mode. Rerun with --device followed by its hardware UDID (Xcode Devices > Identifier, or physical device list above)."
fi
CONFIG_TMP="$(mktemp "$ROOT/Config/Local.xcconfig.XXXXXX")"
printf '// Local signing configuration; keep the same bundle ID for upgrades.\nWORKLOG_BUNDLE_ID = %s\nWORKLOG_TEAM = %s\n' "$BUNDLE" "$TEAM" > "$CONFIG_TMP"
mv "$CONFIG_TMP" "$LOCAL"

plutil -lint "$ROOT/Worklog.xcodeproj/project.pbxproj" "$ROOT/Worklog/Info.plist" "$ROOT/Worklog/PrivacyInfo.xcprivacy"
PROJECT=( -project "$ROOT/Worklog.xcodeproj" -scheme Worklog )
if [ "$RUN_TESTS" = 1 ] || [ "$MODE" = simulator ]; then
  xcrun simctl list --json > "$ROOT/build/simulators.json"
  if SIMULATOR="$(xcrun swift "$ROOT/Scripts/SelectSimulator.swift" "$ROOT/build/simulators.json")"; then
    SELECT_STATUS=0
  else
    SELECT_STATUS=$?
  fi
  if [ "$SELECT_STATUS" = 3 ] && [ "$DOWNLOAD_RUNTIME" = 1 ]; then
    printf '\nDownloading the iOS Simulator runtime from Apple. This may be several GB.\n'
    xcodebuild -downloadPlatform iOS
    xcrun simctl list --json > "$ROOT/build/simulators.json"
    SIMULATOR="$(xcrun swift "$ROOT/Scripts/SelectSimulator.swift" "$ROOT/build/simulators.json")"
  elif [ "$SELECT_STATUS" != 0 ]; then
    die "Simulator selection failed. Install an iOS 17+ runtime in Xcode Settings and retry."
  fi
  [[ "$SIMULATOR" =~ ^[A-Fa-f0-9-]{36}$ ]] || die "Simulator returned an invalid identifier."
  # bootstatus --boot (short form -b) also starts a shut-down simulator.
  xcrun simctl bootstatus "$SIMULATOR" -b
  if [ "$OPEN_UI" = 1 ]; then open "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$SIMULATOR"; fi
  SIM_ARGS=( -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR" -derivedDataPath "$ROOT/build/Simulator" CODE_SIGNING_ALLOWED=NO )
  if [ "$RUN_TESTS" = 1 ]; then
    RESULT="$ROOT/build/Tests-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
    xcodebuild "${PROJECT[@]}" "${SIM_ARGS[@]}" -parallel-testing-enabled NO -resultBundlePath "$RESULT" test
  else
    printf '\nSimulator XCTest was explicitly skipped.\n'
    xcodebuild "${PROJECT[@]}" "${SIM_ARGS[@]}" build
  fi
fi

case "$MODE" in
  simulator)
    APP="$ROOT/build/Simulator/Build/Products/Debug-iphonesimulator/Worklog.app"
    [ -d "$APP" ] || die "Build finished without the expected Simulator app."
    xcrun simctl install "$SIMULATOR" "$APP"
    xcrun simctl launch "$SIMULATOR" "$BUNDLE"
    printf '\nWorklog is running in the Simulator. Camera, Siri and real GPS still need iPhone testing.\n'
    ;;
  device)
    xcodebuild "${PROJECT[@]}" -configuration Debug -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$ROOT/build/Device" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
    APP="$ROOT/build/Device/Build/Products/Debug-iphoneos/Worklog.app"
    xcrun devicectl device install app --device "$DEVICE" "$APP"
    xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
    printf '\nWorklog installed and launched on the selected iPhone. Complete the permission and road tests in Docs/DEVICE-TESTS.md.\n'
    ;;
  archive)
    ARCHIVE="$ROOT/build/Worklog-$(date +%Y%m%d-%H%M%S)-$$.xcarchive"
    xcodebuild "${PROJECT[@]}" -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$ROOT/build/Archive" -allowProvisioningUpdates archive
    printf '\nSigned archive created: %s\nOpen it in Xcode Organizer to validate and distribute with your developer account. No upload was performed.\n' "$ARCHIVE"
    if [ "$OPEN_UI" = 1 ]; then open "$ARCHIVE"; fi
    ;;
esac
if [ "$OPEN_UI" = 1 ]; then open "$ROOT/Worklog.xcodeproj"; fi
printf '\nCompleted. Project: %s\nLog: %s\n' "$ROOT" "$LOG"
