import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: DeviceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionBanner

                if let device = store.connected {
                    Text(device.product)
                        .font(.largeTitle.bold())
                    Text("\(device.isUSB ? "USB" : "蓝牙") · VID \(String(format: "%04X", device.vendorID)) · PID \(String(format: "%04X", device.productID))")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let battery = store.battery {
                        LabeledContent("电量", value: "\(battery)%")
                    }
                    LabeledContent("固件", value: store.firmware)
                    LabeledContent("运行时间", value: store.uptime)
                    LabeledContent("UDID") {
                        Text(store.udid)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    LabeledContent("硬件状态", value: store.hardwareState)

                    HStack {
                        Button("重新读取") { store.readAll() }
                        Button("断开连接") { store.disconnect() }
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
