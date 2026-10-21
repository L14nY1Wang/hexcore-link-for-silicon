import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var selection: DeviceInfo.ID?

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
            .navigationTitle("Devices")
            .toolbar {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan HID devices")
            }
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                permissionBanner

                if let device = store.connected {
                    Text(device.product)
                        .font(.largeTitle.bold())
                    Text("\(device.isUSB ? "USB" : "Bluetooth") · VID \(String(format: "%04X", device.vendorID)) · PID \(String(format: "%04X", device.productID))")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let battery = store.battery {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                    LabeledContent("Firmware", value: store.firmware)
                    LabeledContent("Uptime", value: store.uptime)
                    LabeledContent("UDID") {
                        Text(store.udid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    LabeledContent("Hardware state") {
                        Text(store.hardwareState).font(.system(.caption, design: .monospaced))
                    }

                    HStack {
                        Button("Read again") { store.readAll() }
                        Button("Disconnect") { store.disconnect() }
                    }
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No device selected",
                        systemImage: "keyboard",
                        description: Text("Select a keyboard on the left to connect.")
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Button("OK") { store.error = "" }
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
                Text("Input Monitoring permission is \(store.permission). Keyboard input will not work without it.")
                Spacer()
                Button("Request") { store.requestPermission() }
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
