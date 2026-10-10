import Cocoa
import UniformTypeIdentifiers

struct GrokAttachment {
    var filename: String
    var mime: String
    var data: Data
    var path: String
}

/// "Ask Grok about this" for selected text and Finder files.
/// The system Services menu comes from workflows in ~/Library/Services so the app Info.plist stays untouched.
final class GrokAskService: NSObject {
    static let shared = GrokAskService()
    static let version = 1

    private var watch: DispatchSourceFileSystemObject?
    private var watchFD: Int32 = -1

    func start() {
        installWorkflows()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        startWatching()
        consumeIfPresent()
    }

    /// Service message, used when the system invokes this app directly.
    @objc func askGrokAboutSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            receive(files: urls.map(\.path))
            return
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            receive(text: text)
            return
        }
        error?.pointee = "Nothing selected to send to Grok."
    }

    func consumeIfPresent() {
        let url = Self.pendingURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: url)
        if let text = object["text"] as? String, object["kind"] as? String == "text" {
            receive(text: text)
        } else if let paths = object["paths"] as? [String] {
            receive(files: paths)
        }
    }

    private func receive(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.beginGrokChat(prompt: trimmed, attachments: [])
        }
    }

    private func receive(files paths: [String]) {
        let attachments = paths.compactMap { Self.attachment(at: $0) }
        let note = paths.map { path -> String in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if !exists { return path }
            if isDir.boolValue { return path }
            if attachments.contains(where: { $0.path == path }) { return path }
            if let text = Self.textExcerpt(at: path) { return "\(path)\n\(text)" }
            return path
        }.joined(separator: "\n\n")
        DispatchQueue.main.async {
            let delegate = NSApp.delegate as? AppDelegate
            if attachments.isEmpty {
                delegate?.beginGrokChat(prompt: note, attachments: [])
            } else {
                delegate?.beginGrokChat(prompt: nil, attachments: attachments, fallbackNote: note)
            }
        }
    }

    static func attachment(at path: String) -> GrokAttachment? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty, data.count <= 6_000_000 else { return nil }
        let ext = (path as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .data
        return GrokAttachment(
            filename: (path as NSString).lastPathComponent,
            mime: type.preferredMIMEType ?? "application/octet-stream",
            data: data,
            path: path
        )
    }

    private static func textExcerpt(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 100_000,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(20_000))
    }

    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Grok", isDirectory: true)
    }

    private static var pendingURL: URL {
        supportDirectory.appendingPathComponent("pending-ask.json")
    }

    private func startWatching() {
        let dir = Self.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        watchFD = open(dir.path, O_EVTONLY)
        guard watchFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFD,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.consumeIfPresent()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchFD, fd >= 0 { close(fd) }
        }
        source.resume()
        watch = source
    }

    private func installWorkflows() {
        let stamp = UserDefaults.standard.integer(forKey: "grok.askServiceVersion")
        let services = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
        let textURL = services.appendingPathComponent("Ask Grok about this.workflow")
        let fileURL = services.appendingPathComponent("Ask Grok about these files.workflow")
        if stamp == Self.version,
           FileManager.default.fileExists(atPath: textURL.path),
           FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }
        try? FileManager.default.createDirectory(at: services, withIntermediateDirectories: true)
        writeWorkflow(
            at: textURL,
            bundleID: "com.xai.Grok.ask-about-text",
            menuTitle: "Ask Grok about this",
            sendTypes: ["NSStringPboardType", "public.utf8-plain-text"],
            fileTypes: nil,
            finderOnly: false,
            inputIdentifier: "com.apple.Automator.text",
            command: Self.textScript,
            arguments: false
        )
        writeWorkflow(
            at: fileURL,
            bundleID: "com.xai.Grok.ask-about-files",
            menuTitle: "Ask Grok about this",
            sendTypes: nil,
            fileTypes: ["public.item", "public.folder"],
            finderOnly: true,
            inputIdentifier: "com.apple.Automator.fileSystemObject",
            command: Self.fileScript,
            arguments: true
        )
        UserDefaults.standard.set(Self.version, forKey: "grok.askServiceVersion")
    }

    private func writeWorkflow(
        at url: URL,
        bundleID: String,
        menuTitle: String,
        sendTypes: [String]?,
        fileTypes: [String]?,
        finderOnly: Bool,
        inputIdentifier: String,
        command: String,
        arguments: Bool
    ) {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        var service: [String: Any] = [
            "NSMenuItem": ["default": menuTitle],
            "NSMessage": "runWorkflowAsService"
        ]
        if let sendTypes { service["NSSendTypes"] = sendTypes }
        if let fileTypes { service["NSSendFileTypes"] = fileTypes }
        if finderOnly {
            service["NSRequiredContext"] = ["NSApplicationIdentifier": "com.apple.finder"]
        }
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": bundleID,
            "CFBundleName": menuTitle,
            "CFBundleShortVersionString": "1.0",
            "NSServices": [service]
        ]
        let document = workflowDocument(command: command, inputIdentifier: inputIdentifier, arguments: arguments, finderOnly: finderOnly)
        writePlist(info, to: contents.appendingPathComponent("Info.plist"))
        writePlist(document, to: resources.appendingPathComponent("document.wflow"))
    }

    private func workflowDocument(command: String, inputIdentifier: String, arguments: Bool, finderOnly: Bool) -> [String: Any] {
        let action: [String: Any] = [
            "AMAccepts": [
                "Container": "List",
                "Optional": true,
                "Types": ["com.apple.cocoa.string"]
            ],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": [
                "COMMAND_STRING": [:],
                "CheckedForUserDefaultShell": [:],
                "inputMethod": [:],
                "shell": [:],
                "source": [:]
            ],
            "AMProvides": [
                "Container": "List",
                "Types": ["com.apple.cocoa.string"]
            ],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": [
                "COMMAND_STRING": command,
                "CheckedForUserDefaultShell": true,
                "inputMethod": arguments ? 1 : 0,
                "shell": "/bin/bash",
                "source": ""
            ],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": "B1E0E0E0-0000-4000-8000-000000000001",
            "Keywords": ["Shell", "Script", "Run"],
            "OutputUUID": "B1E0E0E0-0000-4000-8000-000000000002",
            "UUID": "B1E0E0E0-0000-4000-8000-000000000003",
            "UnlocalizedApplications": ["Automator"],
            "arguments": [:],
            "isViewVisible": 0
        ]
        return [
            "AMApplicationBuild": "523",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action, "isViewVisible": 0]],
            "connectors": [:],
            "workflowMetaData": [
                "serviceApplicationBundleID": finderOnly ? "com.apple.finder" : "",
                "serviceInputTypeIdentifier": inputIdentifier,
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 0,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ]
        ]
    }

    private func writePlist(_ object: [String: Any], to url: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) else { return }
        try? data.write(to: url)
    }

    private static let textScript = """
    /usr/bin/python3 -c 'import json,sys,pathlib; p=pathlib.Path.home()/"Library/Application Support/Grok/pending-ask.json"; p.parent.mkdir(parents=True, exist_ok=True); tmp=p.with_suffix(".json.tmp"); tmp.write_text(json.dumps({"kind":"text","text":sys.stdin.read()})); tmp.replace(p)'
    open -a Grok
    """

    private static let fileScript = """
    /usr/bin/python3 - "$@" <<'PY'
    import json, pathlib, sys
    p = pathlib.Path.home() / "Library/Application Support/Grok/pending-ask.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"kind":"files","paths":sys.argv[1:]}))
    tmp.replace(p)
    PY
    open -a Grok
    """
}
