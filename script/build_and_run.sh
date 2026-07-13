#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Canopy"
BUNDLE_ID="com.discm.Canopy"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${TMPDIR%/}/CanopyWorkspace-$UID"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
INSTALL_BUNDLE="/Applications/$APP_NAME.app"

case "$MODE" in
  --debug|debug)
    CONFIGURATION="Debug"
    ;;
  run|--logs|logs|--telemetry|telemetry|--verify|verify)
    CONFIGURATION="Release"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

BUILD_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
rsync -a \
  --exclude .git \
  --exclude .build \
  --exclude DerivedData \
  --exclude Canopy.xcodeproj \
  "$ROOT_DIR/" "$BUILD_ROOT/"

xcodegen generate --spec "$BUILD_ROOT/project.yml" --project "$BUILD_ROOT"
xcodebuild \
  -project "$BUILD_ROOT/Canopy.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "$CONFIGURATION" == "Release" ]]; then
  rm -rf "$INSTALL_BUNDLE"
  /usr/bin/ditto "$BUILD_BUNDLE" "$INSTALL_BUNDLE"
  /usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$ROOT_DIR/Canopy/Resources/Canopy.entitlements" \
    "$INSTALL_BUNDLE"
  APP_BUNDLE="$INSTALL_BUNDLE"
else
  APP_BUNDLE="$BUILD_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    PID="$(pgrep -x -n "$APP_NAME")"
    PROCESS_PATH="$(ps -p "$PID" -o comm=)"
    [[ "$PROCESS_PATH" == "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]
    ;;
esac
