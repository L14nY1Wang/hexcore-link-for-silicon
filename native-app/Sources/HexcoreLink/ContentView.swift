import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $store.page) {
                Section("设备") {
                    ForEach(store.devices) { device in
                        Button {
                            store.connect(device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.product)
                                        .font(.headline)
                                    Text(device.isUSB ? "USB" : "蓝牙")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.connected?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        store.refresh()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Section("功能") {
                    ForEach(DeviceStore.Page.allCases) { page in
                        Label(page.title, systemImage: page.icon)
                            .tag(page)
                    }
                }
            }
            .navigationTitle("Hexcore Link")
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .help("显示/隐藏边栏")
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)

                detailPage
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
