//
//  AppDelegate.swift
//  Grok for Mac
//
//  Created by Brandon Charleson on 2025.
//  Copyright © 2025 Brandon Charleson. All rights reserved.
//
//  https://github.com/bcharleson/xai-grok
//  https://x.com/brandon_ai
//
//  This file is part of Grok for Mac, an unofficial native macOS client
//  for xAI's Grok AI. Grok is a product of xAI (https://x.ai).
//

import Cocoa
import Combine
import WebKit
import Sparkle
import SwiftUI

enum AppMode {
    case chat
    case developer
    case console
    case grokipedia
    case xTwitter
    case chatX  // chat.x.com - X's native chat interface
}

// Custom WKWebView that prevents system beep when typing special characters
// The beep occurs when macOS can't find a menu item matching a key combination
class SilentWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only intercept key events that would cause a beep
        // Let the WebView handle text input directly

        // If this is a typing event (character keys with Shift for symbols like @),
        // don't let the menu system try to match it
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Shift+number keys (for symbols like @, #, $, etc.) - let WebView handle directly
        if flags == .shift {
            // Return false to let the event pass through to the web content
            // The WebView will handle the character input
            return false
        }

        // For Command shortcuts, let the menu system handle them
        if flags.contains(.command) {
            return super.performKeyEquivalent(with: event)
        }

        // For all other cases, pass to super
        return super.performKeyEquivalent(with: event)
    }

    // Override keyDown to ensure key events reach the web content
    override func keyDown(with event: NSEvent) {
        // Pass all key events to the web content
        super.keyDown(with: event)
    }
}

// Shared observable state for mode switching
class AppModeState: ObservableObject {
    static let shared = AppModeState()
    @Published var currentMode: AppMode = .chat
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    // View Management
    var mainContainerView: NSView!
    /// Titlebar/toolbar glass strip only — web content stays opaque.
    var chromeEffectView: NSVisualEffectView!
    var chromeTintView: NSView!
    var chromeBorderView: NSView!
    private var glassObservation: AnyCancellable?
    private var windowFrameObservation: NSObjectProtocol?
    private var consoleWebViewLoaded = false
    private var titlebarBackgroundView: NSView?
    var webView: WKWebView!
    var chatTabs: [GrokChatTab] = []
    var activeChatTabIndex: Int = 0
    var chatTabStrip: GrokChatTabStrip?
    var grokipediaWebView: WKWebView!
    var xWebView: WKWebView!
    var authPopupWindows: [NSWindow] = []
    var chatXWebView: WKWebView!  // chat.x.com - shares cookies with xWebView
    var devViewController: NSHostingController<BuildRootView>?
    var currentMode: AppMode = .chat {
        didSet {
            AppModeState.shared.currentMode = currentMode
        }
    }
    private var lastEmptyBodyReloadDate: Date = .distantPast
    
    var inputWindow: InputWindow?
    /// Prompt waiting to be typed into a fresh grok.com chat after navigation.
    var pendingQuickAsk: String?
    var pendingAttachments: [GrokAttachment] = []
    var pendingAttachmentFallback: String?
    var settingsWindow: SettingsWindow?
    var promptLibraryPanel: PromptLibraryPanel?
    var findBar: GrokFindBar?
    var zenMode = false
    var pipWindow: NSWindow?
    var pipWebView: WKWebView?
    var aboutWindow: NSWindow?
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set Safety Mode default to ON if not already set
        if UserDefaults.standard.object(forKey: "safetyEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "safetyEnabled")
        }

        GrokGhosttyBootstrap.configureEnvironment()
        GrokGhosttyApp.shared.initializeIfNeeded()
        
        // Initialize Sparkle Update Manager early
        _ = UpdateManager.shared
        
        // Setup the main menu with Edit menu for copy/paste
        setupMainMenu()
        
        // Setup Menu Bar Icon
        setupStatusBar()
        
        // Setup HotKey Manager
        HotKeyManager.shared.delegate = self
        HotKeyManager.shared.setup()
        GrokAskService.shared.start()
        GrokUsageBadge.prepareFocusStatus()
        
        // Create the main window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let grokChromeBlack = GlassAppearance.solidMatteNSColor
        window.title = "" // Hide title for cleaner look
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.setFrameAutosaveName("GrokMainWindow")
        window.backgroundColor = grokChromeBlack
        window.minSize = NSSize(width: 800, height: 600)
        window.isOpaque = true
        window.isReleasedWhenClosed = false // Keep window in memory when closed
        window.delegate = self
        
        // Configure WebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        // Enable media capture (microphone, camera)
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Route web “Grok Build” promo CTAs into the native harness.
        config.userContentController.add(self, name: WebToBuildBridge.messageHandlerName)
        config.userContentController.add(self, name: GrokUsageBadge.messageHandlerName)
        GrokUsageBadge.installUserScript(into: config.userContentController)
        
        // Use SilentWebView to prevent keyboard beeps when typing special characters
        webView = SilentWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.uiDelegate = self
        webView.navigationDelegate = self // For downloads

        // Create toolbar with compact style for tighter appearance
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact // Tighter/smaller toolbar

        // Container: opaque web content + optional glass strip over titlebar/toolbar only
        mainContainerView = NSView(frame: .zero)
        mainContainerView.autoresizingMask = [.width, .height]
        mainContainerView.wantsLayer = true
        mainContainerView.layer?.backgroundColor = grokChromeBlack.cgColor
        window.contentView = mainContainerView

        chromeEffectView = NSVisualEffectView(frame: .zero)
        chromeEffectView.blendingMode = .behindWindow
        chromeEffectView.state = .active
        chromeEffectView.autoresizingMask = [.width, .maxYMargin]
        chromeEffectView.wantsLayer = true
        mainContainerView.addSubview(chromeEffectView)

        chromeTintView = NSView(frame: .zero)
        chromeTintView.wantsLayer = true
        chromeTintView.autoresizingMask = [.width, .maxYMargin]
        mainContainerView.addSubview(chromeTintView)

        chromeBorderView = NSView(frame: .zero)
        chromeBorderView.wantsLayer = true
        chromeBorderView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        chromeBorderView.autoresizingMask = [.width, .maxYMargin]
        mainContainerView.addSubview(chromeBorderView)

