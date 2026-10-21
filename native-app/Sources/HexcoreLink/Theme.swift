import SwiftUI

enum Theme {
    static let accent = Color(hex: 0xE5453C)
    static let accentSoft = Color(hex: 0xE5453C).opacity(0.12)
    static let backgroundTop = Color(hex: 0xFAFAFC)
    static let backgroundBottom = Color(hex: 0xEDEDF3)
    static let cardFill = Color.white.opacity(0.88)
    static let cardStroke = Color.black.opacity(0.06)
    static let textPrimary = Color(hex: 0x1D1D22)
    static let textSecondary = Color.black.opacity(0.48)
    static let textTertiary = Color.black.opacity(0.32)
    static let keyFillTop = Color.white
    static let keyFillBottom = Color(hex: 0xF1F1F6)
    static let keyStroke = Color.black.opacity(0.08)
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

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.accent.opacity(0.07), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color(hex: 0x3A6BE8).opacity(0.05), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .shadow(color: Theme.accent.opacity(0.28), radius: 6, y: 2)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
            )
            .foregroundStyle(Theme.textPrimary.opacity(0.85))
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0 : 0.04), radius: 3, y: 1)
    }
}
