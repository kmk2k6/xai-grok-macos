import AppKit

extension Notification.Name {
    static let grokOpenShellTerminal = Notification.Name("grokOpenShellTerminal")
    static let grokSendTerminalSelection = Notification.Name("grokSendTerminalSelection")
    static let grokTerminalAppearanceChanged = Notification.Name("grokTerminalAppearanceChanged")
}

enum GrokTerminalTheme {
    static let fontSizeKey = "grok.terminal.fontSize"
    static let themeKey = "grok.terminal.theme"
    static let pendingPathKey = "grok.shell.pendingPath"

    static var fontSize: CGFloat {
        let raw = UserDefaults.standard.object(forKey: fontSizeKey) as? Double ?? 13
        return CGFloat(min(24, max(9, raw)))
    }

    static var prefersLight: Bool {
        UserDefaults.standard.string(forKey: themeKey) == "light"
    }

    static var palette: (foreground: NSColor, background: NSColor) {
        if prefersLight {
            return (NSColor(calibratedWhite: 0.1, alpha: 1), NSColor(calibratedWhite: 0.96, alpha: 1))
        }
        return (NSColor(calibratedWhite: 0.9, alpha: 1), NSColor(calibratedWhite: 0.07, alpha: 1))
    }
    static var backgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.06, alpha: 1)
                : NSColor(calibratedWhite: 0.98, alpha: 1)
        }
    }

    static var foregroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.88, alpha: 1)
                : NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    }
}
