import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var selection: DeviceInfo.ID?

    /// Points per 1u of key width.
    private static let keyUnit: CGFloat = 36

    var body: some View {
        NavigationSplitView {
            List(store.devices, selection: $selection) { device in
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.product.isEmpty ? "Unknown device" : device.product)
                        .font(.headline)
                    Text(device.isUSB ? "USB" : "Bluetooth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(device.id)
            }
            .navigationTitle("设备")
            .toolbar {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan HID devices")
            }
        } detail: {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionBanner

                if let device = store.connected {
                    Text(device.product)
                        .font(.largeTitle.bold())
                    Text("\(device.isUSB ? "USB" : "Bluetooth") · VID \(String(format: "%04X", device.vendorID)) · PID \(String(format: "%04X", device.productID))")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let battery = store.battery {
                        LabeledContent("电量", value: "\(battery)%")
                    }
                    LabeledContent("固件", value: store.firmware)
                    LabeledContent("运行时间", value: store.uptime)
                    LabeledContent("UDID") {
                        Text(store.udid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    LabeledContent("硬件状态") {
                        Text(store.hardwareState).font(.system(.caption, design: .monospaced))
                    }

                    HStack {
                        Button("重新读取") { store.readAll() }
                        Button("断开连接") { store.disconnect() }
                    }

                    if let keymap = store.currentKeymap {
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("配列 · \(keymap.name)").font(.headline)
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
                        HStack {
                            Button("从设备读取配列") { store.readDeviceLayer() }
                            Button("应用当前配列到设备") { store.applyCurrentLayer() }
                            if !store.deviceLayerStatus.isEmpty {
                                Text(store.deviceLayerStatus)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(LayoutMap.rows(deviceModel: keymap.deviceModel).enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 4) {
                                    ForEach(row) { slot in
                                        if slot.index < keymap.top.count {
                                            Text(keymap.top[slot.index].label)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .frame(width: CGFloat(slot.width) * Self.keyUnit, height: 34)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !store.layouts.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("配列库").font(.headline)
                        Text("共 \(store.layouts.count) 套配列 · \(Set(store.layouts.map(\.model)).count) 个设备型号")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(store.layouts.prefix(8)) { layout in
                            Button {
                                store.selectLayout(layout.id)
                            } label: {
                                HStack {
                                    Text(layout.name)
                                        .fontWeight(store.selectedLayoutID == layout.id ? .semibold : .regular)
                                    Spacer()
                                    Text("型号 \(layout.model)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                        }
                    }
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "未选择设备",
                        systemImage: "keyboard",
                        description: Text("在左侧选择一个键盘即可连接。")
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let id = newValue, let device = store.devices.first(where: { $0.id == id }) else {
                store.disconnect()
                return
            }
            store.connect(device)
        }
        .alert("Error", isPresented: Binding(
            get: { !store.error.isEmpty },
            set: { if !$0 { store.error = "" } }
        )) {
            Button("好") { store.error = "" }
        } message: {
            Text(store.error)
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if store.permission != "granted" {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("输入监控权限：\(store.permission)（未授权时无法监听键盘事件）")
                Spacer()
                Button("请求权限") { store.requestPermission() }
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
