import SwiftUI

struct PlaceholderView: View {
    let page: DeviceStore.Page

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: page.icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text("\(page.title)功能开发中")
                .font(.system(size: 16, weight: .semibold))
            Text("该页面尚未实现，配列页面已可用。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
