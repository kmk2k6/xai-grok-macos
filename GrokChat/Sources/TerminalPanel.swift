//
//  TerminalPanel.swift
//  GrokChat
//
//  Experimental, opt-in terminal panel. Hosts a SwiftTerm
//  LocalProcessTerminalView running the user's login shell in ~/src. It docks
//  at the bottom of the window content so it never covers grok.com's own
//  controls (the web view is inset above it). Off by default.
//

import AppKit
import SwiftTerm

/// Owns the terminal view and its docked container. Created lazily the first
/// time the panel is enabled so there is zero cost (and no spawned shell) while
/// the feature is off.
final class TerminalPanelController: NSObject {
    /// UserDefaults key for the Settings toggle. Default is OFF.
    static let enabledKey = "grok.terminalPanelEnabled"

    /// Height of the docked panel in points.
    static let panelHeight: CGFloat = 220

    /// Whether the panel is currently turned on in Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    private(set) var container: NSView?
    private var terminalView: LocalProcessTerminalView?
    private var started = false

    /// The working directory the shell starts in.
    private var startDirectory: String {
        let src = (NSHomeDirectory() as NSString).appendingPathComponent("src")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue {
            return src
        }
        return NSHomeDirectory()
    }

    /// Build (once) and return the container view holding the terminal.
    func makeContainerIfNeeded() -> NSView {
        if let container { return container }

        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        // A thin top border so the panel reads as separate chrome.
        let border = NSView(frame: .zero)
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        border.autoresizingMask = [.width, .minYMargin]
        box.addSubview(border)

        let term = LocalProcessTerminalView(frame: .zero)
        term.autoresizingMask = [.width, .height]
        box.addSubview(term)

        self.container = box
        self.terminalView = term
        self.borderView = border
        return box
    }

    private var borderView: NSView?

    /// Start the login shell in ~/src the first time the panel becomes visible.
    func startIfNeeded() {
        guard !started, let term = terminalView else { return }
        started = true
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        FileManager.default.changeCurrentDirectoryPath(startDirectory)
        // A leading '-' makes it a login shell.
        term.startProcess(executable: shell, args: ["-\(shellName)"], environment: nil)
    }

    /// Lay the panel out at the bottom of `content`, returning the Y offset the
    /// web content should leave clear (i.e. the panel height). When the panel is
    /// disabled it removes itself and returns 0.
    @discardableResult
    func layout(in content: NSView) -> CGFloat {
        guard Self.isEnabled else {
            container?.removeFromSuperview()
            return 0
        }
        let box = makeContainerIfNeeded()
        let height = min(Self.panelHeight, max(0, content.bounds.height - 80))
        box.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: height)
        box.autoresizingMask = [.width, .maxYMargin]
        borderView?.frame = NSRect(x: 0, y: height - 1, width: content.bounds.width, height: 1)
        terminalView?.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: height - 1)
        if box.superview !== content {
            content.addSubview(box)
        } else {
            box.removeFromSuperview()
            content.addSubview(box)
        }
        startIfNeeded()
        return height
    }
}
