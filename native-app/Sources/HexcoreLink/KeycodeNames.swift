import Foundation

/// Display names for HID keyboard usages carried by `Keycode.keyboard`.
///
/// The table mirrors the vendor `KC_*` enum in `dist/renderers/index-*.js`
/// (`KC_A` = 4 … `KC_RGUI` = 231). Usages the vendor enum leaves undefined
/// keep a hex placeholder so the table stays complete.
enum KeycodeNames {
    static let keyboard: [UInt8: String] = {
        var map: [UInt8: String] = [:]
        for usage in UInt8(4)...UInt8(231) {
            map[usage] = String(format: "0x%02X", usage)
        }

        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            map[UInt8(4 + index)] = String(letter)
        }
        for digit in 1...9 { map[UInt8(29 + digit)] = "\(digit)" }
        map[39] = "0"
        for index in 1...12 { map[UInt8(57 + index)] = "F\(index)" }
        for index in 13...24 { map[UInt8(91 + index)] = "F\(index)" }
        for index in 1...9 { map[UInt8(88 + index)] = "Num \(index)" }
        map[98] = "Num 0"
        for index in 1...9 { map[UInt8(134 + index)] = "INT\(index)" }
        for index in 1...9 { map[UInt8(143 + index)] = "Lang\(index)" }
        for (offset, letter) in "ABCDEF".enumerated() {
            map[UInt8(188 + offset)] = "Num \(letter)"
        }

        let named: [(UInt8, String)] = [
            (40, "Enter"), (41, "Esc"), (42, "Backspace"), (43, "Tab"), (44, "Space"),
            (45, "-"), (46, "="), (47, "["), (48, "]"), (49, "\\"), (50, "# (ISO)"),
            (51, ";"), (52, "'"), (53, "`"), (54, ","), (55, "."), (56, "/"),
            (57, "Caps Lock"),
            (70, "PrtSc"), (71, "Scroll Lock"), (72, "Pause"),
            (73, "Insert"), (74, "Home"), (75, "Page Up"), (76, "Delete"),
            (77, "End"), (78, "Page Down"),
            (79, "Right"), (80, "Left"), (81, "Down"), (82, "Up"),
            (83, "Num Lock"), (84, "Num /"), (85, "Num *"), (86, "Num -"),
            (87, "Num +"), (88, "Num Enter"), (99, "Num ."),
            (100, "ISO \\"), (101, "Application"), (102, "Power"), (103, "Num ="),
            (116, "Execute"), (117, "Help"), (118, "Menu"), (119, "Select"),
            (120, "Stop"), (121, "Again"), (122, "Undo"), (123, "Cut"),
            (124, "Copy"), (125, "Paste"), (126, "Find"),
            (127, "Mute"), (128, "Volume Up"), (129, "Volume Down"),
            (130, "Locking Caps"), (131, "Locking Num"), (132, "Locking Scroll"),
            (133, "Num ,"), (134, "Num = (AS400)"),
            (153, "Alt Erase"), (154, "SysReq"), (155, "Cancel"), (156, "Clear"),
            (157, "Prior"), (158, "Return"), (159, "Separator"), (160, "Out"),
            (161, "Oper"), (162, "Clear Again"), (163, "CrSel"), (164, "ExSel"),
            (176, "Num 00"), (177, "Num 000"),
            (178, "Thousands Sep"), (179, "Decimal Sep"),
            (180, "Currency Unit"), (181, "Currency Sub"),
            (182, "Num ("), (183, "Num )"), (184, "Num {"), (185, "Num }"),
            (186, "Num Tab"), (187, "Num Backspace"),
            (194, "Num XOR"), (195, "Num ^"), (196, "Num %"), (197, "Num <"),
            (198, "Num >"), (199, "Num &"), (200, "Num &&"), (201, "Num |"),
            (202, "Num ||"), (203, "Num :"), (204, "Num #"), (205, "Num Space"),
            (206, "Num @"), (207, "Num !"), (208, "Num Store"), (209, "Num Recall"),
            (210, "Num Clear"), (211, "Num Add"), (212, "Num Sub"), (213, "Num Mul"),
            (214, "Num Div"), (215, "Num ±"), (216, "Num Clear"),
            (217, "Num Clear Entry"), (218, "Num Binary"), (219, "Num Octal"),
            (220, "Num Decimal"), (221, "Num Hex"),
            (224, "Ctrl"), (225, "Shift"), (226, "Alt"), (227, "Cmd"),
            (228, "R Ctrl"), (229, "R Shift"), (230, "R Alt"), (231, "R Cmd"),
        ]
        for (usage, name) in named { map[usage] = name }

        return map
    }()

    /// Vendor `HC_*` codes carried by `Keycode.hexcore` (from the renderer's
    /// `HEXCORE` enum). Kept short so they fit on a key cap.
    static let hexcore: [UInt8: String] = [
        0: "—",
        1: "EMOJI",
        2: "PAD",
        3: "MACRO",
        48: "BT1", 49: "BT2", 50: "BT3", 51: "BT4",
        52: "BT5", 53: "BT6", 54: "BT7", 55: "BT8",
        64: "2.4G1", 65: "2.4G2", 66: "2.4G3", 67: "2.4G4",
        68: "2.4G5", 69: "2.4G6", 70: "2.4G7", 71: "2.4G8",
        80: "HUB↑", 81: "HUB↓", 82: "HUB←", 83: "HUB→",
        96: "MENU↑", 97: "MENU↓",
        224: "LIGHT1", 225: "LIGHT2",
        240: "LIGHT", 241: "EFFECT",
        243: "BRI+", 244: "BRI-",
        246: "BATT", 247: "QNUM",
    ]

    /// HID Consumer Page usages exposed by the vendor app.
    static let media: [(code: UInt16, name: String)] = [
        (0xE2, "静音"), (0xE9, "音量增"), (0xEA, "音量减"),
        (0xB6, "上一曲"), (0xB5, "下一曲"), (0xCD, "播放暂停"),
    ]
}

extension KeycodeNames {
    static let mediaByCode: [UInt16: String] = Dictionary(
        uniqueKeysWithValues: media.map { ($0.code, $0.name) }
    )
}
