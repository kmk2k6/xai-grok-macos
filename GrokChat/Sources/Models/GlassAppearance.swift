import SwiftUI
import AppKit

/// User-adjustable liquid-glass look for window chrome (titlebar / toolbar).
/// Grok WKWebView content stays opaque — only surrounding chrome uses this.
struct GlassAppearance: Equatable, Codable {
    /// Master switch for frosted see-through chrome.
    var enabled: Bool
    /// 0 = more solid tint, 1 = maximum desktop see-through (ghost glass).
    var seeThrough: Double
    /// 0 = ultraThin … 1 = ultraThick (blur / material thickness).
    var thickness: Double
    /// Border / highlight strength (0…1).
    var vibrancy: Double

    /// Default toward solid matte near-black (brown cast gone); dial glass up in Settings.
    static let `default` = GlassAppearance(
        enabled: true,
        seeThrough: 0.06,
        thickness: 0.55,
        vibrancy: 0.40
    )

    enum CodingKeys: String, CodingKey {
        case enabled, seeThrough, thickness, vibrancy
    }

    init(enabled: Bool, seeThrough: Double, thickness: Double, vibrancy: Double) {
        self.enabled = enabled
        self.seeThrough = seeThrough.clamped01
        self.thickness = thickness.clamped01
        self.vibrancy = vibrancy.clamped01
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        seeThrough = (try c.decodeIfPresent(Double.self, forKey: .seeThrough) ?? 0.06).clamped01
        thickness = (try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0.55).clamped01
        vibrancy = (try c.decodeIfPresent(Double.self, forKey: .vibrancy) ?? 0.40).clamped01
    }

    var thicknessLabel: String {
        switch thickness {
        case ..<0.2: return "Ultra Thin"
        case ..<0.4: return "Thin"
        case ..<0.6: return "Regular"
        case ..<0.8: return "Thick"
        default: return "Ultra Thick"
        }
    }

    var swiftUIMaterial: Material {
        switch thickness {
        case ..<0.2: return .ultraThinMaterial
        case ..<0.4: return .thinMaterial
        case ..<0.6: return .regularMaterial
        case ..<0.8: return .thickMaterial
        default: return .ultraThickMaterial
        }
    }

    var nsMaterial: NSVisualEffectView.Material {
        switch thickness {
        case ..<0.2: return .underPageBackground
        case ..<0.4: return .popover
        case ..<0.6: return .hudWindow
        case ..<0.8: return .sidebar
        default: return .headerView
        }
    }

    /// Extra solid wash on top of material. At seeThrough=1 → 0.
    var tintOpacity: Double {
        guard enabled else { return 0.92 }
        let remaining = 1.0 - seeThrough
        return remaining * remaining * 0.42
    }

    var materialFillOpacity: Double {
        guard enabled else { return 1 }
        return 1.0 - seeThrough * 0.73
    }

    var windowEffectOpacity: Double {
        guard enabled else { return 1 }
        return 1.0 - seeThrough * 0.61
    }

    var isGhostGlass: Bool {
        enabled && seeThrough >= 0.92
    }

    /// Treat as solid matte chrome (no VE) when glass off or see-through is low
    /// (default 6% stays solid #000000; dial See-through up to engage glass).
    var prefersSolidChrome: Bool {
        !enabled || seeThrough < 0.12
    }

    func borderOpacity(for colorScheme: ColorScheme) -> Double {
        let base = colorScheme == .dark ? 0.12 : 0.07
        var value = (base + vibrancy * 0.26) * (enabled ? 1 : 0.45)
        if enabled && seeThrough > 0.7 {
            let ghostBoost = (seeThrough - 0.7) / 0.3
            let floor = colorScheme == .dark ? 0.10 : 0.08
            value = max(value * (1.0 - ghostBoost * 0.25), floor * (0.7 + vibrancy * 0.3))
        }
        return value
    }

    func shadowOpacity(for colorScheme: ColorScheme) -> Double {
        let base = colorScheme == .dark ? 0.28 : 0.12
        var value = base * (0.55 + vibrancy * 0.45) * (enabled ? 1 : 0.6)
        if enabled {
            value *= 1.0 - seeThrough * 0.55
        }
        return value
    }

    func tintColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            // True black #000000 — avoid warm system windowBackgroundColor
            return Color(red: 0, green: 0, blue: 0)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    /// Solid matte fill used when glass is off / low seeThrough.
    static var solidMatteNSColor: NSColor {
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) // #000000
    }
}

private extension Double {
    var clamped01: Double { min(1, max(0, self)) }
}
