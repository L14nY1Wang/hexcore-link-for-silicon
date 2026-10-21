import Foundation

/// Categories mirror the vendor app's `keycode.group.*` strings.
enum KeyCategory: String, CaseIterable, Identifiable {
    case letters, numbers, symbols, function, navigation, modifiers, keypad, media, mouse, hexcore, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: return "字符"
        case .numbers: return "数字"
        case .symbols: return "符号"
        case .function: return "功能键"
        case .navigation: return "方向/导航"
        case .modifiers: return "修饰"
        case .keypad: return "小键盘"
        case .media: return "多媒体"
        case .mouse: return "鼠标"
        case .hexcore: return "Hexcore"
        case .other: return "其它"
        }
    }
}

struct KeyChoice: Identifiable {
    let id: String
    let title: String
    let symbol: String?
    let key: Keycode
    let category: KeyCategory
}

/// The pickable keys. Mirrors the vendor keycode groups: keyboard alphabet,
/// numbers, symbols, function keys, navigation, modifiers, keypad, media
/// consumer usages, mouse buttons/wheel, Hexcore-specific codes and the rest.
enum KeyCatalog {
    static let all: [KeyChoice] = {
        var items: [KeyChoice] = []

        func add(_ title: String, _ symbol: String?, _ key: Keycode, _ category: KeyCategory, id: String? = nil) {
            items.append(KeyChoice(id: id ?? "\(category.rawValue)-\(title)", title: title,
                                   symbol: symbol, key: key, category: category))
        }

        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            add(String(letter), nil, .keyboard(UInt8(4 + index)), .letters)
        }
        for digit in 1...9 { add("\(digit)", nil, .keyboard(UInt8(29 + digit)), .numbers) }
        add("0", nil, .keyboard(39), .numbers)

        let symbols: [(String, UInt8)] = [
            ("Enter", 40), ("Esc", 41), ("Backspace", 42), ("Tab", 43), ("Space", 44),
            ("-", 45), ("=", 46), ("[", 47), ("]", 48), ("\\", 49), (";", 51),
            ("'", 52), ("`", 53), (",", 54), (".", 55), ("/", 56), ("Caps Lock", 57),
        ]
        for (title, usage) in symbols {
            add(title, nil, .keyboard(usage), .symbols)
        }

        for index in 1...12 { add("F\(index)", nil, .keyboard(UInt8(57 + index)), .function) }
        for index in 13...24 { add("F\(index)", nil, .keyboard(UInt8(91 + index)), .function) }

        let navigation: [(String, String, UInt8)] = [
            ("上", "arrow.up", 82), ("下", "arrow.down", 81),
            ("左", "arrow.left", 80), ("右", "arrow.right", 79),
            ("Home", "house", 74), ("End", "arrow.right.to.line", 77),
            ("PgUp", "chevron.up.to.line", 75), ("PgDn", "chevron.down.to.line", 78),
            ("Insert", "plus.square", 73), ("Delete", "delete.left", 76),
        ]
        for (title, symbol, usage) in navigation {
            add(title, symbol, .keyboard(usage), .navigation)
        }

        let modifiers: [(String, String, UInt8)] = [
            ("⌃", "control", 224), ("⇧", "shift", 225), ("⌥", "option", 226), ("⌘", "command", 227),
            ("R ⌃", "control", 228), ("R ⇧", "shift", 229), ("R ⌥", "option", 230), ("R ⌘", "command", 231),
        ]
        for (title, symbol, usage) in modifiers {
            add(title, symbol, .modifier(usage), .modifiers)
        }

        let keypad: [(String, UInt8)] = [
            ("Num /", 84), ("Num *", 85), ("Num -", 86), ("Num +", 87), ("Num Enter", 88),
            ("Num 1", 89), ("Num 2", 90), ("Num 3", 91), ("Num 4", 92), ("Num 5", 93),
            ("Num 6", 94), ("Num 7", 95), ("Num 8", 96), ("Num 9", 97), ("Num 0", 98),
            ("Num .", 99), ("Num =", 103),
        ]
        for (title, usage) in keypad {
            add(title, nil, .keyboard(usage), .keypad)
        }

        let media: [(String, String, UInt16)] = [
            ("静音", "speaker.slash.fill", 0xE2),
            ("音量 +", "speaker.plus.fill", 0xE9),
            ("音量 -", "speaker.minus.fill", 0xEA),
            ("上一曲", "backward.fill", 0xB6),
            ("下一曲", "forward.fill", 0xB5),
            ("播放/暂停", "playpause.fill", 0xCD),
        ]
        for (title, symbol, usage) in media {
            add(title, symbol, .consumer(usage), .media)
        }

        let mouse: [(String, String, UInt8)] = [
            ("左键", "computermouse", 16), ("右键", "computermouse.fill", 17),
            ("中键", "circle.circle", 18),
            ("滚轮上", "arrow.up.circle", 32), ("滚轮下", "arrow.down.circle", 33),
        ]
        for (title, symbol, code) in mouse {
            add(title, symbol, .mouse(code), .mouse)
        }

        add("透明", "circle.dashed", .transparent, .hexcore)
        for layer in 0...3 {
            add("层 \(layer)", "square.stack", .layer(layer), .hexcore)
        }
        let bluetooth: [(String, UInt8)] = [("蓝牙 1", 48), ("蓝牙 2", 49), ("蓝牙 3", 50), ("蓝牙 4", 51)]
        for (title, code) in bluetooth {
            add(title, "dot.radiowaves.left.and.right", .hexcore(code), .hexcore)
        }
        let wireless: [(String, UInt8)] = [("24G 1", 64), ("24G 2", 65), ("24G 3", 66), ("24G 4", 67)]
        for (title, code) in wireless {
            add(title, "antenna.radiowaves.left.and.right", .hexcore(code), .hexcore)
        }
        add("游戏", "gamecontroller", .hexcore(2), .hexcore)
        add("表情", "face.smiling", .hexcore(1), .hexcore)
        add("宏", "record.circle", .macro(0), .hexcore)

        let other: [(String, UInt8)] = [
            ("Print Screen", 70), ("Scroll Lock", 71), ("Pause", 72),
            ("Num Lock", 83), ("Application", 101),
        ]
        for (title, usage) in other {
            add(title, nil, .keyboard(usage), .other)
        }
        for index in 1...9 { add("INT\(index)", nil, .keyboard(UInt8(134 + index)), .other) }
        for index in 1...9 { add("Lang\(index)", nil, .keyboard(UInt8(143 + index)), .other) }

        return items
    }()

    static func matches(_ category: KeyCategory, query: String) -> [KeyChoice] {
        all.filter { choice in
            choice.category == category &&
            (query.isEmpty || choice.title.localizedCaseInsensitiveContains(query))
        }
    }
}
