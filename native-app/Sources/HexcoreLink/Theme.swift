import SwiftUI
import AppKit

enum Theme {
    static let canvas = Color(hex: 0xF5F5F7)
    static let sidebar = Color(hex: 0xFAFAFB)
    static let surface = Color.white
    static let border = Color(hex: 0xE4E4E9)
    static let textPrimary = Color(hex: 0x18181B)
    static let textSecondary = Color(hex: 0x71717A)
    static let textTertiary = Color(hex: 0xA1A1AA)
    static let accent = Color(hex: 0xE5484D)
    static let accentSoft = Color(hex: 0xE5484D).opacity(0.09)
    static let keyBorder = Color(hex: 0xDFDFE5)
    static let hoverFill = Color.black.opacity(0.045)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct Card: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.black.opacity(0.055) : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .foregroundStyle(Theme.textPrimary)
    }
}

/// macOS-style segmented control, flattened to the web-driver look.
struct SegmentedPills: View {
    let items: [(String, Int)]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let active = selection == item.1
                Button {
                    selection = item.1
                } label: {
                    Text(item.0)
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(active ? Theme.surface : Color.clear)
                                .shadow(color: .black.opacity(active ? 0.07 : 0), radius: 1, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}

struct HoverRow<Content: View>: View {
    var selected: Bool = false
    var radius: CGFloat = 7
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(selected ? Theme.accentSoft : (hovering ? Theme.hoverFill : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Icons (Lucide, ISC licensed)

enum IconStore {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}

struct AppIcon: View {
    let name: String
    let size: CGFloat

    init(_ name: String, size: CGFloat = 13) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let image = IconStore.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Faint dot grid; keeps the canvas flat but adds a technical texture.
struct DotGridBackground: View {
    var spacing: CGFloat = 22
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y: CGFloat = 10
            while y < size.height {
                var x: CGFloat = 10
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(.black.opacity(0.06)))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
