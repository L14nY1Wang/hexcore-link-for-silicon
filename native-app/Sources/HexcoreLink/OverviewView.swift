import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: DeviceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionBanner
                if let device = store.connected {
                    deviceCard(device)
                    infoCard
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func deviceCard(_ device: DeviceInfo) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(device.product)
                    .font(.system(size: 24, weight: .bold))
                HStack(spacing: 8) {
                    Label(device.isUSB ? "USB" : "蓝牙", systemImage: device.isUSB ? "cable.connector" : "dot.radiowaves.left.and.right")
                    Text("VID \(String(format: "%04X", device.vendorID)) · PID \(String(format: "%04X", device.productID))")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 10) {
                    Button("重新读取") { store.readAll() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("断开连接") { store.disconnect() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 6)
            }
            Spacer()
            if let battery = store.battery {
                batteryRing(battery)
            }
        }
        .card(padding: 20)
    }

    private func batteryRing(_ level: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, level))) / 100)
                .stroke(
                    AngularGradient(
                        colors: level > 25 ? [Theme.accent, Color(hex: 0xFF8A5B)] : [Color(hex: 0xFF5B5B), Color(hex: 0xFF9F43)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.35), radius: 6)
            VStack(spacing: 0) {
                Text("\(level)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 104, height: 104)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设备信息")
                .font(.system(size: 15, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                infoTile("固件", store.firmware, "cpu")
                infoTile("运行时间", store.uptime, "clock")
                infoTile("硬件状态", store.hardwareState, "memorychip")
                infoTile("输入监控", store.permission, "keyboard")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("UDID")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(store.udid)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .card(padding: 18)
    }

    private func infoTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("未连接设备")
                .font(.system(size: 15, weight: .semibold))
            Text("连接键盘后会自动出现在左侧，点击即可连接。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .card(padding: 0)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if store.permission != "granted" {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("输入监控权限：\(store.permission)（未授权时无法监听键盘事件）")
                    .font(.system(size: 12))
                Spacer()
                Button("请求权限") { store.requestPermission() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
    }
}
