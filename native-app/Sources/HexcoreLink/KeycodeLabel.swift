import Foundation

extension Keycode {
    /// Compact label for the layout grid. Vendor keycodes carry HID usages, so
    /// the mapping here mirrors HID Usage Tables 0x04…0xE7.
    var label: String {
        switch self {
        case .transparent: return ""
        case .keyboard(let usage), .modifier(let usage):
            return Self.usageLabel(usage)
        case .layer(let n): return "FN\(n)"
        case .macro(let id): return "M\(id)"
        case .consumer: return "MEDIA"
        case .system: return "SYS"
        case .mouse: return "MOUSE"
        case .gamepad: return "PAD"
        case .symbol: return "SYM"
        case .emoji: return "EMOJI"
        case .hexcore: return "HC"
        case .unknown: return "?"
        }
    }

    private static func usageLabel(_ usage: UInt8) -> String {
        switch usage {
        case 4...29:
            let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            return String(letters[Int(usage) - 4])
        case 30...38:
            return String(Int(usage) - 29)
        case 39: return "0"
        case 40: return "⏎"
        case 41: return "esc"
        case 42: return "⌫"
        case 43: return "tab"
        case 44: return "space"
        case 45: return "-"
        case 46: return "="
        case 47: return "["
        case 48: return "]"
        case 49: return "\\"
        case 51: return ";"
        case 52: return "'"
        case 53: return "`"
        case 54: return ","
        case 55: return "."
        case 56: return "/"
        case 57: return "caps"
        case 58...69: return "F\(Int(usage) - 57)"
        case 74: return "home"
        case 75: return "pgup"
        case 76: return "del"
        case 77: return "end"
        case 78: return "pgdn"
        case 79: return "→"
        case 80: return "←"
        case 81: return "↓"
        case 82: return "↑"
        default: return String(format: "%02X", usage)
        }
    }
}
