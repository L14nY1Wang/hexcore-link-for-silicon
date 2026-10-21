import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    topBar
                    detailPage
                }
            }
        }
        .alert("错误", isPresented: Binding(
            get: { !store.error.isEmpty },
            set: { if !$0 { store.error = "" } }
        )) {
            Button("好") { store.error = "" }
        } message: {
            Text(store.error)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            AppBackground().opacity(0.9)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("设备") {
                        ForEach(store.devices) { device in
                            deviceRow(device)
                        }
                        Button {
                            store.refresh()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.clockwise").frame(width: 18)
                                Text("重新扫描")
                                Spacer()
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    section("功能") {
                        ForEach(DeviceStore.Page.allCases) { page in
                            pageRow(page)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .padding(.leading, 10)
                .padding(.bottom, 2)
            content()
        }
    }

    private func pageRow(_ page: DeviceStore.Page) -> some View {
        let selected = store.page == page
        return Button {
            store.page = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.accentSoft : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deviceRow(_ device: DeviceInfo) -> some View {
        let connected = store.connected?.id == device.id
        return Button {
            store.connect(device)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: connected ? "keyboard.fill" : "keyboard")
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(connected ? Theme.accent : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.product)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(connected ? 1 : 0.82))
                    Text(device.isUSB ? "USB" : "蓝牙")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if connected {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(connected ? Color.white.opacity(0.9) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var topBar: some View {
        HStack {
            Button {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .help("显示/隐藏边栏")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var detailPage: some View {
        switch store.page {
        case .overview:
            OverviewView()
        case .layout:
            LayoutView()
        case .lighting, .macros, .settings:
            PlaceholderView(page: store.page)
        }
    }
}
