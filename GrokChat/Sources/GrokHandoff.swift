//
//  GrokHandoff.swift
//  Grok for Mac
//
//  Lists the local Google Drive Grok Bot inbox, outbox, and done folders.
//  Wake Grok runs the existing Keychain script and never reads or prints the secret.

import AppKit

enum GrokHandoff {
    static let wakeScriptURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/grok-bot-setup-check.sh")

    struct FolderSet {
        var root: URL
        var inbox: URL?
        var outbox: URL?
        var done: URL?
    }

    struct ListedFile {
        var url: URL
        var modified: Date
    }

    private static let folderNames = ["inbox", "outbox", "done"]
    private static var cachedWaiting = false
    private static var cachedAt = Date.distantPast
    private static let cacheQueue = DispatchQueue(label: "grok.handoff.scan")

    static var wakeScriptIsPresent: Bool {
        FileManager.default.isReadableFile(atPath: wakeScriptURL.path)
    }

    /// Yellow when an outbox file is newer than the newest done file.
    static func outboxNeedsAttention(force: Bool = false) -> Bool {
        if !force, Date().timeIntervalSince(cachedAt) < 20 {
            return cachedWaiting
        }
        let waiting = computeOutboxNeedsAttention()
        cachedWaiting = waiting
        cachedAt = Date()
        return waiting
    }

    static func refreshAttention(completion: @escaping (Bool) -> Void) {
        cacheQueue.async {
            let waiting = computeOutboxNeedsAttention()
            DispatchQueue.main.async {
                cachedWaiting = waiting
                cachedAt = Date()
                completion(waiting)
            }
        }
    }

    static func locate() -> FolderSet? {
        let cloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage")
        guard let tops = childDirectories(cloud) else { return nil }
        var best: (url: URL, score: Int)?
        var seen = 0
        for top in tops {
            var queue: [(URL, Int)] = [(top, 0)]
            while !queue.isEmpty {
                let (dir, depth) = queue.removeFirst()
                seen += 1
                if seen > 800 { break }
                let kids = childDirectories(dir) ?? []
                let named = Dictionary(uniqueKeysWithValues: kids.map { ($0.lastPathComponent.lowercased(), $0) })
                let hits = folderNames.compactMap { named[$0] }
                let path = dir.path.lowercased()
                if !hits.isEmpty && (path.contains("grok") || hits.count >= 2) {
                    var score = hits.count
                    if path.contains("grok") { score += 5 }
                    if dir.lastPathComponent.lowercased().contains("grok") { score += 3 }
                    if hits.count == 3 { score += 2 }
                    if best == nil || score > best!.score {
                        best = (dir, score)
                    }
                }
                if depth < 6 {
                    for kid in kids where !folderNames.contains(kid.lastPathComponent.lowercased()) {
                        queue.append((kid, depth + 1))
                    }
                }
            }
        }
        guard let root = best?.url else { return nil }
        let named = Dictionary(uniqueKeysWithValues: (childDirectories(root) ?? []).map {
            ($0.lastPathComponent.lowercased(), $0)
        })
        return FolderSet(root: root, inbox: named["inbox"], outbox: named["outbox"], done: named["done"])
    }

    /// The last `limit` handoffs received, i.e. the newest files in the inbox folder.
    static func latestHandoffs(in folders: FolderSet?, limit: Int = 5) -> [ListedFile] {
        newestFiles(in: folders?.inbox, limit: limit)
    }

    static func newestFiles(in folder: URL?, limit: Int = 8) -> [ListedFile] {
        guard let folder, let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { return nil }
            return ListedFile(url: url, modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }
        .prefix(limit)
        .map { $0 }
    }

    /// Runs only the Keychain-signed webhook section of the wake script, in the background.
    /// The script's `open` commands are not run, so this does not open Settings. Output is never logged.
    static func wake(completion: @escaping (String) -> Void) {
        guard wakeScriptIsPresent,
              let script = try? String(contentsOf: wakeScriptURL, encoding: .utf8),
              let program = wakeProgram(in: script) else {
            DispatchQueue.main.async { completion("Wake failed.") }
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-", program.url, program.service, NSUserName()]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { process in
            let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = wakeMessage(stdout: out, stderr: err, status: process.terminationStatus)
            DispatchQueue.main.async { completion(message) }
        }
        do {
            try process.run()
            input.fileHandleForWriting.write(Data(program.python.utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            DispatchQueue.main.async { completion("Wake failed.") }
        }
    }

    private struct WakeProgram {
        var url: String
        var service: String
        var python: String
    }

    /// The python block inside grok-bot-setup-check.sh that signs the webhook from the Keychain.
    private static func wakeProgram(in script: String) -> WakeProgram? {
        guard let url = shellAssignment(script, name: "URL"),
              let service = shellAssignment(script, name: "SERVICE"),
              url.hasPrefix("https://"),
              let start = script.range(of: "<<'PY'\n"),
              let end = script.range(of: "\nPY\n", range: start.upperBound..<script.endIndex) else { return nil }
        let python = String(script[start.upperBound..<end.lowerBound])
        guard python.contains("find-generic-password"), !python.contains("grokbot://") else { return nil }
        return WakeProgram(url: url, service: service, python: python + "\n")
    }

    private static func shellAssignment(_ script: String, name: String) -> String? {
        let prefix = name + "=\""
        for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("\"") else { continue }
            return String(trimmed.dropFirst(prefix.count).dropLast())
        }
        return nil
    }

    private static func wakeMessage(stdout: String, stderr: String, status: Int32) -> String {
        let lines = (stdout + "\n" + stderr)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("whsec_") }
        if status == 0 || lines.contains(where: { $0.contains("WAKE_OK") }) {
            return "Wake sent"
        }
        if let line = lines.first(where: { $0.contains("WAKE_FAIL") || $0.hasPrefix("FAIL:") }) {
            return String(line.prefix(160))
        }
        return "Wake failed."
    }

