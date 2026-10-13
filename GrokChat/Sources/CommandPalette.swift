//
//  CommandPalette.swift
//  Grok for Mac
//
//  Command-Shift-K lists actions, modes, and settings.
//

import AppKit

struct PaletteCommand {
    var title: String
    var group: String
    var run: () -> Void
}

final class CommandPalettePanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField(frame: .zero)
    private let table = NSTableView(frame: .zero)
    private var commands: [PaletteCommand] = []
    private var filtered: [PaletteCommand] = []

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Commands"
        isReleasedWhenClosed = false
        level = .floating
        center()
        commands = Self.makeCommands()
        filtered = commands
        build()
    }

    private func build() {
        let content = NSView(frame: frame)
        contentView = content
        search.placeholderString = "Search actions, modes, and settings"
        search.setAccessibilityLabel("Search commands")
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = true
        search.target = self
        search.action = #selector(runSelected)
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.title = "Command"
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(runSelected)
        table.target = self
        table.rowHeight = 22
        table.setAccessibilityLabel("Commands")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(search)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        return result
    }

    func showFresh() {
        commands = Self.makeCommands()
        search.stringValue = ""
        filtered = commands
        table.reloadData()
        makeKeyAndOrderFront(nil)
        _ = makeFirstResponder(search)
        NSApp.activate(ignoringOtherApps: true)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = filtered[row]
        let field = NSTextField(labelWithString: "\(command.group)  ·  \(command.title)")
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("\(command.group) \(command.title)")
        return field
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filtered = query.isEmpty ? commands : commands.filter {
            $0.title.lowercased().contains(query) || $0.group.lowercased().contains(query)
        }
        table.reloadData()
        if !filtered.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func filter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filtered = query.isEmpty ? commands : commands.filter {
            $0.title.lowercased().contains(query) || $0.group.lowercased().contains(query)
        }
        table.reloadData()
    }

    @objc private func runSelected() {
        let row = table.selectedRow >= 0 ? table.selectedRow : 0
        guard filtered.indices.contains(row) else { return }
        let command = filtered[row]
        orderOut(nil)
        command.run()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            runSelected()
        } else if event.keyCode == 53 {
            orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private static func makeCommands() -> [PaletteCommand] {
        guard let app = NSApp.delegate as? AppDelegate else { return [] }
        func action(_ title: String, _ run: @escaping (AppDelegate) -> Void) -> PaletteCommand {
            PaletteCommand(title: title, group: "Action") { [weak app] in
                guard let app else { return }
                run(app)
            }
        }
        func mode(_ title: String, _ mode: AppMode) -> PaletteCommand {
            PaletteCommand(title: title, group: "Mode") { [weak app] in
                app?.showMainWindow(nil)
                app?.updateMode(to: mode)
            }
        }
        func setting(_ title: String) -> PaletteCommand {
            PaletteCommand(title: title, group: "Setting") { [weak app] in
                app?.showSettings(nil)
            }
        }
        // One palette entry per configured Grok Bot so the palette can open a
        // specific bot (not just launch the app). Opens the bot's grokbot:// deep
        // link; falls back to the launcher when a bot has no usable URL.
        let botCommands: [PaletteCommand] = GrokBotSwitcher.configuredBots().map { bot in
            PaletteCommand(title: "Grok Bot: \(bot.name)", group: "Action") {
                GrokBotSwitcher.open(bot)
            }
        }
        return [
            action("New Chat") { $0.newChat(nil) },
            action("New Tab") { $0.newChatTab(nil) },
            action("Quick Ask") { $0.showQuickAsk(nil) },
            action("Prompt Library") { $0.showPromptLibrary(nil) },
            action("Find in Page") { $0.showFind(nil) },
            action("Focus Mode") { $0.toggleZen(nil) },
            action("Mini Chat") { $0.toggleMiniChat(nil) },
            action("Export Chat") { $0.exportChat(nil) },
            action("Screenshot to Grok") { $0.captureScreenRegion() },
            action("Build Terminal") { $0.showBuildTerminal(nil) },
            action("Grok Bot") { _ in GrokBotSwitcher.launchOrBringForward() },
            action("Open Bot Switcher") { $0.showBotSwitcher(nil) },
            action("Grok Bot Routines") { _ in GrokBotSwitcher.openRoutines() },
            action("Open usage in Grok Bot app") { _ in GrokBotSwitcher.openUsage() },
            action("Handoff Inbox") { $0.showHandoffInbox(nil) },
            action("Send Terminal Selection to Grok") { $0.sendTerminalSelection(nil) },
            action("Keyboard Shortcuts") { $0.showShortcutCheatSheet(nil) },
            action("Settings") { $0.showSettings(nil) },
            mode("Grok", .chat),
            mode("Build", .developer),
            mode("Console", .console),
            mode("Grokipedia", .grokipedia),
            mode("X", .xTwitter),
            mode("Chat on X", .chatX),
            setting("Launch at Login"),
            setting("Menu Bar"),
            setting("Dock usage badge"),
            setting("Quick Ask shortcut"),
            setting("Prefill from selection"),
            setting("Screenshot shortcut"),
            setting("Weekly pace warning"),
            setting("Quiet hours"),
            setting("Terminal font size"),
            setting("Terminal theme"),
            setting("Grok API key"),
            setting("Safety mode")
        ] + botCommands
    }
}
