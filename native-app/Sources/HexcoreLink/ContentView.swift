import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(200)
        } detail: {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                DotGridBackground()
                VStack(spacing: 0) {
                    topBar
                    page
                }
            }
        }
        .alert(store.error, isPresented: Binding(
            get: { !store.error.isEmpty },
            set: { if !$0 { store.error = "" } }
        )) {
            Button("好") { store.error = "" }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            } label: {
                AppIcon("panel-left", size: 13)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.045))
                    )
            }
            .buttonStyle(.plain)
            .help("显示/隐藏侧边栏")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var page: some View {
        switch store.page {
        case .overview: OverviewView()
        case .layout: LayoutView()
        default: PlaceholderView(page: store.page)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("设备")
                    ForEach(store.devices) { device in
                        deviceRow(device)
                    }
                    Button {
                        store.refresh()
                    } label: {
                        HStack(spacing: 8) {
                            AppIcon("scan-line", size: 12)
                            Text("重新扫描")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    sectionLabel("功能")
                        .padding(.top, 18)
                    ForEach(DeviceStore.Page.allCases) { page in
                        navRow(page)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 26, height: 26)
                .overlay(
                    AppIcon("keyboard", size: 13)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text("Hexcore Link")
                    .font(.system(size: 13, weight: .semibold))
                Text("2.5.9")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    private func deviceRow(_ device: DeviceInfo) -> some View {
        let connected = store.connected?.id == device.id
        return Button {
            if connected { store.disconnect() } else { store.connect(device) }
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(connected ? Theme.accentSoft : Color.black.opacity(0.045))
                    .frame(width: 24, height: 24)
                    .overlay(
                        AppIcon("keyboard", size: 12)
                            .foregroundStyle(connected ? Theme.accent : Theme.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.product)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(device.isUSB ? "USB" : "蓝牙")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Circle()
                    .fill(connected ? Color(hex: 0x22C55E) : Color.black.opacity(0.14))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(connected ? Theme.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(connected ? Theme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navRow(_ page: DeviceStore.Page) -> some View {
        HoverRow(selected: store.page == page, radius: 7) {
            store.page = page
        } content: {
            HStack(spacing: 9) {
                AppIcon(page.icon, size: 13)
                    .frame(width: 16)
                Text(page.title)
                    .font(.system(size: 12.5, weight: store.page == page ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(store.page == page ? Theme.accent : Theme.textSecondary)
        }
    }
}
