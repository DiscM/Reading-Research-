#!/usr/bin/env bash
#
# Builds a distributable, double-clickable macOS .app bundle for
# Research Paper Reader from the Swift Package.
#
# Usage:
#   ./scripts/build-app.sh            # release build into ./dist/Research Paper Reader.app
#   ./scripts/build-app.sh --open     # also open the built app
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EXECUTABLE="ResearchPaperReader"
APP_NAME="Research Paper Reader"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
BUILD_DIR="$ROOT/.iconbuild"

# Build each architecture in its own invocation, then lipo them together.
# (Combining --arch arm64 --arch x86_64 in one swift build invocation trips
# the prebuilt module cache on some toolchains, so we build them separately.)
UNIVERSAL_BIN="$BUILD_DIR/$EXECUTABLE-universal"
mkdir -p "$BUILD_DIR"
SLICES=()

for ARCH in arm64 x86_64; do
    echo "==> Building release binary ($ARCH)"
    if swift build -c release --arch "$ARCH"; then
        SLICE="$(swift build -c release --arch "$ARCH" --show-bin-path)/$EXECUTABLE"
        if [[ -f "$SLICE" ]]; then
            SLICES+=("$SLICE")
        else
            echo "warning: $ARCH binary not found at $SLICE; skipping" >&2
        fi
    else
        echo "warning: $ARCH build failed; skipping that slice" >&2
    fi
done

if [[ ${#SLICES[@]} -eq 0 ]]; then
    echo "error: no architecture slices built successfully" >&2
    exit 1
fi

echo "==> Merging ${#SLICES[@]} slice(s) into a universal binary"
lipo -create "${SLICES[@]}" -output "$UNIVERSAL_BIN"
BIN_PATH="$UNIVERSAL_BIN"
echo "    architectures: $(lipo -archs "$BIN_PATH")"

echo "==> Generating app icon"
mkdir -p "$BUILD_DIR"
ICON_MASTER="$BUILD_DIR/icon-master.png"
swift "$ROOT/scripts/make-icon.swift" "$ICON_MASTER"

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
declare -a SIZES=(16 32 64 128 256 512 1024)
for s in "${SIZES[@]}"; do
    sips -z "$s" "$s" "$ICON_MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
# Retina @2x variants expected by iconutil
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
# Trim to the exact filenames iconutil wants
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

echo "==> Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE"
cp "$ROOT/AppResources/Info.plist" "$CONTENTS/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$RES_DIR/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "warning: ad-hoc codesign failed; app may need right-click > Open on first launch"

# Refresh Launch Services / icon cache for this bundle
touch "$APP"

echo "==> Done: $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
