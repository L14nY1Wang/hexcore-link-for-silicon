#!/usr/bin/env bash
# Rebuild Hexcore Link as a native arm64 app.
#
# The vendor ships an x86_64-only Electron 20 bundle whose main process is V8
# bytecode (index.jsc) bound to x64, so nothing can be reused directly. This
# script pairs the reimplemented main process (main-arm64/index.js) with an
# arm64 Electron runtime and an arm64 rebuild of every native addon.
#
# Usage: ./build-arm64.sh [electron-version]
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f packdir/package.json ] || [ ! -f packdir/dist/preloads/app.cjs ]; then
  echo "packdir/ is missing. Run: node scripts/extract-vendor.js" >&2
  echo "It extracts the resource tree from an installed copy of the vendor app." >&2
  exit 1
fi

APP_NAME="Hexcore Link"
ELECTRON_VERSION="${1:-33.4.11}"
OUT="build/arm64"
VENDOR="$OUT/vendor"
WORK="$OUT/work"

say() { printf '\n== %s\n' "$*"; }

# --- 1. Electron runtime ---------------------------------------------------
say "Electron $ELECTRON_VERSION (arm64)"
mkdir -p "$VENDOR"
if [ ! -d "$VENDOR/Electron.app" ]; then
  curl -fsSL -o "$VENDOR/electron.zip" \
    "https://github.com/electron/electron/releases/download/v$ELECTRON_VERSION/electron-v$ELECTRON_VERSION-darwin-arm64.zip"
  unzip -q "$VENDOR/electron.zip" -d "$VENDOR"
  rm -f "$VENDOR/electron.zip"
fi

# --- 2. native addons ------------------------------------------------------
# HID and uiohook get arm64 replacements via scripts/build-native.sh;
# better-sqlite3 is rebuilt below against the Electron ABI because it uses NAN.
say "native addons"
./scripts/build-native.sh
if [ ! -f "$WORK/sqlite/node_modules/better-sqlite3/build/Release/better_sqlite3.node" ]; then
  mkdir -p "$WORK/sqlite"
  ( cd "$WORK/sqlite"
    npm init -y >/dev/null
    npm install better-sqlite3@12 --ignore-scripts --no-audit --no-fund >/dev/null )
