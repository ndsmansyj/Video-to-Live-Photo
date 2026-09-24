#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Video to Live Turbo.app"
STAGE="$ROOT/.dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG="$DIST/Video to Live Turbo $VERSION.dmg"

rm -rf "$APP" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/Brand/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

swiftc -parse-as-library \
  "$ROOT/HelperSources/SPPLiveExport/main.swift" \
  -o "$APP/Contents/Resources/spp-live-export" \
  -framework Foundation \
  -framework AVFoundation \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -target arm64-apple-macosx13.0

swiftc -parse-as-library \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/Video to Live Turbo" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -framework UniformTypeIdentifiers \
  -framework ImageIO \
  -target arm64-apple-macosx13.0

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [[ "$#" -gt 0 && "$1" == "--dmg" ]]; then
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/Video to Live Turbo.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create \
    -volname "Video to Live Turbo" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Built: $DMG"
else
  echo "Built: $APP"
fi
