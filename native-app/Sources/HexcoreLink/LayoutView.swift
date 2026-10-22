import SwiftUI

struct LayoutView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var selectedKey: Int?
    @State private var editing: KeyEditTarget?
    @State private var renameTarget: DeviceStore.LayoutSummary?
    @State private var renameText = ""
    private let keyUnit: CGFloat = 36

    private struct KeyEditTarget: Identifiable {
        let id: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                toolbar
                keyboardCard
                if let index = selectedKey {
                    keyDetail(index)
                }
                libraryCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("重命名配列", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                store.renameSelectedLayout(to: renameText)
                renameTarget = nil
            }
        }
        .sheet(item: $editing) { target in
            KeyPickerView { key in
                store.setKey(target.id, to: key)
                editing = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("配列")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if store.hasUnsavedEdits {
                        Text("未保存")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(store.currentKeymap.map { "\(DeviceStore.shortName($0.name)) · \($0.top.count) 键" } ?? "未选择配列")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            SegmentedPills(
                items: [("Top", 0), ("Fn1", 1), ("Fn2", 2), ("Tap", 3)],
                selection: $store.layerIndex
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("从设备读取") { store.readDeviceLayer() }
                .buttonStyle(SecondaryButtonStyle())
            Button("应用到设备") { store.applyCurrentLayer() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.connected == nil || store.currentKeys.isEmpty)
            Button("保存到配列库") { store.saveCurrentLayout() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.currentKeymap == nil)
            if !store.deviceLayerStatus.isEmpty {
                Text(store.deviceLayerStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Keyboard

    private var keyboardCard: some View {
        let rows = LayoutMap.rows(deviceModel: store.keyboardModel)
        let keys = store.currentKeys
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row) { slot in
                        KeyCap(
                            label: slot.index < keys.count ? keys[slot.index].label : "",
                            width: keyUnit * slot.width - 5,
                            selected: selectedKey == slot.index
                        ) {
                            selectedKey = slot.index
                            editing = KeyEditTarget(id: slot.index)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private func keyDetail(_ index: Int) -> some View {
        let keys = store.currentKeys
        let key = index < keys.count ? keys[index] : .transparent
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("键 #\(index)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(key.label.isEmpty ? "—" : key.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Rectangle().fill(Theme.border).frame(width: 1, height: 24)
            Text(String(format: "0x%04X", key.raw))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("层 \(layerTitle)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.045), in: Capsule())
            Button("修改按键") { editing = KeyEditTarget(id: index) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .card(padding: 12)
    }

    private var layerTitle: String {
        switch store.layerIndex {
        case 1: return "Fn1"
        case 2: return "Fn2"
        case 3: return "Tap"
        default: return "Top"
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("配列库")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(store.layoutsForDevice.count) 套 · 型号 \(store.keyboardModel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            VStack(spacing: 0) {
                ForEach(store.layoutsForDevice) { layout in
                    libraryRow(layout)
                }
            }
        }
        .card(padding: 12)
    }

    private func libraryRow(_ layout: DeviceStore.LayoutSummary) -> some View {
        let selected = store.selectedLayoutID == layout.id
        return HoverRow(selected: selected) {
            store.selectLayout(layout.id)
            selectedKey = nil
        } content: {
            HStack(spacing: 9) {
                Image(systemName: layout.isDefault ? "lock.fill" : "square.and.pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 14)
                Text(layout.displayName)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textPrimary.opacity(0.85))
                Spacer()
                Text("型号 \(layout.model)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .contextMenu {
            Button("重命名") {
                renameTarget = layout
                renameText = layout.displayName
            }
            Button("复制为副本") {
                store.selectLayout(layout.id)
                store.duplicateCurrentLayout()
            }
            Button("删除", role: .destructive) {
                store.selectLayout(layout.id)
                store.deleteSelectedLayout()
            }
        }
    }
}

/// A single key cap: flat white tile, red when selected, subtle lift on hover.
struct KeyCap: View {
    let label: String
    let width: CGFloat
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(selected ? Color.white : Theme.textPrimary.opacity(0.88))
                .frame(width: width, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Theme.accent : (hovering ? Theme.accentSoft : Theme.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            selected ? Color.clear : (hovering ? Theme.accent.opacity(0.45) : Theme.keyBorder),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(selected ? 0.10 : 0.04), radius: selected ? 4 : 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label.isEmpty ? "空" : label)
    }
}
