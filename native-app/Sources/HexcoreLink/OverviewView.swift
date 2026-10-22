import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: DeviceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionBanner
                if let device = store.connected {
                    deviceCard(device)
                    infoCard
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("总览")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("设备状态与固件信息")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 2)
    }

    private func deviceCard(_ device: DeviceInfo) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(device.product)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(device.isUSB ? "USB" : "蓝牙")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.05), in: Capsule())
                }
                HStack(spacing: 14) {
                    metaItem("VID", String(format: "%04X", device.vendorID))
                    metaItem("PID", String(format: "%04X", device.productID))
                    metaItem("连接", device.isUSB ? "有线" : "无线")
                }
                HStack(spacing: 8) {
                    Button("重新读取") { store.readAll() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("断开连接") { store.disconnect() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 2)
            }
            Spacer()
            if let battery = store.battery {
                batteryRing(battery)
            }
        }
        .card(padding: 20)
    }

    private func metaItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func batteryRing(_ level: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, level))) / 100)
                .stroke(
                    level > 25 ? Theme.accent : Color(hex: 0xF59E0B),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(level)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("电量")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 92, height: 92)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设备信息")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                infoTile("固件", store.firmware, "cpu")
                infoTile("运行时间", store.uptime, "clock")
                infoTile("硬件状态", store.hardwareState, "memorychip")
                infoTile("输入监控", store.permission, "keyboard")
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("UDID")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.textTertiary)
                Text(store.udid.isEmpty ? "—" : store.udid)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .card(padding: 18)
    }

    private func infoTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.045))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "keyboard")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                )
            Text("未连接设备")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("连接键盘后会自动出现在左侧，点击即可连接。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .card(padding: 0)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if store.permission != "granted" {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xF59E0B))
                Text("输入监控权限：\(store.permission)（未授权时无法监听键盘事件）")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("请求权限") { store.requestPermission() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0xF59E0B).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(hex: 0xF59E0B).opacity(0.22), lineWidth: 1)
            )
        }
    }
}
