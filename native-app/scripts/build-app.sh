#!/usr/bin/env bash
# Package the SwiftUI app into "Hexcore Link.app".
# Usage: ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Hexcore Link.app"
BIN=".build/release/HexcoreLink"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HexcoreLink"

if [ -f icon.icns ]; then
  cp icon.icns "$APP/Contents/Resources/icon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>HexcoreLink</string>
  <key>CFBundleIdentifier</key><string>xyz.hexcore.hexcore-link.native</string>
  <key>CFBundleName</key><string>Hexcore Link</string>
  <key>CFBundleDisplayName</key><string>Hexcore Link</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>icon.icns</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

rm -rf "$APP/Contents/_CodeSignature"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $APP"