    private static func computeOutboxNeedsAttention() -> Bool {
        guard let folders = locate(), let outbox = folders.outbox else { return false }
        guard let newestOut = newestFiles(in: outbox, limit: 40).first else { return false }
        let newestDone = newestFiles(in: folders.done, limit: 40).first?.modified ?? .distantPast
        return newestOut.modified > newestDone
    }

    private static func childDirectories(_ url: URL) -> [URL]? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}

final class GrokHandoffPanel: NSWindowController, NSWindowDelegate {
    static let shared = GrokHandoffPanel()

    private let statusField = NSTextField(labelWithString: "")
    private let listStack = NSStackView()
    private var wakeButton: NSButton?
    private var openURLs: [URL] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Grok Bot handoff"
        window.minSize = NSSize(width: 380, height: 320)
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func buildContent() -> NSView {
        let root = NSView()
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let refresh = NSButton(title: "Refresh", target: self, action: #selector(reloadFromButton))
        refresh.bezelStyle = .rounded
        header.addArrangedSubview(refresh)

        if GrokHandoff.wakeScriptIsPresent {
            let wake = NSButton(title: "Wake Grok", target: self, action: #selector(wakeTapped))
            wake.bezelStyle = .rounded
            wakeButton = wake
            header.addArrangedSubview(wake)
        }
        header.addArrangedSubview(NSView())

        statusField.font = .systemFont(ofSize: 12)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byWordWrapping
        statusField.maximumNumberOfLines = 2
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(listStack)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(header)
        column.addArrangedSubview(statusField)
        column.addArrangedSubview(scroll)
        root.addSubview(column)

        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -24),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: document.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return root
    }

    @objc private func reloadFromButton() { reload() }

    func reload() {
        let folders = GrokHandoff.locate()
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let folders else {
            statusField.stringValue = "Google Drive’s Grok Bot folder was not found under Library/CloudStorage."
            return
        }
        statusField.stringValue = folders.root.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        openURLs = []
        addSection("Last 5 handoffs", files: GrokHandoff.latestHandoffs(in: folders))
        addSection("Inbox", files: GrokHandoff.newestFiles(in: folders.inbox))
        addSection("Outbox", files: GrokHandoff.newestFiles(in: folders.outbox))
        addSection("Done", files: GrokHandoff.newestFiles(in: folders.done))
        GrokHandoff.refreshAttention { _ in
            (NSApp.delegate as? AppDelegate)?.refreshUsageStatusButton()
        }
    }

    private func addSection(_ title: String, files: [GrokHandoff.ListedFile]) {
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: 13)
        listStack.addArrangedSubview(heading)
        if files.isEmpty {
            let empty = NSTextField(labelWithString: "No files")
            empty.textColor = .secondaryLabelColor
            listStack.addArrangedSubview(empty)
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for file in files {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            let name = NSTextField(labelWithString: file.url.lastPathComponent)
            name.lineBreakMode = .byTruncatingMiddle
            name.toolTip = file.url.path
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let when = NSTextField(labelWithString: formatter.string(from: file.modified))
            when.textColor = .secondaryLabelColor
            when.font = .systemFont(ofSize: 11)
            let open = NSButton(title: "Open", target: self, action: #selector(openFile(_:)))
            open.bezelStyle = .rounded
            open.tag = openURLs.count
            openURLs.append(file.url)
            row.addArrangedSubview(name)
            row.addArrangedSubview(when)
            row.addArrangedSubview(open)
            listStack.addArrangedSubview(row)
        }
    }

    @objc private func openFile(_ sender: NSButton) {
        guard openURLs.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(openURLs[sender.tag])
    }

    @objc private func wakeTapped() {
        wakeButton?.isEnabled = false
        statusField.stringValue = "Waking…"
        GrokHandoff.wake { [weak self] message in
            self?.wakeButton?.isEnabled = true
            self?.statusField.stringValue = message
        }
    }
}
