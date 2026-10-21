import Foundation

/// One key position in the physical layout.
struct KeySlot: Identifiable {
    /// Index into `Keymap.top` / `fn1` / `fn2` / `tap`.
    let index: Int
    /// Key width in 1u units.
    let width: Double

    var id: Int { index }
}

/// Physical key layout per device model, extracted from the vendor renderer
/// bundles (`dist/renderers/*.js`: `rowNumber` + `keycapStyles`, where
/// `U1` = 1u … `U6P25` = 6.25u).
struct LayoutMap {
    static func rows(deviceModel: Int) -> [[KeySlot]] {
        var index = 0
        return layout(for: deviceModel).map { widths in
            widths.map { width in
                defer { index += 1 }
                return KeySlot(index: index, width: width)
            }
        }
    }

    // MARK: - Tables

    /// 60% family: AnnePro, AnnePro 2, AnnePro 2C18, APX-F61, AnnePro 2D.
    private static let sixty: [[Double]] = [
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2],
        [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
        [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],
        [2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.75],
        [1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 1.25],
    ]

    /// AnneClassic D87 RGB.
    private static let d87: [[Double]] = [
        Array(repeating: 1, count: 16),
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1],
        [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 1, 1, 1],
        [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],
        [2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.75, 1],
        [1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 1.25, 1, 1, 1],
    ]

    private static func layout(for model: Int) -> [[Double]] {
        switch model {
        case 4: return uniform([14, 14, 13, 13, 8])   // AnnePro ISO
        case 6: return uniform([15, 15, 14, 14, 9])   // Param68
        case 7: return d87
        case 11, 13: return uniform([14, 15, 14, 14, 9]) // Fuji65 / Fuji65 RGB
        default: return sixty
        }
    }

    /// Row split only; the vendor bundles ship no per-key widths for these
    /// models, so every key renders 1u.
    private static func uniform(_ rows: [Int]) -> [[Double]] {
        rows.map { Array(repeating: 1, count: $0) }
    }
}
