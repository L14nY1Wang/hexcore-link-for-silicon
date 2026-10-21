import SwiftUI

struct LayoutView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var selectedKey: Int?
    @State private var editing: KeyEditTarget?
    private let keyUnit: CGFloat = 36

    private struct KeyEditTarget: Identifiable {
        let id: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                keyboardGrid
                if let index = selectedKey {
                    keyDetail(index)
                }
                Divider()
                library
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { target in
            KeyPickerView { key in
                store.setKey(target.id, to: key)
                editing = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("配列").font(.title2.bold())
                HStack(spacing: 8) {
                    Text(store.currentKeymap.map { "\($0.name) · \($0.top.count) 键" } ?? "未选择配列")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if store.hasUnsavedEdits {
                        Text("未保存")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
            Picker("层", selection: $store.layerIndex) {
                Text("Top").tag(0)
                Text("Fn1").tag(1)
                Text("Fn2").tag(2)
                Text("Tap").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("从设备读取") { store.readDeviceLayer() }
            Button("应用到设备") { store.applyCurrentLayer() }
                .disabled(store.connected == nil || store.currentKeys.isEmpty)
            Button("保存到配列库") { store.saveCurrentLayout() }
                .disabled(store.currentKeymap == nil)
            if !store.deviceLayerStatus.isEmpty {
                Text(store.deviceLayerStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var keyboardGrid: some View {
        let rows = LayoutMap.rows(deviceModel: store.keyboardModel)
        let keys = store.currentKeys
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { slot in
                        keyCap(slot: slot, keys: keys)
                    }
                }
            }
        }
    }

    private func keyCap(slot: KeySlot, keys: [Keycode]) -> some View {
        let label = slot.index < keys.count ? keys[slot.index].label : ""
        let selected = selectedKey == slot.index
        return Button {
            selectedKey = slot.index
            editing = KeyEditTarget(id: slot.index)
        } label: {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: keyUnit * slot.width - 6, height: 36)
                .background(selected ? Color.accentColor.opacity(0.35) : Color(nsColor: .quaternaryLabelColor).opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func keyDetail(_ index: Int) -> some View {
        let keys = store.currentKeys
        let key = index < keys.count ? keys[index] : .transparent
        return HStack(spacing: 16) {
            Text("键 #\(index)").font(.headline)
            Text("标签 \(key.label.isEmpty ? "—" : key.label)")
            Text("原始值 \(String(format: "0x%04X", key.raw))")
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text("层 \(layerTitle)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("配列库").font(.headline)
                Text("\(store.layoutsForDevice.count) 套 · 型号 \(store.keyboardModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.layoutsForDevice) { layout in
                        Button {
                            store.selectLayout(layout.id)
                            selectedKey = nil
                        } label: {
                            HStack {
                                Text(layout.name)
                                    .fontWeight(store.selectedLayoutID == layout.id ? .semibold : .regular)
                                Spacer()
                                Text("型号 \(layout.model)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var layerTitle: String {
        switch store.layerIndex {
        case 1: return "Fn1"
        case 2: return "Fn2"
        case 3: return "Tap"
        default: return "Top"
        }
    }
}
