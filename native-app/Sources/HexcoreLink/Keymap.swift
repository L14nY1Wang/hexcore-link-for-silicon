import Foundation

/// A keycode as stored by the vendor app: `(kind << 12) | code`, where `kind`
/// is the renderer's keycode namespace enum
/// (`dist/renderers/index-*.js`: SYSTEM=7 … KEYBOARD=15).
enum Keycode: Equatable {
    /// `KEYBOARD|KC_NO` — key does nothing on this layer.
    case transparent
    /// Plain HID keyboard usage, e.g. 0x29 = Escape.
    case keyboard(UInt8)
    /// HID usage 0xE0…0xE7 (Ctrl/Shift/Alt/GUI).
    case modifier(UInt8)
    /// `HEXCORE|HC_FN0+n` — switch to keyboard layer `n`.
    case layer(Int)
    /// `MACRO|id` — run the macro with this id.
    case macro(UInt16)
    case consumer(UInt16)
    case system(UInt16)
    case mouse(UInt8)
    case gamepad(UInt8)
    case symbol(UInt16)
    case emoji(UInt16)
    /// Any other `HEXCORE` code (backlight, quick-number, wireless slot …).
    case hexcore(UInt8)
    case unknown(Int)

    init(raw: Int) {
        let code = raw & 0xFFF
        switch raw >> 12 {
        case 7: self = .system(UInt16(code))
        case 8: self = .gamepad(UInt8(truncatingIfNeeded: code))
        case 9: self = .mouse(UInt8(truncatingIfNeeded: code))
        case 10 where (0xC0...0xCF).contains(code): self = .layer(code - 0xC0)
        case 10: self = .hexcore(UInt8(truncatingIfNeeded: code))
        case 11: self = .symbol(UInt16(code))
        case 12: self = .emoji(UInt16(code))
        case 13: self = .consumer(UInt16(code))
        case 14: self = .macro(UInt16(code))
        case 15 where code == 0: self = .transparent
        case 15 where (0xE0...0xE7).contains(code): self = .modifier(UInt8(code))
        case 15: self = .keyboard(UInt8(truncatingIfNeeded: code))
        default: self = .unknown(raw)
        }
    }

    var raw: Int {
        switch self {
        case .transparent: return 0xF000
        case .keyboard(let usage), .modifier(let usage): return 0xF000 | Int(usage)
        case .layer(let n): return 0xA000 | (0xC0 + n)
        case .macro(let id): return 0xE000 | Int(id)
        case .consumer(let code): return 0xD000 | Int(code)
        case .system(let code): return 0x7000 | Int(code)
        case .mouse(let code): return 0x9000 | Int(code)
        case .gamepad(let code): return 0x8000 | Int(code)
        case .symbol(let code): return 0xB000 | Int(code)
        case .emoji(let code): return 0xC000 | Int(code)
        case .hexcore(let code): return 0xA000 | Int(code)
        case .unknown(let raw): return raw
        }
    }
}

/// One row of `kbd_keymap`: the four layers (top/fn1/fn2/tap) for a device model.
struct Keymap {
    let id: Int
    let name: String
    let deviceModel: Int
    var top: [Keycode]
    var fn1: [Keycode]
    var fn2: [Keycode]
    var tap: [Keycode]
    let isDefault: Bool
    let isChanged: Bool
    let quickNumber: Int?
    let macro: [Int]

    static func parse(row: [String: Any]) -> Keymap? {
        guard let id = row["id"] as? Int64,
              let name = row["name"] as? String,
              let deviceModel = row["deviceModel"] as? Int64 else { return nil }
        return Keymap(
            id: Int(id),
            name: name,
            deviceModel: Int(deviceModel),
            top: codes(row, "top"),
            fn1: codes(row, "fn1"),
            fn2: codes(row, "fn2"),
            tap: codes(row, "tap"),
            isDefault: (row["isDefault"] as? Int64).map { $0 != 0 } ?? false,
            isChanged: (row["isChanged"] as? Int64).map { $0 != 0 } ?? false,
            quickNumber: (row["quickNumber"] as? Int64).map(Int.init),
            macro: ints(row, "macro")
        )
    }

    private static func ints(_ row: [String: Any], _ key: String) -> [Int] {
        guard let text = row[key] as? String, let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return values
    }

    private static func codes(_ row: [String: Any], _ key: String) -> [Keycode] {
        ints(row, key).map(Keycode.init(raw:))
    }
}
