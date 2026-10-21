import SwiftUI

/// Sheet for assigning a keycode to a layout slot.
struct KeyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    private let onPick: (Keycode) -> Void

    @State private var category: KeyCategory = .letters
    @State private var query = ""

    init(onPick: @escaping (Keycode) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Picker("分类", selection: $category) {
                ForEach(KeyCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            searchField
            Divider()
            grid
        }
        .padding(16)
        .frame(width: 520, height: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("选择键位").font(.headline)
            Spacer()
            Text("\(items.count) 个").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索键名", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var grid: some View {
        ScrollView {
            if items.isEmpty {
                Text("无匹配结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 92), spacing: 6)], spacing: 6) {
                    ForEach(items) { item in
                        Button { pick(item.key) } label: {
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
            }
        }
    }

    private func pick(_ key: Keycode) {
        onPick(key)
        dismiss()
    }

    private var items: [Item] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            return Self.all.filter { $0.category == category }
        }
        return Self.all.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    private static let hexcoreItems: [Item] = [
        Item(key: .transparent, name: "透明", category: .hexcore),
    ] + (0...3).map {
        Item(key: .layer($0), name: "层 \($0)", category: .hexcore)
    }

    private static let mediaItems: [Item] = KeycodeNames.media.map {
        Item(key: .consumer($0.code), name: $0.name, category: .media)
    }

    private static let keyboardItems: [Item] = KeycodeNames.keyboard
        .sorted { $0.key < $1.key }
        .map { usage, name in
            let key: Keycode = usage >= 0xE0 ? .modifier(usage) : .keyboard(usage)
            return Item(key: key, name: name, category: category(for: usage))
        }

    private static let all: [Item] = keyboardItems + mediaItems + hexcoreItems

    private static func category(for usage: UInt8) -> KeyCategory {
        switch usage {
        case 4...29: return .letters
        case 30...39, 89...98: return .numbers
        case 45...56, 84...88, 99, 100, 103, 133, 134: return .symbols
        case 57, 58...72, 83, 104...115: return .function
        case 73...82: return .navigation
        case 127...129: return .media
        case 224...231: return .modifiers
        default: return .other
        }
    }
}

private struct Item: Identifiable {
    let key: Keycode
    let name: String
    let category: KeyCategory

    var id: Int { key.raw }
}

private enum KeyCategory: String, CaseIterable, Identifiable {
    case letters, numbers, symbols, function, navigation, modifiers, media, hexcore, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: return "字符"
        case .numbers: return "数字"
        case .symbols: return "符号"
        case .function: return "功能键"
        case .navigation: return "导航"
        case .modifiers: return "修饰"
        case .media: return "媒体"
        case .hexcore: return "Hexcore"
        case .other: return "其他"
        }
    }
}
