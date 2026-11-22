#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_NAME="TokenCodexInfo"
APP_DISPLAY_NAME="Token Codex Info"
BUNDLE_ID="com.vibecode.TokenCodexInfo"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "VERSION must be X.Y.Z and BUILD_NUMBER must be numeric." >&2
  exit 2
fi

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_PATH="$DIST_DIR/$EXECUTABLE_NAME-$VERSION-universal.dmg"
ZIP_PATH="$DIST_DIR/$EXECUTABLE_NAME-$VERSION-universal.zip"

mkdir -p "$DIST_DIR"

bash "$ROOT_DIR/script/prepare_artwork.sh"
DMG_PYTHON="$ROOT_DIR/.build/dmg-tools/bin/python"
if [[ ! -x "$DMG_PYTHON" ]] || ! "$DMG_PYTHON" -c 'import dmgbuild, ds_store, mac_alias' >/dev/null 2>&1; then
  python3 -m venv "$ROOT_DIR/.build/dmg-tools"
  "$DMG_PYTHON" -m pip install -r "$ROOT_DIR/script/requirements-dmg.txt"
fi

swift build -c release --arch arm64 --arch x86_64 "$@"
BUILD_BINARY="$(swift build -c release --arch arm64 --arch x86_64 "$@" --show-bin-path)/$EXECUTABLE_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Release binary not found at $BUILD_BINARY" >&2
  exit 1
fi

lipo "$BUILD_BINARY" -verify_arch arm64
lipo "$BUILD_BINARY" -verify_arch x86_64

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
ditto "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"

# Remove debugging metadata that embeds the builder's absolute home paths.
# Do this before signing; stripping an already signed executable invalidates it.
/usr/bin/strip -S "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
plutil -lint "$INFO_PLIST"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

"$ROOT_DIR/.build/dmg-tools/bin/dmgbuild" \
  -s "$ROOT_DIR/script/dmg_settings.py" \
  -D "app=$APP_BUNDLE" \
  -D "background=$ROOT_DIR/Assets/dmg-background.png" \
  "$APP_DISPLAY_NAME" "$DMG_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > SHA256SUMS.txt
)

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$DIST_DIR/SHA256SUMS.txt"
bash "$ROOT_DIR/script/prepare_download_page.sh"
