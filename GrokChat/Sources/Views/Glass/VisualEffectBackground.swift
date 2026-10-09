import SwiftUI
import AppKit

/// Real AppKit blur so the desktop shows through chrome regions.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Shared frosted fill + tint + vibrancy stroke for Settings live preview cards.
struct GlassChromeBackground: View {
    var cornerRadius: CGFloat = 20
    var showShadow: Bool = true
    var borderColor: Color? = nil

    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let g = settings.glassAppearance
        ZStack {
            if g.enabled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .background {
                        VisualEffectBackground(material: g.nsMaterial, blendingMode: .behindWindow)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .opacity(g.materialFillOpacity)

                if !g.isGhostGlass {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(g.swiftUIMaterial)
                        .opacity(g.materialFillOpacity * 0.30)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: GlassAppearance.solidMatteNSColor))
            }

            if g.tintOpacity > 0.001 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(g.tintColor(for: colorScheme).opacity(g.tintOpacity))
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            (borderColor ?? Color.primary).opacity(g.borderOpacity(for: colorScheme)),
                            (borderColor ?? Color.primary).opacity(g.borderOpacity(for: colorScheme) * 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: g.isGhostGlass ? 0.75 : 1
                )
        }
        .shadow(
            color: showShadow ? .black.opacity(g.shadowOpacity(for: colorScheme)) : .clear,
            radius: showShadow ? (g.isGhostGlass ? 10 : 18) : 0,
            y: showShadow ? (g.isGhostGlass ? 4 : 8) : 0
        )
    }
}

/// Settings pane for the liquid-glass titlebar. Hosted by the AppKit settings window.
struct GlassAppearanceSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Text & Theme") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Font Size: \(Int(settingsManager.fontSize))")
                            Slider(value: $settingsManager.fontSize, in: 10...20, step: 1)
                        }
                        Picker("Color Scheme", selection: $settingsManager.colorScheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                    }
                    .padding(4)
                }

                GroupBox("Window Chrome") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Liquid glass chrome", isOn: Binding(
                            get: { settingsManager.glassAppearance.enabled },
                            set: { settingsManager.glassAppearance.enabled = $0 }
                        ))
                        .toggleStyle(.switch)

                        Text("Frosted see-through titlebar and toolbar. Grok web content stays opaque; only surrounding chrome is glass.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        glassPreview
                            .frame(height: 88)
                            .opacity(settingsManager.glassAppearance.enabled ? 1 : 0.55)

                        Group {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("See-through")
                                    Spacer()
                                    Text("\(Int(settingsManager.glassAppearance.seeThrough * 100))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.seeThrough },
                                        set: { settingsManager.glassAppearance.seeThrough = $0 }
                                    ),
                                    in: 0...1
                                )
                                Text("Higher = more desktop visible. Low = solid matte near-black.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Material thickness")
                                    Spacer()
                                    Text(settingsManager.glassAppearance.thicknessLabel)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.thickness },
                                        set: { settingsManager.glassAppearance.thickness = $0 }
                                    ),
                                    in: 0...1
                                )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Vibrancy / highlight")
                                    Spacer()
                                    Text("\(Int(settingsManager.glassAppearance.vibrancy * 100))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.vibrancy },
                                        set: { settingsManager.glassAppearance.vibrancy = $0 }
                                    ),
                                    in: 0...1
                                )
                            }
                        }
                        .disabled(!settingsManager.glassAppearance.enabled)
                        .opacity(settingsManager.glassAppearance.enabled ? 1 : 0.45)

                        HStack {
                            Button("Reset Look") { settingsManager.resetGlassAppearance() }
                                .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                    .padding(4)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var glassPreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.45),
                    Color.purple.opacity(0.35),
                    Color.cyan.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                    .frame(width: 120, height: 56)
                    .background {
                        GlassChromeBackground(cornerRadius: 12, showShadow: true)
                    }
                    .overlay {
                        Text("Glass card")
                            .font(.caption.weight(.semibold))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Live preview")
                        .font(.subheadline.weight(.semibold))
                    Text(settingsManager.glassAppearance.enabled
                         ? "\(settingsManager.glassAppearance.thicknessLabel) · \(Int(settingsManager.glassAppearance.seeThrough * 100))% clear"
                         : "Solid chrome")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}
