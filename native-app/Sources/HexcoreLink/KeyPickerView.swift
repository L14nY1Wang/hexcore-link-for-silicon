import SwiftUI

/// Sheet for assigning a keycode to a layout slot. Categories mirror the
/// vendor app; keys carry an SF Symbol where the vendor shows an icon.
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
            categoryBar
            searchField
            Divider()
            grid
        }
        .padding(16)
        .frame(width: 580, height: 470)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("选择键位").font(.headline)
            Spacer()
            Text("\(items.count) 个").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(KeyCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item.title)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                category == item ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    category == item ? Color.accentColor : .clear, lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
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

    private var items: [KeyChoice] {
        if query.isEmpty {
            return KeyCatalog.matches(category, query: "")
        }
        return KeyCatalog.all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var grid: some View {
        ScrollView {
            if items.isEmpty {
                Text("没有匹配的键位")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(items) { choice in
                        Button {
                            onPick(choice.key)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                if let symbol = choice.symbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(height: 18)
                                } else {
                                    Spacer().frame(height: 18)
                                }
                                Text(choice.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
