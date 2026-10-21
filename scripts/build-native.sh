#!/usr/bin/env bash
# Build/install the arm64 native addons the vendor preloads load at runtime:
#   @hexcore/node-hid  -> native/liana-hid (clean-room reimplementation)
#   uiohook-napi       -> prebuilt darwin-arm64 binary from its npm tarball
# better-sqlite3 is built separately in build-arm64.sh because it needs the
# Electron ABI and the SQLite3 Multiple Ciphers amalgamation.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d packdir/node_modules ]; then
  echo "packdir/ is missing. Run: node scripts/extract-vendor.js" >&2
  exit 1
fi

WORK="build/arm64/work"
mkdir -p "$WORK"

# --- uiohook-napi ----------------------------------------------------------
# Its npm tarball ships prebuilds for every supported platform; copy the arm64
# one over the x64 prebuild that comes out of the vendor archive.
UIO="$WORK/uiohook"
if [ ! -d "$UIO/package/prebuilds/darwin-arm64" ]; then
  mkdir -p "$UIO"
  ( cd "$UIO"
    npm pack uiohook-napi@1.3.0 --silent >/dev/null
    tar -xzf uiohook-napi-1.3.0.tgz )
fi
PREBUILDS="packdir/node_modules/uiohook-napi/prebuilds"
mkdir -p "$PREBUILDS"
rm -rf "$PREBUILDS/darwin-x64"
cp -R "$UIO/package/prebuilds/darwin-arm64" "$PREBUILDS/"

# --- liana-hid -------------------------------------------------------------
# The vendor addon is x86_64-only; native/liana-hid rebuilds the same N-API
# surface for arm64.
( cd native/liana-hid
  npm install --no-audit --no-fund --silent
  npx --yes node-gyp rebuild >/dev/null )
mkdir -p packdir/node_modules/@hexcore/node-hid/out/Release
cp native/liana-hid/build/Release/HID.node \
   packdir/node_modules/@hexcore/node-hid/out/Release/HID.node

# node-hid is listed as a dependency but never required at runtime; drop its
# x64 payload so no x86 code ships.
rm -rf packdir/node_modules/node-hid/bin/darwin-x64-82

echo "native addons ready"