fi
# The vendor database is encrypted with SQLite3 Multiple Ciphers (default
# chacha20). Stock better-sqlite3 cannot read it, so swap its bundled SQLite
# for the same codec amalgamation the vendor used. An existing build is only
# reusable if it was made from the swapped source: a stock .node opens the
# database with SQLITE_NOTADB and the UI never renders.
if [ ! -f "$WORK/sqlite/node_modules/better-sqlite3/build/Release/better_sqlite3.node" ] ||
   ! grep -q SQLITE3MC "$WORK/sqlite/node_modules/better-sqlite3/deps/sqlite3/sqlite3.c" 2>/dev/null; then
  ( cd "$WORK/sqlite"
    curl -fsSL -o mc.zip \
      "https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.5.5/sqlite3mc-1.5.5-sqlite-3.40.1-amalgamation.zip"
    unzip -q -o mc.zip -d mc
    B="node_modules/better-sqlite3"
    cp mc/sqlite3mc_amalgamation.c "$B/deps/sqlite3/sqlite3.c"
    cp mc/sqlite3mc_amalgamation.h "$B/deps/sqlite3/sqlite3.h"
    # 3.40.1 predates these fields/codes; drop the ones it cannot compile.
    sed -i '' "/'SQLITE_OMIT_SHARED_CACHE',/d;/'SQLITE_OMIT_DEPRECATED',/d" "$B/deps/defines.gypi"
    python3 - "$B" <<'PY2'
import re, sys
b = sys.argv[1]
c = b + '/src/util/constants.cpp'
s = open(c).read()
for n in ('SQLITE_IOERR_IN_PAGE', 'SQLITE_NOTICE_RBU', 'SQLITE_CANTOPEN_SYMLINK'):
    line = f'\t\tSetCode(isolate, {n}, "{n}");\n'
    s = s.replace(line, f'#ifdef {n}\n{line}#endif\n')
open(c, 'w').write(s)
t = b + '/src/util/custom-table.cpp'
s = open(t).read()
s = s.replace('\tNULL,                         /* xShadowName */\n\tNULL                          /* xIntegrity */\n};',
              '\tNULL                          /* xShadowName */\n};')
open(t, 'w').write(s)
PY2
    ( cd "$B" && npx --yes node-gyp rebuild --target="$ELECTRON_VERSION" --arch=arm64 \
        --dist-url=https://electronjs.org/headers >/dev/null )
  )
fi
cp "$WORK/sqlite/node_modules/better-sqlite3/build/Release/better_sqlite3.node" \
   packdir/node_modules/better-sqlite3/build/Release/better_sqlite3.node

# --- 3. bundle -------------------------------------------------------------
say "bundle"
cp main-arm64/index.js packdir/dist/main/index.js
cp main-arm64/compat-preload.js packdir/dist/main/compat-preload.js
rm -rf "$OUT/$APP_NAME.app"
cp -R "$VENDOR/Electron.app" "$OUT/$APP_NAME.app"
BUNDLE="$OUT/$APP_NAME.app"

mv "$BUNDLE/Contents/MacOS/Electron" "$BUNDLE/Contents/MacOS/$APP_NAME"
for helper in "$BUNDLE/Contents/Frameworks/"*.app; do
  base=$(basename "$helper")
  renamed="${base/Electron/$APP_NAME}"
  [ "$base" != "$renamed" ] && mv "$helper" "$BUNDLE/Contents/Frameworks/$renamed"
  old="$BUNDLE/Contents/Frameworks/$renamed/Contents/MacOS/${base%.app}"
  [ -f "$old" ] && mv "$old" "$BUNDLE/Contents/Frameworks/$renamed/Contents/MacOS/${renamed%.app}"
done

python3 - "$BUNDLE" <<'PY'
import plistlib, sys
bundle = sys.argv[1]
pl = f'{bundle}/Contents/Info.plist'
info = plistlib.load(open(pl, 'rb'))
info.update({
    'CFBundleIdentifier': 'xyz.hexcore.hexcore-link',
    'CFBundleName': 'Hexcore Link',
    'CFBundleDisplayName': 'Hexcore Link',
    'CFBundleExecutable': 'Hexcore Link',
    'CFBundleShortVersionString': '2.5.9',
    'CFBundleVersion': '2.5.9',
    'CFBundleIconFile': 'icon.icns',
    'LSMinimumSystemVersion': '10.15',
})
info.pop('ElectronAsarIntegrity', None)
plistlib.dump(info, open(pl, 'wb'))
PY

rm -f "$BUNDLE/Contents/Resources/app.asar"* "$BUNDLE/Contents/Resources/default_app.asar"
npx --yes @electron/asar@4.3.1 pack packdir "$BUNDLE/Contents/Resources/app.asar" --unpack-dir "node_modules" >/dev/null
# asar writes the unpacked tree next to the archive it creates; keep it there.
if [ -d "$BUNDLE/Contents/Resources/app.asar.unpacked" ]; then
  :
else
  echo "asar produced no unpacked tree" >&2
  exit 1
fi
cp packdir/icon.icns "$BUNDLE/Contents/Resources/icon.icns"

python3 - "$BUNDLE" <<'PY'
import hashlib, plistlib, struct, sys
bundle = sys.argv[1]
asar = f'{bundle}/Contents/Resources/app.asar'
data = open(asar, 'rb').read()
_, header_size, _, _ = struct.unpack('<4I', data[:16])
digest = hashlib.sha256(data[16:16 + header_size - 8]).hexdigest()
pl = f'{bundle}/Contents/Info.plist'
info = plistlib.load(open(pl, 'rb'))
info['ElectronAsarIntegrity'] = {'Resources/app.asar': {'hash': digest, 'algorithm': 'SHA256'}}
plistlib.dump(info, open(pl, 'wb'))
PY

# --- 4. sign ---------------------------------------------------------------
say "sign"
rm -rf "$BUNDLE/Contents/_CodeSignature"
codesign --force --deep --sign - --entitlements ent.plist "$BUNDLE" >/dev/null 2>&1

say "done: $BUNDLE"
