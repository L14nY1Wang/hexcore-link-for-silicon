# Hexcore Link for Silicon

Unofficial Apple Silicon (arm64) build of **Hexcore Link 2.5.9**, the
configuration app for Hexcore / ObinsLab keyboards (Anne Pro, etc.).

## Why this exists

The vendor app is an x86_64 Electron 20 bundle:

- its main process is `index.jsc`, V8 bytecode bound to x64, so Rosetta cannot
  load it on Apple Silicon;
- its native addons are x86_64 bundles.

This repository reimplements the main-process IPC contract the vendor preloads
and renderers expect, and pairs it with an arm64 Electron runtime and arm64
native addons.

## What works

- Device discovery and HID traffic (Liana protocol), layouts, lighting, macros
- Settings, including app-wide language (en / zh-CN) and theme switching
- Tray, window state, display listing, notifications
- The vendor's encrypted database (SQLite3 Multiple Ciphers)

## Known limitations

- DDC/CI external-display brightness is stubbed (no-ops)
- Auto-update is disabled
- Sentry error reports are logged locally instead of being sent
- Tested only against Hexcore Link 2.5.9 on macOS 15/26 with an Anne Pro 2D

## Requirements

- Apple Silicon Mac, macOS 11+
- Xcode Command Line Tools
- Node.js 18+
- A legally obtained copy of Hexcore Link 2.5.9 installed in `/Applications`

## Build

```sh
node scripts/extract-vendor.js   # unpack the vendor tree into packdir/
./build-arm64.sh                 # Electron 33.4.11 arm64 + addons + bundle
open "build/arm64/Hexcore Link.app"
```

The script is idempotent: downloads and native builds are cached under
`build/arm64/`. The vendor tree in `packdir/` is not part of this repository.

## Layout

| Path | Purpose |
| --- | --- |
| `main-arm64/index.js` | Main-process reimplementation |
| `main-arm64/compat-preload.js` | Restores `ipcRenderer.sendTo` (removed in Electron 28), used by the vendor preloads for window-to-window messages |
| `native/liana-hid/` | Clean-room arm64 N-API addon for the keyboard HID protocol, built on hidapi |
| `scripts/extract-vendor.js` | Unpacks the vendor `app.asar` (legacy header) into `packdir/` |
| `scripts/build-native.sh` | Installs the arm64 uiohook prebuild and builds `liana-hid` |
| `build-arm64.sh` | Electron runtime, better-sqlite3 + sqlite3mc, asar packaging, ad-hoc signing |

## Disclaimer

Not affiliated with Taicang Zhigengniao Information Technology Co., Ltd.,
Hexcore, or ObinsLab. This repository contains no vendor code or assets; the
vendor application is read from the user's own installation. Use at your own
risk.

## License

MIT for the code in this repository. `native/liana-hid/hidapi` is
BSD-3-Clause (see the license files in that directory). The vendor
application and its assets remain the property of their owners.
