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
