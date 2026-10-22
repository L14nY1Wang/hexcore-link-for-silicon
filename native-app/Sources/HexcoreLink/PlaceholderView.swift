import SwiftUI

struct PlaceholderView: View {
    let page: DeviceStore.Page

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: page.icon)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                )
            Text("\(page.title)功能开发中")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("该页面尚未实现，配列页面已可用。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
