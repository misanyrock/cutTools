#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=CutTools
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/cuttools-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "$PWD/.build/cache"
BIN="$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" --show-bin-path)/$APP_NAME"
BUNDLE="$PWD/dist/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>CutTools</string><key>CFBundleIdentifier</key><string>local.cuttools.app</string><key>CFBundleIconFile</key><string>AppIcon.icns</string><key>CFBundleName</key><string>CutTools</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
/usr/bin/codesign --force --deep --sign - "$BUNDLE"
case "${1:-run}" in
  --build) ;;
  run) open -n "$BUNDLE" ;;
  --verify) open -n "$BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug) lldb -- "$BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|--telemetry) open -n "$BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "CutTools"' ;;
  *) exit 2 ;;
esac
