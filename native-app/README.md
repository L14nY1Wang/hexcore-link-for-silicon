# Hexcore Link — native (SwiftUI)

A lightweight Apple Silicon rewrite of the Electron app. This is the
`swift-native` branch of `hexcore-link-for-silicon`.

| | Electron port | Native |
| --- | --- | --- |
| Bundle size | ~260 MB | < 5 MB |
| Memory | ~600 MB | ~80 MB |
| Startup | 1–2 s | < 0.3 s |

## Status

- [x] HID transport (Liana protocol, hidapi) — `CLiana`
- [x] Device discovery, battery, firmware, uptime, UDID
- [x] Encrypted vendor database (SQLite3 Multiple Ciphers) — `CSQLiteMC`
- [ ] Layout editor
- [ ] Lighting effects
- [ ] Macros
- [ ] Audio visualizer / wireless / firmware update

## Build

```sh
./scripts/build-app.sh          # -> build/Hexcore Link.app
open "build/Hexcore Link.app"
```

`icon.icns` is not in the repository; copy it from a local installation of the
vendor app into `native-app/icon.icns` to get the Dock icon.

## Probes

```sh
swift run LianaProbe   # enumerate keyboards and query firmware/battery
swift run DbProbe      # open the vendor database read-only and dump counts
```

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CLiana` | Liana protocol over hidapi (C) |
| `Sources/CSQLiteMC` | SQLite3 Multiple Ciphers amalgamation |
| `Sources/HexcoreLink` | SwiftUI app + database wrapper |
| `Sources/LianaProbe` | Hardware smoke test |
| `Sources/DbProbe` | Database smoke test |

## Notes

- The vendor database key is extracted from the installed app at runtime in the
  Electron version; the native build embeds it (see `Database.swift`).
- Requires macOS 14+.
