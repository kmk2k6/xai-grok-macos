//
//  PromptLibrary.swift
//  Grok for Mac
//
//  Reusable prompts. Command-Shift-P opens the palette and inserts into the composer.
//

import AppKit
import UniformTypeIdentifiers
import WebKit

struct PromptEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var body: String
}

enum PromptLibraryStore {
    static let storageKey = "grok.promptLibrary"

    static func load() -> [PromptEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([PromptEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func save(_ entries: [PromptEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

final class PromptLibraryPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private var entries: [PromptEntry] = PromptLibraryStore.load()
    private var filtered: [Int] = []
    private let searchField = NSSearchField(frame: .zero)
    private let table = NSTableView(frame: .zero)
    private let bodyView = NSTextView(frame: .zero)
    private var selectedEntry: Int?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Prompt Library"
        isReleasedWhenClosed = false
        level = .floating
        center()
        build()
        refilter()
    }

    private func build() {
        let content = NSView(frame: frame)
        contentView = content

        searchField.placeholderString = "Search prompts"
        searchField.setAccessibilityLabel("Search prompts")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "Prompt"
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(insertSelected)
        table.setAccessibilityLabel("Saved prompts")
        table.rowHeight = 22
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(frame: .zero)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        bodyView.isRichText = false
        bodyView.font = .systemFont(ofSize: 13)
        bodyView.delegate = self
        bodyView.isVerticallyResizable = true
        bodyView.isHorizontallyResizable = false
        bodyView.autoresizingMask = [.width]
        bodyView.textContainer?.widthTracksTextView = true
        bodyView.setAccessibilityLabel("Prompt text")
        let bodyScroll = NSScrollView(frame: .zero)
        bodyScroll.documentView = bodyView
        bodyScroll.hasVerticalScroller = true
        bodyScroll.translatesAutoresizingMaskIntoConstraints = false

        let insert = button("Insert", action: #selector(insertSelected), label: "Insert prompt into the chat")
        let make = button("New", action: #selector(makeNew), label: "New prompt")
        let delete = button("Delete", action: #selector(deleteSelected), label: "Delete prompt")
        let export = button("Export…", action: #selector(exportJSON), label: "Export prompts as JSON")
        let importBtn = button("Import…", action: #selector(importJSON), label: "Import prompts from JSON")

        let buttons = NSStackView(views: [insert, make, delete, export, importBtn])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(searchField)
        content.addSubview(scroll)
        content.addSubview(bodyScroll)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.widthAnchor.constraint(equalToConstant: 180),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            bodyScroll.topAnchor.constraint(equalTo: scroll.topAnchor),
            bodyScroll.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 8),
            bodyScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bodyScroll.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func button(_ title: String, action: Selector, label: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(label)
        return button
    }

    private func refilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filtered = Array(entries.indices)
        } else {
            filtered = entries.indices.filter { index in
                entries[index].title.lowercased().contains(query) || entries[index].body.lowercased().contains(query)
            }
        }
        table.reloadData()
        if let selectedEntry, let row = filtered.firstIndex(of: selectedEntry) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: entries[filtered[row]].title)
        text.lineBreakMode = .byTruncatingTail
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        commitBody()
        let row = table.selectedRow
        guard filtered.indices.contains(row) else {
            selectedEntry = nil
            bodyView.string = ""
            return
        }
        selectedEntry = filtered[row]
        bodyView.string = entries[filtered[row]].body
    }

    func textDidChange(_ notification: Notification) {
        commitBody()
    }

    private func commitBody() {
        guard let selectedEntry, entries.indices.contains(selectedEntry) else { return }
        entries[selectedEntry].body = bodyView.string
        let firstLine = bodyView.string
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !firstLine.isEmpty {
            entries[selectedEntry].title = String(firstLine.prefix(60))
            let row = table.selectedRow
            if row >= 0 {
                table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
            }
        }
        PromptLibraryStore.save(entries)
    }

    @objc private func searchChanged() { refilter() }

    @objc private func makeNew() {
        commitBody()
        let entry = PromptEntry(id: UUID(), title: "New prompt", body: "")
        entries.append(entry)
        PromptLibraryStore.save(entries)
        selectedEntry = entries.count - 1
        refilter()
        if let row = filtered.firstIndex(of: entries.count - 1) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        bodyView.string = ""
        makeFirstResponder(bodyView)
    }

    @objc private func deleteSelected() {
        guard let selectedEntry else { return }
        entries.remove(at: selectedEntry)
        self.selectedEntry = nil
        bodyView.string = ""
        PromptLibraryStore.save(entries)
        refilter()
    }

    @objc private func insertSelected() {
        commitBody()
        guard let selectedEntry, entries.indices.contains(selectedEntry) else { return }
        let body = entries[selectedEntry].body
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.showMainWindow(nil)
        app.updateMode(to: .chat)
        GrokChatInjector.fill(body, into: app.webView)
        orderOut(nil)
    }

    @objc private func exportJSON() {
        commitBody()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "grok-prompts.json"
        panel.beginSheetModal(for: self) { [entries] response in
            guard response == .OK, let url = panel.url else { return }
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: url)
            }
        }
    }

    @objc private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let data = try? Data(contentsOf: url),
                  let incoming = try? JSONDecoder().decode([PromptEntry].self, from: data) else { return }
            var merged = self.entries
            for entry in incoming where !merged.contains(where: { $0.id == entry.id }) {
                merged.append(entry)
            }
            self.entries = merged
            PromptLibraryStore.save(merged)
            self.refilter()
        }
    }
}
