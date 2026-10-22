import SwiftUI

struct LightingView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var brightnessDraft: Double?

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(alignment: .top, spacing: 14) {
                    effectsCard
                    VStack(spacing: 14) {
                        colorCard
                        brightnessCard
                    }
                    .frame(width: 262)
                }
                if !store.lightStatus.isEmpty {
                    Text(store.lightStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("灯光")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                Text("灯效、颜色与亮度")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if store.connected == nil {
                Text("设备未连接")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xF59E0B))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xF59E0B).opacity(0.10), in: Capsule())
            }
        }
    }

    private var effectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("灯效")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(store.lightEffects.count) 种")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button { store.previewSelectedLightEffect() } label: {
                    HStack(spacing: 5) {
                        AppIcon("eye", size: 11)
                        Text("预览")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.connected == nil || store.selectedLightEffectID == nil)
                Button { store.applyLightEffect() } label: {
                    HStack(spacing: 5) {
                        AppIcon("upload", size: 11)
                        Text("应用到设备")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.connected == nil || store.selectedLightEffectID == nil)
            }

            if store.lightEffects.isEmpty {
                Text("未找到该设备的灯效配置")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.lightEffects) { effect in
                        effectTile(effect)
                    }
                }
            }
        }
        .card(padding: 16)
    }

    private func effectTile(_ effect: DeviceStore.LightEffect) -> some View {
        let selected = store.selectedLightEffectID == effect.id
        return Button {
            store.selectedLightEffectID = effect.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(Array(effect.swatchColors.prefix(7).enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Text(effect.displayName)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(effect.isDynamic ? "动态" : "静态")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.black.opacity(0.045), in: Capsule())
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accentSoft : Color.black.opacity(0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义颜色")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                ColorPicker("颜色", selection: $store.customLightColor, supportsOpacity: false)
                    .labelsHidden()
                Text("选择颜色后点击预览")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            HStack(spacing: 8) {
                Button { store.previewLightColor() } label: {
                    HStack(spacing: 5) {
                        AppIcon("eye", size: 11)
                        Text("预览")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.connected == nil)
                Spacer()
                Button { store.applyCustomLightColor() } label: {
                    HStack(spacing: 5) {
                        AppIcon("save", size: 11)
                        Text("保存到设备")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.connected == nil)
            }
        }
        .card(padding: 16)
    }

    private var brightnessCard: some View {
        let level = brightnessDraft ?? Double(store.brightness)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("亮度")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(level))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { level },
                    set: { brightnessDraft = $0 }
                ),
                in: 0...100,
                onEditingChanged: { editing in
                    if !editing, let draft = brightnessDraft {
                        store.setBrightness(Int(draft))
                        brightnessDraft = nil
                    }
                }
            )
            .tint(Theme.accent)
            .disabled(store.connected == nil)
            Text("松开滑杆后写入设备")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 16)
    }
}
