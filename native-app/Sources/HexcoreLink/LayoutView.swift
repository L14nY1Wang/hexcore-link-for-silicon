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
            VStack(alignment: .leading, spacing: 16) {
                controlCard
                keyboardCard
                if let index = selectedKey {
                    keyDetail(index)
                }
                libraryCard
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
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

    // MARK: - Controls

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("配列")
                            .font(.system(size: 22, weight: .bold))
                        if store.hasUnsavedEdits {
                            Text("未保存")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.accentSoft, in: Capsule())
                        }
                    }
                    Text(store.currentKeymap.map { "\(DeviceStore.shortName($0.name)) · \($0.top.count) 键" } ?? "未选择配列")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Picker("层", selection: $store.layerIndex) {
                    Text("Top").tag(0)
                    Text("Fn1").tag(1)
                    Text("Fn2").tag(2)
                    Text("Tap").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            HStack(spacing: 10) {
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
                }
                Spacer()
            }
        }
        .card(padding: 18)
    }

    // MARK: - Keyboard

    private var keyboardCard: some View {
        let rows = LayoutMap.rows(deviceModel: store.keyboardModel)
        let keys = store.currentKeys
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { slot in
                        keyCap(slot: slot, keys: keys)
                    }
                }
            }
        }
        .card(padding: 16)
    }

    private func keyCap(slot: KeySlot, keys: [Keycode]) -> some View {
        let label = slot.index < keys.count ? keys[slot.index].label : ""
        let selected = selectedKey == slot.index
        return Button {
            selectedKey = slot.index
            editing = KeyEditTarget(id: slot.index)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? .white : Theme.textPrimary.opacity(0.85))
                .frame(width: keyUnit * slot.width - 6, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: selected
                                    ? [Theme.accent.opacity(0.95), Theme.accent.opacity(0.72)]
                                    : [Theme.keyFillTop, Theme.keyFillBottom],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.keyStroke, lineWidth: 1)
                )
                .shadow(color: selected ? Theme.accent.opacity(0.35) : .black.opacity(0.08),
                        radius: selected ? 7 : 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(label.isEmpty ? "空" : label)
    }

    private func keyDetail(_ index: Int) -> some View {
        let keys = store.currentKeys
        let key = index < keys.count ? keys[index] : .transparent
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("键 #\(index)")
                    .font(.system(size: 13, weight: .semibold))
                Text(key.label.isEmpty ? "—" : key.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Divider().frame(height: 26)
            Text(String(format: "0x%04X", key.raw))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("修改按键") { editing = KeyEditTarget(id: index) }
                .buttonStyle(SecondaryButtonStyle())
            Text("层 \(layerTitle)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配列库")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(store.layoutsForDevice.count) 套 · 型号 \(store.keyboardModel)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            VStack(spacing: 2) {
                ForEach(store.layoutsForDevice) { layout in
                    libraryRow(layout)
                }
            }
        }
        .card(padding: 16)
    }

    private func libraryRow(_ layout: DeviceStore.LayoutSummary) -> some View {
        let selected = store.selectedLayoutID == layout.id
        return Button {
            store.selectLayout(layout.id)
            selectedKey = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: layout.isDefault ? "lock.fill" : "square.and.pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 14)
                Text(layout.displayName)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(selected ? 1 : 0.85))
                Spacer()
                Text("型号 \(layout.model)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.accentSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
