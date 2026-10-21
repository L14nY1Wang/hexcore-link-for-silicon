import SwiftUI

struct PlaceholderView: View {
    let page: DeviceStore.Page

    var body: some View {
        ContentUnavailableView(
            "\(page.title)功能开发中",
            systemImage: page.icon,
            description: Text("该页面尚未实现，配列页面已可用。")
        )
    }
}
