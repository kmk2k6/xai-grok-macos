//
//  SettingsWindow.swift
//  Grok for Mac
//
//  Created by Brandon Charleson on 2025.
//  Copyright © 2025 Brandon Charleson. All rights reserved.
//
//  https://github.com/bcharleson/xai-grok
//

import Cocoa
import ServiceManagement
import Sparkle
import SwiftUI
import WebKit

class SettingsWindow: NSWindow {
    
    private var apiKeyField: NSSecureTextField!
    private var safetyCheckbox: NSButton!
    private var retentionPopup: NSPopUpButton!
    private var settingsTabView: NSTabView?
    private var generalRows: NSStackView?
    private var grokRows: NSStackView?
    private var appearanceHost: NSView?
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Settings"
        self.center()
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 480, height: 400)
        setupUI()
    }
    
    private func setupUI() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 480))
        root.autoresizingMask = [.width, .height]
        let search = NSSearchField(frame: NSRect(x: 16, y: 444, width: 488, height: 28))
        search.placeholderString = "Search settings"
        search.setAccessibilityLabel("Search settings")
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = true
        search.delegate = self
        search.autoresizingMask = [.width, .minYMargin]
        root.addSubview(search)

        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 520, height: 436))
        tabView.autoresizingMask = [.width, .height]
        
        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = createGeneralView()

        let appearanceItem = NSTabViewItem(identifier: "appearance")
        appearanceItem.label = "Appearance"
        appearanceItem.view = createAppearanceView()
        
        let grokItem = NSTabViewItem(identifier: "grok")
        grokItem.label = "Grok Build"
        grokItem.view = createGrokView()
        
        tabView.addTabViewItem(generalItem)
        tabView.addTabViewItem(appearanceItem)
        tabView.addTabViewItem(grokItem)
        settingsTabView = tabView
        root.addSubview(tabView)
        
        self.contentView = root
    }

    private func createAppearanceView() -> NSView {
        let hosting = NSHostingView(rootView: GlassAppearanceSettingsView(settingsManager: .shared))
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 480)
        hosting.autoresizingMask = [.width, .height]
        appearanceHost = hosting
        return hosting
    }
    
    private func createGeneralView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 350))
        
        let stack = NSStackView(frame: container.bounds.insetBy(dx: 40, dy: 40))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.autoresizingMask = [.width, .height]
        container.addSubview(stack)
        
        // Launch at Login
        let launchToggle = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        stack.addArrangedSubview(launchToggle)
        
        // Menu Bar Icon (default to ON if key doesn't exist)
        let dockBadgeToggle = NSButton(
            checkboxWithTitle: "Show usage percent on the Dock icon",
            target: self,
            action: #selector(toggleDockBadge(_:))
        )
        dockBadgeToggle.state = UserDefaults.standard.bool(forKey: "grok.dockBadge.enabled") ? .on : .off
        dockBadgeToggle.toolTip = "Off by default. The Dock icon shows the latest usage percent."
        stack.addArrangedSubview(dockBadgeToggle)

        let menuBarToggle = NSButton(checkboxWithTitle: "Show in Menu Bar", target: self, action: #selector(toggleMenuBarIcon(_:)))
        let showMenuBar = UserDefaults.standard.object(forKey: "showMenuBarIcon") == nil ? true : UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        menuBarToggle.state = showMenuBar ? .on : .off
        stack.addArrangedSubview(menuBarToggle)
        
        // Auto-update
        let autoUpdateToggle = NSButton(checkboxWithTitle: "Automatically check for updates", target: self, action: #selector(toggleAutoUpdate(_:)))
        autoUpdateToggle.state = UpdateManager.shared.updater.automaticallyChecksForUpdates ? .on : .off
        stack.addArrangedSubview(autoUpdateToggle)
        
        stack.addArrangedSubview(createSeparator())
        
        // Global Shortcut
        let shortcutsLabel = NSTextField(labelWithString: "Quick Ask Shortcut")
        shortcutsLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(shortcutsLabel)
        
        let hotkeyDropdown = NSPopUpButton(frame: .zero, pullsDown: false)
        hotkeyDropdown.addItems(withTitles: [
            "Option + Space",
            "Control + Space",
            "Command + Shift + G",
            "Option + G"
        ])
        hotkeyDropdown.selectItem(at: UserDefaults.standard.integer(forKey: "hotkeyPreset"))
        hotkeyDropdown.target = self
        hotkeyDropdown.action = #selector(hotkeyChanged(_:))
        stack.addArrangedSubview(hotkeyDropdown)

        let selectionToggle = NSButton(
            checkboxWithTitle: "Prefill Quick Ask from the selected text",
            target: self,
            action: #selector(toggleQuickAskSelection(_:))
        )
        selectionToggle.state = UserDefaults.standard.bool(forKey: QuickAskController.prefillFromSelectionKey) ? .on : .off
        selectionToggle.toolTip = "When on, Quick Ask sends Command-C to the frontmost app and prefills that selection. Off by default. Accessibility permission is required."
        stack.addArrangedSubview(selectionToggle)

        let shotLabel = NSTextField(labelWithString: "Screenshot to Grok")
        shotLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(shotLabel)

        let shotDropdown = NSPopUpButton(frame: .zero, pullsDown: false)
        shotDropdown.addItems(withTitles: [
            "Control + Option + 4",
            "Option + Shift + 4",
            "Control + Shift + 4"
        ])
        shotDropdown.selectItem(at: UserDefaults.standard.integer(forKey: "screenshotHotkeyPreset"))
        shotDropdown.target = self
        shotDropdown.action = #selector(screenshotHotkeyChanged(_:))
        stack.addArrangedSubview(shotDropdown)

        let paceToggle = NSButton(
            checkboxWithTitle: "Warn when usage is more than 15 points ahead of weekly pace",
            target: self,
            action: #selector(togglePaceWarning(_:))
        )
        paceToggle.state = UserDefaults.standard.bool(forKey: GrokUsageBadge.paceWarningEnabledKey) ? .on : .off
        paceToggle.toolTip = "Sends one notification per week when usage runs ahead of an even weekly pace. Off by default."
        stack.addArrangedSubview(paceToggle)

        let quietToggle = NSButton(
            checkboxWithTitle: "Quiet hours for usage alerts",
            target: self,
            action: #selector(toggleQuietHours(_:))
        )
        quietToggle.state = UserDefaults.standard.bool(forKey: GrokUsageBadge.quietHoursEnabledKey) ? .on : .off
        quietToggle.toolTip = "Holds usage alerts during these hours, and while macOS Focus is on."
        stack.addArrangedSubview(quietToggle)

        let quietRow = NSStackView()
        quietRow.orientation = .horizontal
        quietRow.spacing = 8
        quietRow.addArrangedSubview(NSTextField(labelWithString: "From"))
        let startPopup = hourPopup(selected: UserDefaults.standard.object(forKey: GrokUsageBadge.quietHoursStartKey) as? Int ?? 22, action: #selector(quietStartChanged(_:)))
        startPopup.setAccessibilityLabel("Quiet hours start")
        quietRow.addArrangedSubview(startPopup)
        quietRow.addArrangedSubview(NSTextField(labelWithString: "to"))
        let endPopup = hourPopup(selected: UserDefaults.standard.object(forKey: GrokUsageBadge.quietHoursEndKey) as? Int ?? 7, action: #selector(quietEndChanged(_:)))
        endPopup.setAccessibilityLabel("Quiet hours end")
        quietRow.addArrangedSubview(endPopup)
        stack.addArrangedSubview(quietRow)
        
        stack.addArrangedSubview(createSeparator())
        
        // Updates
        let updatesLabel = NSTextField(labelWithString: "Updates")
        updatesLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(updatesLabel)
        
        let versionString = "Version \(UpdateManager.shared.currentVersion) (Build \(UpdateManager.shared.currentBuild))"
        let versionLabel = NSTextField(labelWithString: versionString)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)
        
        let updateButton = NSButton(title: "Check for Updates...", target: self, action: #selector(checkForUpdates(_:)))
        updateButton.bezelStyle = .rounded
        stack.addArrangedSubview(updateButton)
        generalRows = stack
        labelNativeRows(stack)
        
        return container
    }
    
    private func createGrokView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 350))
        
        let stack = NSStackView(frame: container.bounds.insetBy(dx: 40, dy: 40))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.autoresizingMask = [.width, .height]
        container.addSubview(stack)
        
        // API Key Section
        let apiLabel = NSTextField(labelWithString: "Grok API Key")
        apiLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(apiLabel)
        
        apiKeyField = NSSecureTextField()
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyChanged(_:))
        // Load API key from Keychain (secure storage)
        if let key = KeychainHelper.shared.getAPIKey() {
            apiKeyField.stringValue = key
        }
        stack.addArrangedSubview(apiKeyField)
        
        stack.addArrangedSubview(createSeparator())
        
        // Security Section
        let securityLabel = NSTextField(labelWithString: "Security & Safety")
        securityLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(securityLabel)
        
        safetyCheckbox = NSButton(checkboxWithTitle: "Enable Safety Mode (Block destructive commands)", target: self, action: #selector(safetyToggled(_:)))
        // Check if key exists, if not use default of true (ON)
        if UserDefaults.standard.object(forKey: "safetyEnabled") == nil {
            safetyCheckbox.state = .on // Default: ON
        } else {
            safetyCheckbox.state = UserDefaults.standard.bool(forKey: "safetyEnabled") ? .on : .off
        }
        stack.addArrangedSubview(safetyCheckbox)
        
        stack.addArrangedSubview(createSeparator())
        
        // History Section
        let historyLabel = NSTextField(labelWithString: "Chat History")
        historyLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(historyLabel)
        
        let retentionStack = NSStackView()
        retentionStack.orientation = .horizontal
        retentionStack.spacing = 8
        
        retentionStack.addArrangedSubview(NSTextField(labelWithString: "Retention Policy:"))
        
        retentionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        retentionPopup.addItem(withTitle: "Forever") // Tag 0
        retentionPopup.addItem(withTitle: "7 Days")  // Tag 7
        retentionPopup.addItem(withTitle: "30 Days") // Tag 30
        
        // Map tags to items
        retentionPopup.item(at: 0)?.tag = 0
        retentionPopup.item(at: 1)?.tag = 7
        retentionPopup.item(at: 2)?.tag = 30
        
        // Select current
        let currentRetention = UserDefaults.standard.integer(forKey: "chatRetentionDays")
        if currentRetention == 7 { retentionPopup.selectItem(withTag: 7) }
        else if currentRetention == 30 { retentionPopup.selectItem(withTag: 30) }
        else { retentionPopup.selectItem(withTag: 0) }
        
        retentionPopup.target = self
        retentionPopup.action = #selector(retentionChanged(_:))
        retentionStack.addArrangedSubview(retentionPopup)
        
        stack.addArrangedSubview(retentionStack)
        
        let clearButton = NSButton(title: "Clear All History", target: self, action: #selector(clearHistory(_:)))
        clearButton.bezelStyle = .rounded
        stack.addArrangedSubview(clearButton)
        let terminalLabel = NSTextField(labelWithString: "Terminal")
        terminalLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(terminalLabel)
        let fontRow = NSStackView()
        fontRow.orientation = .horizontal
        fontRow.spacing = 8
        fontRow.addArrangedSubview(NSTextField(labelWithString: "Font size"))
        let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for size in [11, 13, 15, 18] {
            fontPopup.addItem(withTitle: "\(size)")
            fontPopup.lastItem?.tag = size
        }
        let storedSize = Int(UserDefaults.standard.object(forKey: GrokTerminalTheme.fontSizeKey) as? Double ?? 13)
        fontPopup.selectItem(withTag: storedSize == 0 ? 13 : storedSize)
        fontPopup.target = self
        fontPopup.action = #selector(terminalFontChanged(_:))
        fontPopup.setAccessibilityLabel("Terminal font size")
        fontRow.addArrangedSubview(fontPopup)
        stack.addArrangedSubview(fontRow)
        let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        themePopup.addItems(withTitles: ["Dark", "Light"])
        themePopup.selectItem(at: UserDefaults.standard.string(forKey: GrokTerminalTheme.themeKey) == "light" ? 1 : 0)
        themePopup.target = self
        themePopup.action = #selector(terminalThemeChanged(_:))
        themePopup.setAccessibilityLabel("Terminal theme")
        stack.addArrangedSubview(themePopup)
        grokRows = stack
        labelNativeRows(stack)
        
        return container
    }
    
    private func createSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
    
    // MARK: - Actions
    
    @objc func apiKeyChanged(_ sender: NSSecureTextField) {
        // Save API key to Keychain (secure storage)
        let key = sender.stringValue
        if key.isEmpty {
            KeychainHelper.shared.deleteAPIKey()
        } else {
            KeychainHelper.shared.saveAPIKey(key)
        }
        // Notify the app that API key changed
        NotificationCenter.default.post(name: Notification.Name("APIKeyChanged"), object: key)
    }
    
    @objc func safetyToggled(_ sender: NSButton) {
        let isEnabled = sender.state == .on
        UserDefaults.standard.set(isEnabled, forKey: "safetyEnabled")
        // Force update across app
        NotificationCenter.default.post(name: Notification.Name("SafetyModeChanged"), object: isEnabled)
    }
    
    @objc func retentionChanged(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem else { return }
        UserDefaults.standard.set(selectedItem.tag, forKey: "chatRetentionDays")
    }
    
    @objc func clearHistory(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Clear all chat history?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // Clear WebKit data stores
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let date = Date(timeIntervalSince1970: 0)
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: date) {
                // Notify that history was cleared
                NotificationCenter.default.post(name: Notification.Name("ReloadGrokHistory"), object: nil)
            }
        }
    }
    
    @objc func toggleDockBadge(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "grok.dockBadge.enabled")
        (NSApp.delegate as? AppDelegate)?.refreshDockBadge()
    }

    @objc func toggleMenuBarIcon(_ sender: NSButton) {
        let isOn = sender.state == .on
        UserDefaults.standard.set(isOn, forKey: "showMenuBarIcon")
        if let appDelegate = NSApp.delegate as? AppDelegate {
            if isOn { appDelegate.showStatusBar() } else { appDelegate.hideStatusBar() }
        }
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            #if DEBUG
            print("Failed to toggle launch at login: \(error)")
            #endif
        }
    }
    
    @objc func toggleAutoUpdate(_ sender: NSButton) {
        UpdateManager.shared.configureAutomaticUpdates(enabled: sender.state == .on)
    }
    
    @objc func toggleQuickAskSelection(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: QuickAskController.prefillFromSelectionKey)
        if enabled {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    @objc func togglePaceWarning(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: GrokUsageBadge.paceWarningEnabledKey)
    }

    private func hourPopup(selected: Int, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for hour in 0..<24 {
            popup.addItem(withTitle: String(format: "%02d:00", hour))
            popup.lastItem?.tag = hour
        }
        popup.selectItem(withTag: selected)
        popup.target = self
        popup.action = action
        return popup
    }

    @objc func toggleQuietHours(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: GrokUsageBadge.quietHoursEnabledKey)
        if sender.state == .on {
            GrokUsageBadge.prepareFocusStatus()
        }
    }

    @objc func quietStartChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.selectedTag(), forKey: GrokUsageBadge.quietHoursStartKey)
    }

    @objc func quietEndChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.selectedTag(), forKey: GrokUsageBadge.quietHoursEndKey)
    }

    @objc func screenshotHotkeyChanged(_ sender: NSPopUpButton) {
        if let preset = HotKeyManager.ScreenshotPreset(rawValue: sender.indexOfSelectedItem) {
            HotKeyManager.shared.setScreenshotPreset(preset)
        }
    }

    @objc func hotkeyChanged(_ sender: NSPopUpButton) {
        if let preset = HotKeyManager.ShortcutPreset(rawValue: sender.indexOfSelectedItem) {
            HotKeyManager.shared.setPreset(preset)
        }
    }
    
    @objc func terminalFontChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(Double(sender.selectedTag()), forKey: GrokTerminalTheme.fontSizeKey)
        NotificationCenter.default.post(name: .grokTerminalAppearanceChanged, object: nil)
    }

    @objc func terminalThemeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem == 1 ? "light" : "dark", forKey: GrokTerminalTheme.themeKey)
        NotificationCenter.default.post(name: .grokTerminalAppearanceChanged, object: nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateManager.shared.checkForUpdates(sender)
    }

    fileprivate func applySettingsFilter(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filterRows(generalRows, query: query)
        filterRows(grokRows, query: query)
        let appearanceText = "appearance glass opacity tint font border chrome"
        let appearanceMatches = query.isEmpty || appearanceText.contains(query)
        appearanceHost?.isHidden = !appearanceMatches
        guard !query.isEmpty, let tabView = settingsTabView else { return }
        if stackHasVisibleRow(generalRows) {
            tabView.selectTabViewItem(at: 0)
        } else if appearanceMatches {
            tabView.selectTabViewItem(at: 1)
        } else if stackHasVisibleRow(grokRows) {
            tabView.selectTabViewItem(at: 2)
        }
    }

    private func filterRows(_ stack: NSStackView?, query: String) {
        guard let stack else { return }
        for view in stack.arrangedSubviews {
            if query.isEmpty {
                view.isHidden = false
            } else {
                view.isHidden = !searchableText(in: view).contains(query)
            }
        }
    }

    private func stackHasVisibleRow(_ stack: NSStackView?) -> Bool {
        stack?.arrangedSubviews.contains { !$0.isHidden } ?? false
    }

    private func labelNativeRows(_ stack: NSStackView, context: String = "Settings") {
        var pending = context
        for view in stack.arrangedSubviews {
            if let field = view as? NSTextField, !field.isEditable {
                let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    pending = title
                    field.setAccessibilityLabel(title)
                }
            } else if let button = view as? NSButton {
                button.setAccessibilityLabel(button.title)
            } else if let popup = view as? NSPopUpButton {
                popup.setAccessibilityLabel(pending)
            } else if let secure = view as? NSSecureTextField {
                secure.setAccessibilityLabel(pending)
            } else if let nested = view as? NSStackView {
                labelNativeRows(nested, context: pending)
            }
            for child in view.subviews {
                if let popup = child as? NSPopUpButton { popup.setAccessibilityLabel(pending) }
                if let field = child as? NSTextField, field.isEditable || field is NSSecureTextField {
                    field.setAccessibilityLabel(pending)
                }
                if let button = child as? NSButton, button.title.isEmpty == false {
                    button.setAccessibilityLabel(button.title)
                }
            }
        }
    }

    private func searchableText(in view: NSView) -> String {
        var parts: [String] = []
        if let button = view as? NSButton { parts.append(button.title) }
        if let field = view as? NSTextField { parts.append(field.stringValue) }
        if let popup = view as? NSPopUpButton { parts.append(popup.itemTitles.joined(separator: " ")) }
        if let label = view as? NSTextField { parts.append(label.placeholderString ?? "") }
        for child in view.subviews {
            parts.append(searchableText(in: child))
        }
        return parts.joined(separator: " ").lowercased()
    }
}

extension SettingsWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        applySettingsFilter(field.stringValue)
    }
}
