import Foundation
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let glassAppearance = "grok.glassAppearance"
    }

    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("selectedModel") var selectedModel: String = "grok-beta"
    @AppStorage("temperature") var temperature: Double = 0.7
    @AppStorage("streamResponses") var streamResponses: Bool = true
    @AppStorage("fontSize") var fontSize: Double = 14
    @AppStorage("colorScheme") var colorScheme: String = "system"

    private var isLoading = true

    /// Liquid-glass chrome (see-through, thickness, vibrancy). Persisted as JSON.
    @Published var glassAppearance: GlassAppearance = .default {
        didSet {
            guard !isLoading, glassAppearance != oldValue else { return }
            persistGlassAppearance()
            NotificationCenter.default.post(name: .grokGlassAppearanceDidChange, object: glassAppearance)
        }
    }

    static let availableModels = [
        "grok-beta",
        "grok-2",
        "grok-2-mini"
    ]

    var isAPIKeySet: Bool {
        !apiKey.isEmpty
    }

    private init() {
        glassAppearance = Self.loadGlassAppearance(from: .standard)
        isLoading = false
    }

    func resetToDefaults() {
        selectedModel = "grok-beta"
        temperature = 0.7
        streamResponses = true
        fontSize = 14
        colorScheme = "system"
    }

    func resetGlassAppearance() {
        glassAppearance = .default
    }

    private func persistGlassAppearance() {
        if let data = try? JSONEncoder().encode(glassAppearance) {
            UserDefaults.standard.set(data, forKey: Keys.glassAppearance)
        }
    }

    private static func loadGlassAppearance(from defaults: UserDefaults) -> GlassAppearance {
        guard let data = defaults.data(forKey: Keys.glassAppearance),
              let decoded = try? JSONDecoder().decode(GlassAppearance.self, from: data) else {
            return .default
        }
        return decoded
    }
}

extension Notification.Name {
    static let grokGlassAppearanceDidChange = Notification.Name("grokGlassAppearanceDidChange")
}