        webView.autoresizingMask = [.width, .height]
        webView.frame = mainContainerView.bounds
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = grokChromeBlack.cgColor
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = grokChromeBlack
        }
        mainContainerView.addSubview(webView, positioned: .below, relativeTo: chromeEffectView)
        adoptInitialChatTab()

        // Pre-load Developer View (Grok Build Agent)
        let devView = NSHostingController(rootView: BuildRootView())
        devView.view.autoresizingMask = [.width, .height]
        devView.view.frame = mainContainerView.bounds
        self.devViewController = devView

        // Setup Grokipedia WebView (separate config for isolated session)
        let grokipediaConfig = WKWebViewConfiguration()
        grokipediaConfig.websiteDataStore = .default()
        grokipediaConfig.mediaTypesRequiringUserActionForPlayback = []
        let grokipediaPrefs = WKWebpagePreferences()
        grokipediaPrefs.allowsContentJavaScript = true
        grokipediaConfig.defaultWebpagePreferences = grokipediaPrefs

        // Use SilentWebView for Grokipedia too
        grokipediaWebView = SilentWebView(frame: .zero, configuration: grokipediaConfig)
        grokipediaWebView.allowsBackForwardNavigationGestures = true
        grokipediaWebView.allowsLinkPreview = true
        grokipediaWebView.uiDelegate = self
        grokipediaWebView.navigationDelegate = self
        grokipediaWebView.autoresizingMask = [.width, .height]
        grokipediaWebView.frame = mainContainerView.bounds
        // Don't add as subview initially - just load

        // Pre-load Grokipedia
        if let grokipediaURL = URL(string: "https://grokipedia.com") {
            grokipediaWebView.load(URLRequest(url: grokipediaURL))
        }

        // Setup X.com WebView (separate config for isolated session)
        let xConfig = WKWebViewConfiguration()
        xConfig.websiteDataStore = .default()
        xConfig.mediaTypesRequiringUserActionForPlayback = []
        let xPrefs = WKWebpagePreferences()
        xPrefs.allowsContentJavaScript = true
        xConfig.defaultWebpagePreferences = xPrefs

        // Use SilentWebView for X.com - prevents beep when typing @mentions
        xWebView = SilentWebView(frame: .zero, configuration: xConfig)
        xWebView.allowsBackForwardNavigationGestures = true
        xWebView.allowsLinkPreview = true
        xWebView.uiDelegate = self
        xWebView.navigationDelegate = self
        xWebView.autoresizingMask = [.width, .height]
        xWebView.frame = mainContainerView.bounds

        // Pre-load X.com
        if let xURL = URL(string: "https://x.com") {
            xWebView.load(URLRequest(url: xURL))
        }

        // Setup Chat.X WebView (shares cookies/session with xWebView via same dataStore)
        let chatXConfig = WKWebViewConfiguration()
        chatXConfig.websiteDataStore = xConfig.websiteDataStore  // Share cookies with X.com
        chatXConfig.mediaTypesRequiringUserActionForPlayback = []
        let chatXPrefs = WKWebpagePreferences()
        chatXPrefs.allowsContentJavaScript = true
        chatXConfig.defaultWebpagePreferences = chatXPrefs

        // Use SilentWebView for chat.x.com - same pattern as X.com
        chatXWebView = SilentWebView(frame: .zero, configuration: chatXConfig)
        chatXWebView.allowsBackForwardNavigationGestures = true
        chatXWebView.allowsLinkPreview = true
        chatXWebView.uiDelegate = self
        chatXWebView.navigationDelegate = self
        chatXWebView.autoresizingMask = [.width, .height]
        chatXWebView.frame = mainContainerView.bounds

        // Pre-load chat.x.com
        if let chatXURL = URL(string: "https://chat.x.com") {
            chatXWebView.load(URLRequest(url: chatXURL))
        }

        // Load Grok Chat
        if let url = URL(string: "https://grok.com") {
            webView.load(URLRequest(url: url))
        }

        applyGlassChrome()
        glassObservation = SettingsManager.shared.$glassAppearance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyGlassChrome() }
        windowFrameObservation = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in self?.layoutChromeStrip() }
        
        // Show window and make key
        window.makeKeyAndOrderFront(nil)
        
        // Make the webview the first responder
        window.makeFirstResponder(webView)
        applyStoredZoom()
        refreshDockBadge()
        
        // Initialize Input Window (hidden by default)
        inputWindow = InputWindow()
    }

    /// Solid #000000 when glass is off or see-through is low. Frosted strip over the titlebar when dialed up.
    func applyGlassChrome() {
        guard window != nil, mainContainerView != nil, chromeEffectView != nil else { return }
        if currentMode == .developer {
            updateWindowChrome(for: .developer)
            return
        }
        let g = SettingsManager.shared.glassAppearance
        let solid = GlassAppearance.solidMatteNSColor

        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar?.isVisible = true

        mainContainerView.wantsLayer = true
        applyOpaqueWebChrome(solid)
        applyTitlebarBackground(g.prefersSolidChrome ? solid : .clear)

        if g.prefersSolidChrome {
            window.isOpaque = true
            window.backgroundColor = solid
            mainContainerView.layer?.backgroundColor = solid.cgColor
            chromeEffectView.isHidden = true
            chromeTintView.isHidden = true
            chromeBorderView.isHidden = true
        } else {
            window.isOpaque = false
            window.backgroundColor = .clear
            mainContainerView.layer?.backgroundColor = solid.cgColor
            chromeEffectView.isHidden = false
            chromeEffectView.material = g.nsMaterial
            chromeEffectView.alphaValue = CGFloat(g.windowEffectOpacity)
            chromeTintView.isHidden = false
            chromeTintView.layer?.backgroundColor = solid.withAlphaComponent(CGFloat(g.tintOpacity)).cgColor
            let borderAlpha = CGFloat(g.borderOpacity(for: .dark))
            chromeBorderView.isHidden = borderAlpha < 0.01
            chromeBorderView.layer?.backgroundColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        }
        layoutChromeStrip()
    }

    private func applyTitlebarBackground(_ color: NSColor) {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }
        var cursor: NSView? = closeButton
        var titlebarHost: NSView?
        while let view = cursor {
            if view.frame.width >= window.frame.width * 0.8,
               view.frame.height >= 30, view.frame.height <= 120 {
                titlebarHost = view
                break
            }
            cursor = view.superview
        }
        guard let host = titlebarHost ?? closeButton.superview?.superview else { return }

        let overlay: NSView
        if let existing = titlebarBackgroundView, existing.superview === host {
            overlay = existing
        } else {
            titlebarBackgroundView?.removeFromSuperview()
            overlay = NSView(frame: host.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            host.addSubview(overlay, positioned: .below, relativeTo: nil)
            titlebarBackgroundView = overlay
        }
        overlay.frame = host.bounds
        overlay.layer?.backgroundColor = color.cgColor
    }

    private func styleOpaqueWebView(_ wv: WKWebView, solid: NSColor) {
        wv.setValue(false, forKey: "drawsBackground")
        wv.wantsLayer = true
        wv.layer?.backgroundColor = solid.cgColor
        if #available(macOS 12.0, *) {
            wv.underPageBackgroundColor = solid
        }
    }

    private func applyOpaqueWebChrome(_ solid: NSColor) {
        styleOpaqueWebView(webView, solid: solid)
        for tab in chatTabs {
            styleOpaqueWebView(tab.webView, solid: solid)
        }
        styleOpaqueWebView(grokipediaWebView, solid: solid)
        styleOpaqueWebView(xWebView, solid: solid)
        styleOpaqueWebView(chatXWebView, solid: solid)
        if consoleWebViewLoaded {
            styleOpaqueWebView(consoleWebView, solid: solid)
        }
    }

    func layoutChromeStrip() {
        guard currentMode != .developer,
              let content = mainContainerView, window != nil,
              chromeEffectView != nil else { return }
        let layout = window.contentLayoutRect
        var chromeHeight = max(0, content.bounds.height - layout.height)
        if chromeHeight < 1 {
            chromeHeight = 52
        }
        let width = content.bounds.width
        let y = content.bounds.height - chromeHeight
        chromeEffectView.frame = NSRect(x: 0, y: y, width: width, height: chromeHeight)
        chromeTintView.frame = chromeEffectView.frame
        chromeBorderView.frame = NSRect(x: 0, y: y, width: width, height: 1)
        layoutChatTabs()
        layoutFindBar()
        if zenMode && currentMode == .chat {
            chromeEffectView.isHidden = true
            chromeTintView.isHidden = true
            chromeBorderView.isHidden = true
            window.toolbar?.isVisible = false
            chatTabStrip?.isHidden = true
            webView.frame = content.bounds
            return
        }
        content.addSubview(chromeEffectView, positioned: .above, relativeTo: nil)
        content.addSubview(chromeTintView, positioned: .above, relativeTo: chromeEffectView)
        content.addSubview(chromeBorderView, positioned: .above, relativeTo: chromeTintView)
    }
    
    func setupStatusBar() {
        // Check if user wants menu bar icon (default to true)
        if !UserDefaults.standard.bool(forKey: "showMenuBarIcon") && UserDefaults.standard.object(forKey: "showMenuBarIcon") != nil {
            return // User explicitly disabled it
        }
        
        // Set default to true on first launch
        if UserDefaults.standard.object(forKey: "showMenuBarIcon") == nil {
            UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
        }
        
        showStatusBar()
    }
    
    func showStatusBar() {
        if statusItem != nil { return } // Already showing
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Grok usage")
            bolt?.isTemplate = true
            button.image = bolt
            button.imagePosition = .imageLeading
            button.title = ""
            button.setAccessibilityLabel("Grok usage")
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshUsageStatusButton()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(usagePercentChanged(_:)),
            name: .grokUsagePercentDidChange,
            object: nil
        )
    }

    @objc private func usagePercentChanged(_ note: Notification) {
        refreshUsageStatusButton()
        refreshDockBadge()
    }

    func refreshDockBadge() {
        guard UserDefaults.standard.bool(forKey: "grok.dockBadge.enabled") else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        if let percent = UserDefaults.standard.object(forKey: GrokUsageBadge.percentStorageKey) as? Int {
            NSApp.dockTile.badgeLabel = "\(percent)"
        }
    }

    func refreshUsageStatusButton() {
        guard let button = statusItem?.button else { return }
        if let percent = UserDefaults.standard.object(forKey: GrokUsageBadge.percentStorageKey) as? Int {
            button.title = " \(percent)%"
            button.setAccessibilityLabel("Grok usage \(percent) percent")
        } else {
            button.title = ""
            button.setAccessibilityLabel("Grok usage")
        }
    }

    private func rebuildStatusMenu(recent: [(title: String, href: String)]? = nil) {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        if let percent = UserDefaults.standard.object(forKey: GrokUsageBadge.percentStorageKey) as? Int {
            let usage = NSMenuItem(title: "Usage \(percent)%", action: nil, keyEquivalent: "")
            usage.isEnabled = false
            menu.addItem(usage)
        } else {
            let usage = NSMenuItem(title: "Usage unavailable", action: nil, keyEquivalent: "")
            usage.isEnabled = false
            menu.addItem(usage)
        }
        menu.addItem(NSMenuItem.separator())
        let header = NSMenuItem(title: "Recent chats", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let recent, !recent.isEmpty {
            for chat in recent.prefix(8) {
                let item = NSMenuItem(title: chat.title, action: #selector(openRecentChat(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.href
                menu.addItem(item)
            }
        } else if recent == nil {
            let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        } else {
            let empty = NSMenuItem(title: "No recent chats", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(NSMenuItem.separator())
        let newChat = NSMenuItem(title: "New Chat", action: #selector(newChat(_:)), keyEquivalent: "")
        newChat.target = self
        menu.addItem(newChat)
        let quickAsk = NSMenuItem(title: "Quick Ask", action: #selector(showQuickAsk(_:)), keyEquivalent: "")
        quickAsk.target = self
        menu.addItem(quickAsk)
        menu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Grok", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc func openRecentChat(_ sender: NSMenuItem) {
        guard let href = sender.representedObject as? String, let url = URL(string: href) else { return }
        showMainWindow(nil)
        updateMode(to: .chat)
        webView.load(URLRequest(url: url))
    }

    private func scrapeRecentChats() {
        guard webView != nil else {
            rebuildStatusMenu(recent: [])
            return
        }
        let js = """
        (function() {
            var nodes = document.querySelectorAll('a[href]');
            var seen = {};
            var out = [];
            for (var i = 0; i < nodes.length; i++) {
                var link = nodes[i];
                var href = link.href || '';
                if (!/\\/(chat|c)\\//.test(href) && href.indexOf('grok.com') === -1) continue;
                if (!/grok\\.com/.test(href)) continue;
                if (href.indexOf('/chat') === -1 && href.indexOf('/c/') === -1) continue;
                var title = (link.innerText || link.getAttribute('aria-label') || '').trim().split('\\n')[0];
                if (!title || title.length > 80 || seen[href]) continue;
                seen[href] = true;
                out.push({title: title, href: href});
                if (out.length >= 8) break;
            }
            return JSON.stringify(out);
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            var chats: [(title: String, href: String)] = []
            if let text = result as? String, let data = text.data(using: .utf8),
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                chats = rows.compactMap { row in
                    guard let title = row["title"], let href = row["href"] else { return nil }
                    return (title, href)
                }
            }
            self.rebuildStatusMenu(recent: chats)
        }
    }
    
    func hideStatusBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    @objc func showMainWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Grok", action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",") // Cmd+, for settings
        
        // Check for Updates menu item
        let updateMenuItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateMenuItem.target = self
        appMenu.addItem(updateMenuItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Grok", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Chat", action: #selector(newChat(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newChatTab(_:)), keyEquivalent: "t")
        let promptItem = NSMenuItem(
            title: "Prompt Library",
            action: #selector(showPromptLibrary(_:)),
            keyEquivalent: "p"
        )
        promptItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(promptItem)
        fileMenu.addItem(withTitle: "Open Project Folder…", action: #selector(openProjectFolder(_:)), keyEquivalent: "o")
        let jumpItem = NSMenuItem(
            title: "Jump to Session…",
            action: #selector(openBuildSessionSwitcher(_:)),
            keyEquivalent: "k"
        )
        fileMenu.addItem(jumpItem)
        let archiveItem = NSMenuItem(
            title: "Archive Current Session",
            action: #selector(archiveBuildSession(_:)),
            keyEquivalent: "w"
        )
        archiveItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(archiveItem)
        let sendToBuildItem = NSMenuItem(
            title: "Send to Build",
            action: #selector(sendToBuild(_:)),
            keyEquivalent: "b"
        )
        sendToBuildItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(sendToBuildItem)
        fileMenu.addItem(withTitle: "Export Chat…", action: #selector(exportChat(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Quick Ask", action: #selector(showQuickAsk(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Quick Query", action: #selector(toggleInputWindow(_:)), keyEquivalent: " ") // Option+Space is handled by HotKeyManager, this is a menu item backup
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(performClose(_:)), keyEquivalent: "w")
        
        // Edit Menu - Critical for copy/paste
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(showFind(_:)), keyEquivalent: "f")
        
        // View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reload(_:)), keyEquivalent: "r")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "=") // Cmd+= is standard
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(NSMenuItem.separator())
        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        let zenItem = NSMenuItem(
            title: "Focus Mode",
            action: #selector(toggleZen(_:)),
            keyEquivalent: "f"
        )
        zenItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(zenItem)
        
        // History Menu
        let historyMenuItem = NSMenuItem()
        mainMenu.addItem(historyMenuItem)
        let historyMenu = NSMenu(title: "History")
        historyMenuItem.submenu = historyMenu
        historyMenu.addItem(withTitle: "Back", action: #selector(goBack(_:)), keyEquivalent: "[")
        historyMenu.addItem(withTitle: "Forward", action: #selector(goForward(_:)), keyEquivalent: "]")
        historyMenu.addItem(NSMenuItem.separator())
        historyMenu.addItem(withTitle: "Home", action: #selector(goHome(_:)), keyEquivalent: "H")
        historyMenu.addItem(NSMenuItem.separator())
        let prevProject = NSMenuItem(
            title: "Previous Build Project",
            action: #selector(buildPreviousProject(_:)),
            keyEquivalent: "["
        )
        prevProject.keyEquivalentModifierMask = [.command, .shift]
        historyMenu.addItem(prevProject)
        let nextProject = NSMenuItem(
            title: "Next Build Project",
            action: #selector(buildNextProject(_:)),
            keyEquivalent: "]"
        )
        nextProject.keyEquivalentModifierMask = [.command, .shift]
        historyMenu.addItem(nextProject)
        let prevThread = NSMenuItem(
            title: "Previous Build Chat",
            action: #selector(buildPreviousThread(_:)),
            keyEquivalent: "["
        )
        prevThread.keyEquivalentModifierMask = [.command, .option]
        historyMenu.addItem(prevThread)
        let nextThread = NSMenuItem(
            title: "Next Build Chat",
            action: #selector(buildNextThread(_:)),
            keyEquivalent: "]"
        )
        nextThread.keyEquivalentModifierMask = [.command, .option]
        historyMenu.addItem(nextThread)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Mini Chat", action: #selector(toggleMiniChat(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        for number in 1...9 {
            let item = NSMenuItem(
                title: "Chat Tab \(number)",
                action: #selector(selectChatTabFromMenu(_:)),
                keyEquivalent: "\(number)"
            )
            item.target = self
            item.tag = number
            windowMenu.addItem(item)
        }
        
        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
    }
    
    // Don't quit when the "x" is clicked, just close the window
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running for hotkey support
    }
    
    // Re-open window when clicking Dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Check if window exists and is valid
            if window == nil || !window.isVisible {
                window?.makeKeyAndOrderFront(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    @objc func performClose(_ sender: Any?) {
        if currentMode == .chat, chatTabs.count > 1 {
            closeChatTab(at: activeChatTabIndex)
            return
        }
        window?.orderOut(sender)
    }
    
    @objc func checkForUpdates(_ sender: Any?) {
        UpdateManager.shared.checkForUpdates(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleInputWindow(_ sender: Any?) {
        guard let panel = inputWindow else { return }
        
        if panel.isVisible {
            panel.orderOut(nil)
            // If main window is hidden, we effectively hide the app
            if !window.isVisible {
                NSApp.hide(nil)
            }
        } else {
            // Logic to prevent main window from jumping to front if we just want Spotlight
            // Check if app is already active
            let wasActive = NSApp.isActive
            
            if !wasActive {
                // If coming from background, we ONLY want the input window
                // So momentarily hide the main window if it's open, to prevent it jumping up
                if window.isVisible {
                    window.orderOut(nil)
                }
            }
            
            // Center floating panel on screen
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let panelRect = panel.frame
                let x = screenRect.midX - (panelRect.width / 2)
                let y = screenRect.midY + (screenRect.height / 4)
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            // Show panel on top without affecting main window
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeFirstResponder(panel.textField)
        }
    }
    
    func submitQuery(_ query: String, to mode: AppMode = .chat) {
        // 1. Hide input window
        inputWindow?.orderOut(nil)
        
        // 2. Show main window and switch to target mode
        window.makeKeyAndOrderFront(nil)
        window.alphaValue = 1.0 // Ensure it's visible
        NSApp.activate(ignoringOtherApps: true)
        updateMode(to: mode)
        
        // 3. Route based on mode
        switch mode {
        case .xTwitter:
            // Search on X.com
            let searchURL = "https://x.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            if let url = URL(string: searchURL) {
                xWebView.load(URLRequest(url: url))
            }

        case .chatX:
            // Send query to chat.x.com - use similar JS injection as grok.com
            let escapedQuery = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let js = """
            (function() {
                console.log('[ChatX] Starting injection...');

                // Find the input element
                var input = document.querySelector('textarea') ||
                            document.querySelector('[contenteditable="true"]') ||
                            document.querySelector('input[type="text"]');

                if (!input) {
                    console.log('[ChatX] No input found!');
                    return;
                }

                input.focus();

                // Set value based on element type
                if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
                    const valueSetter = Object.getOwnPropertyDescriptor(
                        input.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype,
                        'value'
                    ).set;
                    valueSetter.call(input, "\(escapedQuery)");
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                } else {
                    input.textContent = "\(escapedQuery)";
                    input.dispatchEvent(new InputEvent('input', { bubbles: true, data: "\(escapedQuery)" }));
                }

                // Wait for React to process, then submit
                setTimeout(() => {
                    var allButtons = document.querySelectorAll('button');
                    var submitBtn = null;

                    for (var btn of allButtons) {
                        var label = btn.getAttribute('aria-label') || '';
                        var text = btn.textContent || '';
                        if (label.toLowerCase().includes('send') || text.toLowerCase().includes('send')) {
                            submitBtn = btn;
                            break;
                        }
                    }

                    if (!submitBtn) {
                        submitBtn = document.querySelector('button[type="submit"]') ||
                                    document.querySelector('form button:last-child');
                    }

                    if (submitBtn && !submitBtn.disabled) {
                        submitBtn.click();
                    } else {
                        // Simulate Enter key
                        var enterEvent = new KeyboardEvent('keydown', {
                            bubbles: true, cancelable: true,
                            key: 'Enter', code: 'Enter', keyCode: 13, which: 13
                        });
                        input.dispatchEvent(enterEvent);
                    }
                }, 200);
            })();
            """

            // Wait for page to load, then inject
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.chatXWebView.evaluateJavaScript(js, completionHandler: nil)
            }

        case .developer:
            // Send to Grok Build via notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SpotlightQuery"), object: query)
            }

        case .grokipedia:
            // React-compatible input value setting + button click
            let escapedQuery = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let js = """
            (function() {
                var input = document.querySelector('input[type="text"]') || 
                            document.querySelector('textarea') ||
                            document.querySelector('input');
                
                if (input) {
                    // React-compatible value setting
                    var nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                        window.HTMLInputElement.prototype, 
                        'value'
                    ).set;
                    nativeInputValueSetter.call(input, "\(escapedQuery)");
                    
                    // Trigger React events
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                    
                    // Wait longer, then click submit button
                    setTimeout(() => {
                        var button = document.querySelector('button[type="submit"]') ||
                                    input.parentElement.querySelector('button') ||
                                    input.closest('form')?.querySelector('button');
                        
                        if (button) {
                            button.click();
                        }
                    }, 300);
                }
            })();
            """
            
            // Wait for page to load, then inject
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.grokipediaWebView.evaluateJavaScript(js, completionHandler: nil)
            }
            
        default: // .chat
            // Inject JS to type and submit to grok.com
            let js = """
            (function() {
                console.log('[GrokApp] Starting injection...');
                
                // Find the input element (textarea or contenteditable)
                var input = document.querySelector('textarea') || 
                            document.querySelector('[contenteditable="true"]') ||
                            document.querySelector('input[type="text"]');
                
                console.log('[GrokApp] Found input:', input);
                
                if (!input) {
                    console.log('[GrokApp] No input found!');
                    return;
                }
                
                input.focus();
                
                // Set value based on element type
                if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
                    const valueSetter = Object.getOwnPropertyDescriptor(
                        input.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype, 
                        'value'
                    ).set;
                    valueSetter.call(input, \(query.debugDescription));
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                } else {
                    // contenteditable
                    input.textContent = \(query.debugDescription);
                    input.dispatchEvent(new InputEvent('input', { bubbles: true, data: \(query.debugDescription) }));
                }
                
                console.log('[GrokApp] Value set, waiting...');
                
                // Wait for React/framework to process
                setTimeout(() => {
                    // Find ALL buttons and look for the submit one
                    var allButtons = document.querySelectorAll('button');
                    var submitBtn = null;
                    
                    console.log('[GrokApp] Found buttons:', allButtons.length);
                    
                    for (var btn of allButtons) {
                        var label = btn.getAttribute('aria-label') || '';
                        var text = btn.textContent || '';
                        console.log('[GrokApp] Button:', label, text);
                        
                        if (label.toLowerCase().includes('send') || 
                            text.toLowerCase().includes('send') ||
                            btn.querySelector('svg[class*="send"]')) {
                            submitBtn = btn;
                            break;
                        }
                    }
                    
                    // Also try common patterns
                    if (!submitBtn) {
                        submitBtn = document.querySelector('button[type="submit"]') ||
                                    document.querySelector('form button:last-child') ||
                                    document.querySelector('[data-testid="send-button"]');
                    }
                    
                    if (submitBtn && !submitBtn.disabled) {
                        console.log('[GrokApp] Clicking submit button');
                        submitBtn.click();
                    } else {
                        console.log('[GrokApp] No button found, simulating Enter');
                        // Simulate Enter key with all possible event properties
                        var enterEvent = new KeyboardEvent('keydown', {
                            bubbles: true,
                            cancelable: true,
                            key: 'Enter',
                            code: 'Enter',
                            keyCode: 13,
                            which: 13,
                            charCode: 13
                        });
                        input.dispatchEvent(enterEvent);
                        
                        // Also try form submission
                        var form = input.closest('form');
                        if (form) {
                            console.log('[GrokApp] Submitting form');
                            form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                        }
                    }
                }, 200);
            })();
            """
            
            webView.evaluateJavaScript(js) { (result, error) in
            #if DEBUG
            if let error = error {
                print("JS Injection Error: \(error)")
            } else {
                print("JS executed successfully")
            }
            #endif
            }
        }
    }
    
    // Navigation Methods - works for Chat, Grokipedia, X, and Chat.X
    private var activeWebView: WKWebView {
        switch currentMode {
        case .grokipedia: return grokipediaWebView
        case .xTwitter: return xWebView
        case .chatX: return chatXWebView
        case .console: return consoleWebView
        default: return webView
        }
    }

    private var zoomStorageKey: String { "grok.pageZoom.\(currentMode)" }

    private func persistZoom() {
        guard currentMode != .developer else { return }
        UserDefaults.standard.set(activeWebView.pageZoom, forKey: zoomStorageKey)
    }

    private func applyStoredZoom() {
        guard currentMode != .developer else { return }
        let stored = UserDefaults.standard.double(forKey: zoomStorageKey)
        guard stored >= 0.5, stored <= 3 else { return }
        activeWebView.pageZoom = stored
    }
    
    @objc func goBack(_ sender: Any?) { activeWebView.goBack() }
    @objc func goForward(_ sender: Any?) { activeWebView.goForward() }
    @objc func reload(_ sender: Any?) { activeWebView.reload() }
    @objc func goHome(_ sender: Any?) {
        switch currentMode {
        case .grokipedia:
            if let url = URL(string: "https://grokipedia.com") {
                grokipediaWebView.load(URLRequest(url: url))
            }
        case .xTwitter:
            if let url = URL(string: "https://x.com") {
                xWebView.load(URLRequest(url: url))
            }
        default:
            if let url = URL(string: "https://grok.com") {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - New Actions
    
    var zoomOverlay: NSVisualEffectView?
    var zoomTimer: Timer?
    
    func showZoomOverlay() {
        let percentage = Int(activeWebView.pageZoom * 100)
        
        // Remove existing
        zoomTimer?.invalidate()
        zoomOverlay?.removeFromSuperview()
        
        // Create Glass HUD
        let overlay = NSVisualEffectView()
        overlay.material = .hudWindow
        overlay.blendingMode = .withinWindow
        overlay.state = .active
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 10
        overlay.layer?.masksToBounds = true
        
        let width: CGFloat = 80
        let height: CGFloat = 40
        overlay.frame = NSRect(x: 0, y: 0, width: width, height: height)
        
        // Label
        let label = NSTextField(labelWithString: "\(percentage)%")
        label.font = NSFont.systemFont(ofSize: 15, weight: .bold) // Native looking font
        label.textColor = .labelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (height - 20) / 2, width: width, height: 20)
        overlay.addSubview(label)
        
        // Center in window
        if let contentView = window.contentView {
            let x = (contentView.bounds.width - width) / 2
            let y = (contentView.bounds.height - height) / 2
            overlay.frame.origin = NSPoint(x: x, y: y)
            contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        
        zoomOverlay = overlay
        
        // Fade out
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self?.zoomOverlay?.animator().alphaValue = 0
            }, completionHandler: {
                self?.zoomOverlay?.removeFromSuperview()
                self?.zoomOverlay = nil
            })
        }
    }
    
    @objc func newChat(_ sender: Any?) {
        if currentMode == .developer || currentMode == .console {
            showMainWindow(nil)
            NotificationCenter.default.post(name: .buildNewSession, object: nil)
            return
        }
        if let url = URL(string: "https://grok.com") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func openProjectFolder(_ sender: Any?) {
        showMainWindow(nil)
        updateMode(to: .developer)
        NotificationCenter.default.post(name: Notification.Name("OpenProjectFolder"), object: nil)
    }

    @objc func openBuildSessionSwitcher(_ sender: Any?) {
        showMainWindow(nil)
        updateMode(to: .developer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .buildOpenSessionSwitcher, object: nil)
        }
    }

    @objc func archiveBuildSession(_ sender: Any?) {
        guard currentMode == .developer || currentMode == .console else { return }
        NotificationCenter.default.post(name: .buildArchiveCurrentSession, object: nil)
    }

    @objc func buildNextProject(_ sender: Any?) {
        guard currentMode == .developer || currentMode == .console else { return }
        NotificationCenter.default.post(name: .buildSelectNextProject, object: nil)
    }

    @objc func buildPreviousProject(_ sender: Any?) {
        guard currentMode == .developer || currentMode == .console else { return }
        NotificationCenter.default.post(name: .buildSelectPreviousProject, object: nil)
    }

    @objc func buildNextThread(_ sender: Any?) {
        guard currentMode == .developer || currentMode == .console else { return }
        NotificationCenter.default.post(name: .buildSelectNextThread, object: nil)
    }

    @objc func buildPreviousThread(_ sender: Any?) {
        guard currentMode == .developer || currentMode == .console else { return }
        NotificationCenter.default.post(name: .buildSelectPreviousThread, object: nil)
    }
    
    @objc func zoomIn(_ sender: Any?) {
        guard currentMode != .developer else { return }
        activeWebView.pageZoom = min(3, activeWebView.pageZoom + 0.1)
        persistZoom()
        showZoomOverlay()
    }
    
    @objc func zoomOut(_ sender: Any?) {
        guard currentMode != .developer else { return }
        activeWebView.pageZoom = max(0.5, activeWebView.pageZoom - 0.1)
        persistZoom()
        showZoomOverlay()
    }
    
    @objc func resetZoom(_ sender: Any?) {
        guard currentMode != .developer else { return }
        activeWebView.pageZoom = 1.0
        persistZoom()
        showZoomOverlay()
    }

    
    lazy var consoleWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Use SilentWebView to prevent keyboard beeps
        let wv = SilentWebView(frame: .zero, configuration: config)
        if let url = URL(string: "https://console.x.ai/home") {
            wv.load(URLRequest(url: url))
        }
        wv.autoresizingMask = [.width, .height]
        let chrome = GlassAppearance.solidMatteNSColor
        wv.setValue(false, forKey: "drawsBackground")
        wv.wantsLayer = true
        wv.layer?.backgroundColor = chrome.cgColor
        if #available(macOS 12.0, *) {
            wv.underPageBackgroundColor = chrome
        }
        DispatchQueue.main.async { [weak self] in
            self?.consoleWebViewLoaded = true
            self?.applyGlassChrome()
        }
        return wv
    }()
    
    // MARK: - Mode Switching
    
    @objc func switchMode(_ sender: NSSegmentedControl) {
        let mode: AppMode
        switch sender.selectedSegment {
        case 0: mode = .chat
        case 1: mode = .developer
        case 2: mode = .console
        default: return
        }
        updateMode(to: mode)
    }
    
    func updateMode(to mode: AppMode) {
        if mode == currentMode {
            updateWindowChrome(for: mode)
            if mode == .developer, let devView = devViewController?.view {
                if devView.superview == nil {
                    mainContainerView.subviews.forEach { $0.removeFromSuperview() }
                    devView.frame = mainContainerView.bounds
                    mainContainerView.addSubview(devView)
                }
                NotificationCenter.default.post(name: .buildDidBecomeActive, object: nil)
            }
            return
        }
        currentMode = mode

        // Remove current view
        mainContainerView.subviews.forEach { $0.removeFromSuperview() }

        switch mode {
        case .chat:
            webView.frame = mainContainerView.bounds
            mainContainerView.addSubview(webView)
            // Recover from a cancelled/blank load (e.g. prior Build deep-link hijack).
            let urlString = webView.url?.absoluteString ?? ""
            if urlString.isEmpty || urlString == "about:blank" {
                if let url = URL(string: "https://grok.com") {
                    webView.load(URLRequest(url: url))
                }
            }
            window.makeFirstResponder(webView)
        case .developer:
            if let devView = devViewController?.view {
                devView.frame = mainContainerView.bounds
                mainContainerView.addSubview(devView)
                NotificationCenter.default.post(name: .buildDidBecomeActive, object: nil)
            }
        case .console:
            consoleWebView.frame = mainContainerView.bounds
            mainContainerView.addSubview(consoleWebView)
            window.makeFirstResponder(consoleWebView)
        case .grokipedia:
            grokipediaWebView.frame = mainContainerView.bounds
            mainContainerView.addSubview(grokipediaWebView)
            window.makeFirstResponder(grokipediaWebView)
        case .xTwitter:
            xWebView.frame = mainContainerView.bounds
            mainContainerView.addSubview(xWebView)
            window.makeFirstResponder(xWebView)
        case .chatX:
            chatXWebView.frame = mainContainerView.bounds
            mainContainerView.addSubview(chatXWebView)
            window.makeFirstResponder(chatXWebView)
        }
        updateWindowChrome(for: mode)
        applyStoredZoom()
    }

    private func updateWindowChrome(for mode: AppMode) {
        let isBuild = mode == .developer
        window.toolbar?.isVisible = true
        window.titleVisibility = .hidden
        if isBuild {
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.isOpaque = true
            chromeEffectView?.isHidden = true
            chromeTintView?.isHidden = true
            chromeBorderView?.isHidden = true
            return
        }
        applyGlassChrome()
    }
}

// MARK: - NSToolbarDelegate
extension AppDelegate: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        // Use smaller symbol configuration for compact buttons
        let smallConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        
        if itemIdentifier == NSToolbarItem.Identifier("back") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Back"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")?.withSymbolConfiguration(smallConfig)
            item.action = #selector(goBack(_:))
            item.target = self
            item.isBordered = true
            return item
        }
        
        if itemIdentifier == NSToolbarItem.Identifier("forward") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Forward"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")?.withSymbolConfiguration(smallConfig)
            item.action = #selector(goForward(_:))
            item.target = self
            item.isBordered = true
            return item
        }
        
        if itemIdentifier == NSToolbarItem.Identifier("reload") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Reload"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")?.withSymbolConfiguration(smallConfig)
            item.action = #selector(reload(_:))
            item.target = self
            item.isBordered = true
            return item
        }
        
        if itemIdentifier == NSToolbarItem.Identifier("settings") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?.withSymbolConfiguration(smallConfig)
            item.action = #selector(showSettings(_:))
            item.target = self
            item.isBordered = true
            return item
        }
        
        if itemIdentifier == NSToolbarItem.Identifier("transfer") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Send to Build"
            item.image = NSImage(systemSymbolName: "arrow.up.right.diamond", accessibilityDescription: "Send to Build")?.withSymbolConfiguration(smallConfig)
            item.action = #selector(sendToBuild(_:))
            item.target = self
            item.isBordered = true
            item.toolTip = "Send selection or page to Build (⌘⇧B). GitHub URLs clone & open."
            return item
        }
        
        if itemIdentifier == NSToolbarItem.Identifier("modeSwitch") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            
            let switcher = ToolbarModeSwitcher(onModeChange: { [weak self] newMode in
                self?.updateMode(to: newMode)
            })
            
            let view = NSHostingView(rootView: switcher)
            view.frame = NSRect(x: 0, y: 0, width: 336, height: 30) // X + Chat + Grok + Build + Grokipedia (exact previous logos + words)
            
            item.view = view
            return item
        }
        
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("back"),
            NSToolbarItem.Identifier("forward"),
            NSToolbarItem.Identifier("reload"),
            NSToolbarItem.Identifier("transfer"), // New Transfer Button
            .flexibleSpace,
            NSToolbarItem.Identifier("modeSwitch"), // The Toggle
            .flexibleSpace,
            NSToolbarItem.Identifier("settings")
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
    
    @objc func showAboutPanel(_ sender: Any?) {
        // If window already exists, just bring it to front
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Create custom About window using NSStackView for proper layout
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Grok for Mac"
        window.center()
        window.isReleasedWhenClosed = false // Prevent premature deallocation

        // Use NSStackView for reliable vertical layout
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 30, left: 40, bottom: 25, right: 40)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // App Icon
        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        stackView.addArrangedSubview(iconView)
        stackView.setCustomSpacing(20, after: iconView)

        // App Name
        let nameLabel = NSTextField(labelWithString: "Grok for Mac")
        nameLabel.font = .boldSystemFont(ofSize: 20)
        nameLabel.alignment = .center
        stackView.addArrangedSubview(nameLabel)

        // Version
        let versionLabel = NSTextField(labelWithString: "Version \(UpdateManager.shared.currentVersion)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        stackView.addArrangedSubview(versionLabel)
        stackView.setCustomSpacing(15, after: versionLabel)

        // Description
        let descLabel = NSTextField(labelWithString: "A free, open-source native macOS app for Grok AI.")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.alignment = .center
        stackView.addArrangedSubview(descLabel)
        stackView.setCustomSpacing(25, after: descLabel)

        // Open Source Header
        let openSourceHeader = NSTextField(labelWithString: "✦ Open Source Community Project")
        openSourceHeader.font = .systemFont(ofSize: 12, weight: .semibold)
        openSourceHeader.alignment = .center
        stackView.addArrangedSubview(openSourceHeader)

        // Community Message
        let communityMsg = NSTextField(labelWithString: "Contributions welcome! Report bugs or suggest features.")
        communityMsg.font = .systemFont(ofSize: 11)
        communityMsg.textColor = .secondaryLabelColor
        communityMsg.alignment = .center
        stackView.addArrangedSubview(communityMsg)
        stackView.setCustomSpacing(20, after: communityMsg)

        // GitHub Button
        let githubButton = NSButton(title: "View Source on GitHub", target: self, action: #selector(openGitHubRepo(_:)))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        githubButton.widthAnchor.constraint(equalToConstant: 200).isActive = true
        stackView.addArrangedSubview(githubButton)

        // Report Issue Button
        let issuesButton = NSButton(title: "Report an Issue", target: self, action: #selector(openGitHubIssues(_:)))
        issuesButton.bezelStyle = .rounded
        issuesButton.translatesAutoresizingMaskIntoConstraints = false
        issuesButton.widthAnchor.constraint(equalToConstant: 200).isActive = true
        stackView.addArrangedSubview(issuesButton)
        stackView.setCustomSpacing(25, after: issuesButton)

        // Credits
        let creditsLabel = NSTextField(labelWithString: "Built by Brandon Charleson")
        creditsLabel.font = .systemFont(ofSize: 11)
        creditsLabel.textColor = .secondaryLabelColor
        creditsLabel.alignment = .center
        stackView.addArrangedSubview(creditsLabel)

        // X Profile Button
        let xButton = NSButton(title: "@brandon_ai on 𝕏", target: self, action: #selector(openXProfileInApp(_:)))
        xButton.bezelStyle = .rounded
        xButton.controlSize = .small
        stackView.addArrangedSubview(xButton)
        stackView.setCustomSpacing(20, after: xButton)

        // Disclaimer - Use NSFontDescriptor for safe italic font creation
        let disclaimerLabel = NSTextField(labelWithString: "Unofficial app. Grok is a product of xAI.")
        let italicDescriptor = NSFont.systemFont(ofSize: 10).fontDescriptor.withSymbolicTraits(.italic)
        if let italicFont = NSFont(descriptor: italicDescriptor, size: 10) {
            disclaimerLabel.font = italicFont
        } else {
            // Fallback to regular font if italic creation fails
            disclaimerLabel.font = .systemFont(ofSize: 10)
        }
        disclaimerLabel.textColor = .tertiaryLabelColor
        disclaimerLabel.alignment = .center
        stackView.addArrangedSubview(disclaimerLabel)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: "© 2025 Brandon Charleson • MIT License")
        copyrightLabel.font = .systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        stackView.addArrangedSubview(copyrightLabel)

        // Add stack to window
        window.contentView?.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor)
        ])

        // Store reference to prevent deallocation
        self.aboutWindow = window

        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func openGitHubRepo(_ sender: Any?) {
        if let url = URL(string: "https://github.com/bcharleson/xai-grok-cli") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitHubIssues(_ sender: Any?) {
        if let url = URL(string: "https://github.com/bcharleson/xai-grok-cli/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openXProfileInApp(_ sender: Any?) {
        // Close About window first
        aboutWindow?.close()
        aboutWindow = nil

        // Switch to X mode
        updateMode(to: .xTwitter)

        // Add small delay to let WebView fully initialize before loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if let url = URL(string: "https://x.com/brandon_ai") {
                self.xWebView.load(URLRequest(url: url))
            }
        }
    }
    
    @objc func transferContext(_ sender: Any?) {
        sendToBuild(sender)
    }

    /// ⌘⇧B — selection → Build; else page title/URL. GitHub URLs offer clone/open.
    @objc func sendToBuild(_ sender: Any?) {
        guard currentMode == .chat
                || currentMode == .grokipedia
                || currentMode == .xTwitter
                || currentMode == .chatX else { return }

        let pageURL = activeWebView.url?.absoluteString
        let pageTitle = activeWebView.title

        activeWebView.evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let self else { return }
            let selection = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let haystack = [selection, pageURL].compactMap { $0 }.joined(separator: "\n")

            if let githubURL = WebToBuildBridge.githubRepoURL(in: haystack) {
                self.offerGitHubClone(url: githubURL)
                return
            }

            let prompt = WebToBuildBridge.structuredPrompt(
                selection: selection,
                pageTitle: pageTitle,
                pageURL: pageURL
            )
            let hasSelection = !(selection ?? "").isEmpty
            self.updateMode(to: .developer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if hasSelection {
                    NotificationCenter.default.post(name: Notification.Name("TransferWebContext"), object: prompt)
                } else {
                    NotificationCenter.default.post(name: Notification.Name("SpotlightQuery"), object: prompt)
                }
            }
        }
    }
    
    // MARK: - GitHub Integration
    
    /// Detect GitHub URLs in selected text and offer to clone in Build
    @objc func detectAndOfferGitHubClone(_ sender: Any?) {
        sendToBuild(sender)
    }
    
    private func offerGitHubClone(url: String) {
        let alert = NSAlert()
        alert.messageText = "GitHub Repository Detected"
        alert.informativeText = "Found: \(url)\n\nClone into \(WebToBuildBridge.defaultCloneDirectory().path) and open in Build?"
        alert.addButton(withTitle: "Clone & Open")
        alert.addButton(withTitle: "Just Send URL")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            cloneGitHubAndOpenInBuild(url: url)
        case .alertSecondButtonReturn:
            updateMode(to: .developer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("TransferWebContext"), object: url)
            }
        default:
            break
        }
    }

    private func cloneGitHubAndOpenInBuild(url: String) {
        updateMode(to: .developer)
        let prompt = "Summarize this repository structure and suggest a good first task.\n\nRepo: \(url)"

        if let existing = WebToBuildBridge.localPathIfCloned(githubURL: url) {
            NotificationCenter.default.post(
                name: WebToBuildBridge.openProjectAtPath,
                object: existing,
                userInfo: ["prompt": prompt, "submit": true]
            )
            return
        }

        WebToBuildBridge.cloneOrOpenRepository(githubURL: url) { [weak self] result in
            switch result {
            case .success(let path):
                NotificationCenter.default.post(
                    name: WebToBuildBridge.openProjectAtPath,
                    object: path,
                    userInfo: ["prompt": prompt, "submit": true]
                )
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Couldn’t clone repository"
                alert.informativeText = error.localizedDescription
                    + "\n\nYou can still send the URL into Build for the CLI to handle."
                alert.addButton(withTitle: "Send URL to Build")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    self?.updateMode(to: .developer)
                    NotificationCenter.default.post(
                        name: Notification.Name("SpotlightQuery"),
                        object: "Clone and analyze this GitHub repository: \(url)"
                    )
                }
            }
        }
    }

    private func openNativeBuildFromWeb() {
        updateMode(to: .developer)
        NotificationCenter.default.post(name: .buildDidBecomeActive, object: nil)
    }
    
    /// Open current page content in Build for analysis
    @objc func openPageInCode(_ sender: Any?) {
        guard currentMode == .chat
                || currentMode == .grokipedia
                || currentMode == .xTwitter
                || currentMode == .chatX else { return }
        
        let url = activeWebView.url?.absoluteString
        let title = activeWebView.title ?? "Web Page"
        let prompt = WebToBuildBridge.structuredPrompt(selection: nil, pageTitle: title, pageURL: url)

        updateMode(to: .developer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: Notification.Name("SpotlightQuery"), object: prompt)
        }
    }
}

// MARK: - Web → Build message bridge
extension AppDelegate: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == WebToBuildBridge.messageHandlerName {
            if let body = message.body as? [String: Any],
               let action = body["action"] as? String,
               action == "openNativeBuild" {
                openNativeBuildFromWeb()
                return
            }
            openNativeBuildFromWeb()
        } else if message.name == GrokUsageBadge.messageHandlerName {
            GrokUsageBadge.handleScriptMessage(message, in: webView)
        }
    }
}

// MARK: - Menu bar
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildStatusMenu(recent: nil)
        scrapeRecentChats()
    }
}

// MARK: - HotKeyDelegate
extension AppDelegate: HotKeyDelegate {
    func hotKeyTriggered() {
        QuickAskController.toggle()
    }

    func screenshotHotKeyTriggered() {
        captureScreenRegion()
    }

    /// `screencapture -i` writes a region to a temp file, then attaches it to a new grok.com chat.
    private func captureScreenRegion() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GrokShot-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", url.path]
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                guard process.terminationStatus == 0,
                      let attachment = GrokAskService.attachment(at: url.path) else { return }
                (NSApp.delegate as? AppDelegate)?.beginGrokChat(
                    prompt: nil,
                    attachments: [attachment],
                    fallbackNote: url.path
                )
            }
        }
        try? process.run()
    }
}

// MARK: - WKUIDelegate for media permissions
extension AppDelegate: WKUIDelegate {
    func webView(_ webView: WKWebView, 
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Auto-grant permission for grok.com
        if origin.host == "grok.com" || origin.host.hasSuffix(".grok.com") {
            decisionHandler(.grant)
        } else {
            decisionHandler(.prompt)
        }
    }
    
    // Handle JavaScript alerts
    func webView(_ webView: WKWebView, 
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }
    
    // Handle JavaScript confirm dialogs
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }
    
    // Handle file upload dialogs
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        
        openPanel.begin { result in
            if result == .OK {
                completionHandler(openPanel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    // Handle opening links in new windows (Popups/OAuth vs External Links)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }
        let host = url.host?.lowercased() ?? ""
        let authHosts = ["grok.com", "x.ai", "x.com", "twitter.com", "google.com", "apple.com"]
        let isAuth = host.isEmpty || url.scheme == "about" || authHosts.contains { host.contains($0) }
        guard isAuth else {
            NSWorkspace.shared.open(url)
            return nil
        }
        // Real popup sharing the opener's session so OAuth can post back via window.opener
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: configuration)
        popup.uiDelegate = self
        popup.navigationDelegate = self
        popup.customUserAgent = webView.customUserAgent
        let win = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "Sign in"
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        authPopupWindows.append(win)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let i = authPopupWindows.firstIndex(where: { $0.contentView === webView }) {
            authPopupWindows[i].close()
            authPopupWindows.remove(at: i)
        }
    }
}

// MARK: - WKNavigationDelegate for downloads
extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // 0. Explicit user clicks on web Grok Build / CLI install → native Build.
        // Only intercept linkActivated navigations — never cancel SPA/bootstrap loads
        // (that left the Grok tab stuck on a blank white page).
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            let absolute = url.absoluteString.lowercased()
            let isCLIInstall = host.contains("x.ai")
                && (path.contains("/cli") || absolute.contains("install.sh") || absolute.contains("cli/install"))
            let isBuildDeepLink = absolute.contains("grok.com/build")
                || absolute.contains("grok.com/cli")
                || (host.contains("grok.com") && path.contains("/build"))
            if isCLIInstall || isBuildDeepLink {
                openNativeBuildFromWeb()
                decisionHandler(.cancel, preferences)
                return
            }
        }

        // 1. External Link Logic
        // Open non-app links in the default browser (Safari/Chrome)
        if let url = navigationAction.request.url, let host = url.host?.lowercased() {
             // Whitelist allowed domains for main window (App + Auth providers)
             let allowedHosts = ["grok.com", "x.ai", "twitter.com", "x.com", "google.com", "accounts.google.com", "apple.com"]
             let isAllowed = allowedHosts.contains { host.contains($0) }
             
             // If not allowed and it's a link click, open in external browser
             if !isAllowed && navigationAction.navigationType == .linkActivated {
                 NSWorkspace.shared.open(url)
                 decisionHandler(.cancel, preferences)
                 return
             }
        }
        
        // 2. Download Logic
        // Check if this is a download link
        if let url = navigationAction.request.url {
            let ext = url.pathExtension.lowercased()
            let downloadableExtensions = ["pdf", "zip", "dmg", "pkg", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "json", "xml", "mp3", "mp4", "mov", "avi", "png", "jpg", "jpeg", "gif", "svg"]
            
            if downloadableExtensions.contains(ext) || navigationAction.shouldPerformDownload {
                // Trigger download
                if #available(macOS 11.3, *) {
                    decisionHandler(.download, preferences)
                } else {
                    // Fallback for older macOS - open in browser
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel, preferences)
                }
                return
            }
        }
        
        decisionHandler(.allow, preferences)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            if #available(macOS 11.3, *) {
                decisionHandler(.download)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
    
    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    // Handle navigation errors
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("Navigation failed: \(error.localizedDescription)")
        #endif
        showLoadError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("Provisional navigation failed: \(error.localizedDescription)")
        #endif
        showLoadError(error)
    }
    
    private func showLoadError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to load Grok"
        alert.informativeText = "\(error.localizedDescription)\n\nClick Retry to try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://grok.com") {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("Page loaded successfully: \(webView.url?.absoluteString ?? "unknown")")
        #endif
        injectGrokBuildNativeHookIfNeeded(in: webView)
        if isChatTab(webView) || webView === self.webView {
            GrokUsageBadge.injectIfNeeded(into: webView)
            noteChatTabTitle(for: webView)
            if webView === self.webView {
                deliverPendingQuickAskIfNeeded(in: webView)
                if zenMode { applyZenStyle(to: webView) }
            }
        }
    }

    @objc func toggleMiniChat(_ sender: Any?) {
        if let pipWindow, pipWindow.isVisible {
            pipWindow.orderOut(nil)
            return
        }
        if pipWindow == nil {
            let mini = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            mini.title = "Grok Mini"
            mini.level = .floating
            mini.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            mini.isReleasedWhenClosed = false
            mini.minSize = NSSize(width: 280, height: 320)
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = prefs
            let miniWeb = SilentWebView(frame: .zero, configuration: config)
            miniWeb.autoresizingMask = [.width, .height]
            miniWeb.frame = NSRect(x: 0, y: 0, width: 380, height: 520)
            mini.contentView = miniWeb
            pipWebView = miniWeb
            pipWindow = mini
        }
        let current = webView.url
        let allowed = current?.host?.lowercased()
        let url: URL
        if let current, let host = allowed, host == "grok.com" || host.hasSuffix(".grok.com") || host == "x.com" || host.hasSuffix(".x.com") {
            url = current
        } else if let fallback = URL(string: "https://grok.com") {
            url = fallback
        } else {
            return
        }
        pipWebView?.load(URLRequest(url: url))
        pipWindow?.center()
        pipWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleZen(_ sender: Any?) {
        zenMode.toggle()
        if zenMode && currentMode != .chat {
            updateMode(to: .chat)
        }
        applyZenChrome()
        applyZenStyle(to: webView)
    }

    private func applyZenChrome() {
        if zenMode && currentMode == .chat {
            layoutChromeStrip()
        } else {
            chatTabStrip?.isHidden = false
            updateWindowChrome(for: currentMode)
        }
    }

    private func applyZenStyle(to webView: WKWebView) {
        let enabled = zenMode ? "true" : "false"
        let js = """
        (function() {
            var on = \(enabled);
            var id = 'grok-zen-style';
            var existing = document.getElementById(id);
            if (!on) { if (existing) existing.remove(); return; }
            if (!existing) {
                existing = document.createElement('style');
                existing.id = id;
                document.documentElement.appendChild(existing);
            }
            existing.textContent = 'nav,aside,[class*="sidebar" i],[data-testid*="sidebar" i]{display:none !important;} main{max-width:720px !important;margin-left:auto !important;margin-right:auto !important;}';
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Loads grok.com as a new chat, then types the prompt once the page finishes.
    func submitQuickAsk(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        beginGrokChat(prompt: trimmed, attachments: [])
    }

    /// Opens a new grok.com chat and either types `prompt` or attaches files. A failed attach falls back to `fallbackNote`.
    func beginGrokChat(prompt: String?, attachments: [GrokAttachment], fallbackNote: String? = nil) {
        QuickAskController.close()
        pendingQuickAsk = prompt
        pendingAttachments = attachments
        pendingAttachmentFallback = fallbackNote
        showMainWindow(nil)
        newChatTab(nil)
    }

    @objc func showQuickAsk(_ sender: Any?) {
        QuickAskController.toggle()
    }

    @objc func exportChat(_ sender: Any?) {
        ChatExporter.export(from: activeWebView, window: window)
    }

    @objc func showFind(_ sender: Any?) {
        guard currentMode != .developer, let content = mainContainerView else { return }
        if findBar == nil {
            let bar = GrokFindBar(frame: .zero)
            bar.onFind = { [weak self] query, backwards in
                self?.findInPage(query, backwards: backwards)
            }
            bar.onClose = { [weak self] in
                self?.findBar?.removeFromSuperview()
                self?.findBar?.isHidden = true
            }
            findBar = bar
        }
        guard let findBar else { return }
        findBar.isHidden = false
        layoutFindBar()
        if findBar.superview !== content {
            content.addSubview(findBar, positioned: .above, relativeTo: nil)
        }
        window.makeFirstResponder(findBar.field)
    }

    func layoutFindBar() {
        guard let findBar, !findBar.isHidden, let content = mainContainerView else { return }
        findBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: 40)
        if findBar.superview !== content {
            content.addSubview(findBar, positioned: .above, relativeTo: nil)
        }
    }

    private func findInPage(_ query: String, backwards: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let literal = (try? String(data: JSONEncoder().encode(trimmed), encoding: .utf8)) ?? "\"\""
        let js = "window.find(\(literal), false, \(backwards ? "true" : "false"), true, false, false, false)"
        activeWebView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func showPromptLibrary(_ sender: Any?) {
        if promptLibraryPanel == nil {
            promptLibraryPanel = PromptLibraryPanel()
        }
        promptLibraryPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deliverPendingQuickAskIfNeeded(in webView: WKWebView) {
        guard pendingQuickAsk != nil || !pendingAttachments.isEmpty else { return }
        guard let host = webView.url?.host?.lowercased(),
              host == "grok.com" || host.hasSuffix(".grok.com") else { return }
        let prompt = pendingQuickAsk
        let attachments = pendingAttachments
        let fallback = pendingAttachmentFallback
        pendingQuickAsk = nil
        pendingAttachments = []
        pendingAttachmentFallback = nil
        if attachments.isEmpty {
            if let prompt, !prompt.isEmpty {
                GrokChatInjector.inject(prompt, into: webView)
            }
            return
        }
        GrokChatInjector.attach(attachments, into: webView) { ok in
            if let prompt, !prompt.isEmpty {
                GrokChatInjector.inject(prompt, into: webView)
            } else if !ok, let fallback, !fallback.isEmpty {
                GrokChatInjector.inject(fallback, into: webView)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        GrokAskService.shared.consumeIfPresent()
    }

    private func injectGrokBuildNativeHookIfNeeded(in webView: WKWebView) {
        guard let host = webView.url?.host?.lowercased(), host.contains("grok.com") else { return }
        webView.evaluateJavaScript(WebToBuildBridge.grokBuildCTAScript, completionHandler: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        print("[AppDelegate] Web content process terminated for webView: \(webView)")
        #endif
        reloadTerminatedWebView(webView)
    }

    private func reloadTerminatedWebView(_ webView: WKWebView) {
        if let url = webView.url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" {
            webView.load(URLRequest(url: url))
        } else if let home = homeURL(for: webView) {
            webView.load(URLRequest(url: home))
        }
    }

    private func homeURL(for webView: WKWebView) -> URL? {
        if webView === self.webView {
            return URL(string: "https://grok.com")
        } else if webView === self.consoleWebView {
            return URL(string: "https://console.x.ai/home")
        } else if webView === self.grokipediaWebView {
            return URL(string: "https://grokipedia.com")
        } else if webView === self.xWebView {
            return URL(string: "https://x.com")
        } else if webView === self.chatXWebView {
            return URL(string: "https://chat.x.com")
        }
        return URL(string: "https://grok.com")
    }

    func checkAndRecoverEmptyBodyIfNeeded() {
        guard currentMode == .chat else { return }
        let now = Date()
        guard now.timeIntervalSince(lastEmptyBodyReloadDate) >= 30 else { return }

        webView.evaluateJavaScript("(!document.body || document.body.innerHTML.trim().length === 0 || document.body.children.length === 0)") { [weak self] result, error in
            guard let self = self else { return }
            if let isEmpty = result as? Bool, isEmpty {
                self.lastEmptyBodyReloadDate = Date()
                #if DEBUG
                print("[AppDelegate] Empty document body detected on key window, reloading grok.com")
                #endif
                if let url = self.webView.url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" {
                    self.webView.load(URLRequest(url: url))
                } else if let home = URL(string: "https://grok.com") {
                    self.webView.load(URLRequest(url: home))
                }
            }
        }
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        checkAndRecoverEmptyBodyIfNeeded()
    }
}

// MARK: - WKDownloadDelegate
@available(macOS 11.3, *)
extension AppDelegate: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Save to Downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var destinationURL = downloadsURL.appendingPathComponent(suggestedFilename)
        
        // If file exists, add number suffix
        var counter = 1
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        let ext = destinationURL.pathExtension
        
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let newName = "\(baseName) (\(counter)).\(ext)"
            destinationURL = downloadsURL.appendingPathComponent(newName)
            counter += 1
        }
        
        completionHandler(destinationURL)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        // Show notification or play sound
        NSSound(named: .init("Glass"))?.play()
        #if DEBUG
        print("Download finished!")
        #endif
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        #if DEBUG
        print("Download failed: \(error.localizedDescription)")
        #endif
        
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

struct ToolbarModeSwitcher: View {
    @ObservedObject var modeState = AppModeState.shared
    var onModeChange: (AppMode) -> Void
    @AppStorage("hasSeenGrokBuild") private var hasSeenGrokBuild = false
    @AppStorage("hasSeenGrokipedia") private var hasSeenGrokipedia = false
    @AppStorage("hasSeenX") private var hasSeenX = false
    @AppStorage("hasSeenChatX") private var hasSeenChatX = false
    @Environment(\.colorScheme) var colorScheme

    // Real Grok logo — asset catalog at native resolution (avoid tiny NSImage rasterization)
    private var grokLogo: some View {
        GrokMarkView(size: 14, template: true)
    }

    // Button sizes for icon + label design
    // Order: 𝕏 | Chat | Grok | Build | Grokipedia
    private let xButtonWidth: CGFloat = 32  // Just the 𝕏 logo
    private let chatXButtonWidth: CGFloat = 64
    private let grokButtonWidth: CGFloat = 64
    private let buildButtonWidth: CGFloat = 66
    private let wikiButtonWidth: CGFloat = 92
    private let buttonHeight: CGFloat = 24
    private let cornerRadius: CGFloat = 6

    private var totalWidth: CGFloat {
        xButtonWidth + chatXButtonWidth + grokButtonWidth + buildButtonWidth + wikiButtonWidth + 4
    }

    private var thumbWidth: CGFloat {
        switch modeState.currentMode {
        case .xTwitter: return xButtonWidth
        case .chatX: return chatXButtonWidth
        case .chat: return grokButtonWidth
        case .developer, .console: return buildButtonWidth
        case .grokipedia: return wikiButtonWidth
        }
    }

    private var thumbOffset: CGFloat {
        // Calculate offset from center for each button position
        // Buttons: [X][Chat][Grok][Build][Grokipedia]
        switch modeState.currentMode {
        case .xTwitter:
            return -(totalWidth - xButtonWidth) / 2 + 2
        case .chatX:
            return -(totalWidth - xButtonWidth * 2 - chatXButtonWidth) / 2 + 2
        case .chat:
            return -(totalWidth - xButtonWidth * 2 - chatXButtonWidth * 2 - grokButtonWidth) / 2 + 2
        case .developer, .console:
            return (totalWidth - wikiButtonWidth * 2 - buildButtonWidth) / 2 - 2
        case .grokipedia:
            return (totalWidth - wikiButtonWidth) / 2 - 2
        }
    }

    var body: some View {
        ZStack {
            // Layer 1: Track (Bottom) - with proper clip
            RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.88))

            // Layer 2: Active Thumb (Middle) - Fully Opaque, No Blending
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.28) : Color.white)
                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                .frame(width: thumbWidth, height: buttonHeight)
                .offset(x: thumbOffset)
                .animation(.snappy(duration: 0.2), value: modeState.currentMode)

            // Layer 3: Labels (Top) - Icons + Labels
            // Order: 𝕏 | Chat | Grok | Build | Grokipedia
            HStack(spacing: 0) {
                // 𝕏 Button - Logo only (x.com feed)
                Button(action: {
                    onModeChange(.xTwitter)
                    hasSeenX = true
                }) {
                    Text("𝕏")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(modeState.currentMode == .xTwitter ? (colorScheme == .dark ? .white : .black) : .secondary)
                        .frame(width: xButtonWidth, height: buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("X · Home feed")

                // Chat Button - chat.x.com
                Button(action: {
                    onModeChange(.chatX)
                    hasSeenChatX = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Chat")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(modeState.currentMode == .chatX ? (colorScheme == .dark ? .white : .black) : .secondary)
                    .frame(width: chatXButtonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Chat · chat.x.com")

                // Grok Button
                Button(action: { onModeChange(.chat) }) {
                    HStack(spacing: 5) {
                        grokLogo
                        Text("Grok")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(modeState.currentMode == .chat ? (colorScheme == .dark ? .white : .black) : .secondary)
                    .frame(width: grokButtonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Grok · grok.com")

                // Build Button
                Button(action: {
                    onModeChange(.developer)
                    hasSeenGrokBuild = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("Build")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle((modeState.currentMode == .developer || modeState.currentMode == .console) ? (colorScheme == .dark ? .white : .black) : .secondary)
                    .frame(width: buildButtonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Grok Build · local coding agent")

                // Grokipedia Button
                Button(action: {
                    onModeChange(.grokipedia)
                    hasSeenGrokipedia = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Grokipedia")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(modeState.currentMode == .grokipedia ? (colorScheme == .dark ? .white : .black) : .secondary)
                    .frame(width: wikiButtonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Grokipedia · knowledge wiki")
            }
        }
        .frame(width: totalWidth, height: buttonHeight + 4)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous))
    }
}
