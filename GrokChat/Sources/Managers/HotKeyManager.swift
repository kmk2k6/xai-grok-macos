//
//  HotKeyManager.swift
//  Grok for Mac
//
//  Created by Brandon Charleson on 2025.
//  Copyright © 2025 Brandon Charleson. All rights reserved.
//
//  https://github.com/bcharleson/xai-grok
//

import Cocoa
import Carbon
import WebKit

protocol HotKeyDelegate: AnyObject {
    func hotKeyTriggered()
    func screenshotHotKeyTriggered()
    func grokBotHotKeyTriggered()
}

class HotKeyManager {
    static let shared = HotKeyManager()
    weak var delegate: HotKeyDelegate?
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var grokBotHotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID(signature: OSType(0x47524F4B), id: 1) // 'GROK', 1
    
    private var currentKeyCode: UInt32 = 49 // Space
    private var currentModifiers: UInt32 = UInt32(optionKey) // Option
    
    // Presets
    enum ShortcutPreset: Int {
        case optionSpace = 0
        case controlSpace = 1
        case commandShiftG = 2
        case optionG = 3
        
        var name: String {
            switch self {
            case .optionSpace: return "Option + Space"
            case .controlSpace: return "Control + Space"
            case .commandShiftG: return "Command + Shift + G"
            case .optionG: return "Option + G"
            }
        }
        
        var keyCode: UInt32 {
            switch self {
            case .optionSpace: return 49 // Space
            case .controlSpace: return 49 // Space
            case .commandShiftG: return 5 // G
            case .optionG: return 5 // G
            }
        }
        
        var modifiers: UInt32 {
            switch self {
            case .optionSpace: return UInt32(optionKey)
            case .controlSpace: return UInt32(controlKey)
            case .commandShiftG: return UInt32(cmdKey | shiftKey)
            case .optionG: return UInt32(optionKey)
            }
        }
    }

    /// Region-capture shortcut. Default is Control-Option-4.
    enum ScreenshotPreset: Int {
        case controlOption4 = 0
        case optionShift4 = 1
        case controlShift4 = 2

        var name: String {
            switch self {
            case .controlOption4: return "Control + Option + 4"
            case .optionShift4: return "Option + Shift + 4"
            case .controlShift4: return "Control + Shift + 4"
            }
        }

        var keyCode: UInt32 { 21 } // kVK_ANSI_4

        var modifiers: UInt32 {
            switch self {
            case .controlOption4: return UInt32(controlKey | optionKey)
            case .optionShift4: return UInt32(optionKey | shiftKey)
            case .controlShift4: return UInt32(controlKey | shiftKey)
            }
        }
    }
    
    func setup() {
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressed
            )
            if status == noErr && pressed.id == 2 {
                HotKeyManager.shared.delegate?.screenshotHotKeyTriggered()
            } else if status == noErr && pressed.id == 3 {
                HotKeyManager.shared.delegate?.grokBotHotKeyTriggered()
            } else {
                HotKeyManager.shared.delegate?.hotKeyTriggered()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        
        // Load preference
        let saved = UserDefaults.standard.integer(forKey: "hotkeyPreset")
        let preset = ShortcutPreset(rawValue: saved) ?? .optionSpace
        setPreset(preset)
        let shot = ScreenshotPreset(rawValue: UserDefaults.standard.integer(forKey: "screenshotHotkeyPreset")) ?? .controlOption4
        setScreenshotPreset(shot)
        let bot = GrokBotPreset(rawValue: UserDefaults.standard.integer(forKey: "grokBotHotkeyPreset")) ?? .controlOptionG
        setGrokBotPreset(bot)
    }
    
    func setPreset(_ preset: ShortcutPreset) {
        // Save
        UserDefaults.standard.set(preset.rawValue, forKey: "hotkeyPreset")
        
        // Register
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        
        let id = EventHotKeyID(signature: OSType(0x47524F4B), id: 1)
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        #if DEBUG
        print("Registered HotKey: \(preset.name)")
        #endif
    }

    func setScreenshotPreset(_ preset: ScreenshotPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: "screenshotHotkeyPreset")
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x47524F4B), id: 2)
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &screenshotHotKeyRef)
    }

    enum GrokBotPreset: Int {
        case controlOptionG = 0
        case controlOptionB = 1
        case optionShiftG = 2

        var keyCode: UInt32 { 5 } // G, except B

        var modifiers: UInt32 {
            switch self {
            case .controlOptionG: return UInt32(controlKey | optionKey)
            case .controlOptionB: return UInt32(controlKey | optionKey)
            case .optionShiftG: return UInt32(optionKey | shiftKey)
            }
        }

        var registeredKeyCode: UInt32 {
            self == .controlOptionB ? 11 : 5 // kVK_ANSI_B or G
        }
    }

    func setGrokBotPreset(_ preset: GrokBotPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: "grokBotHotkeyPreset")
        if let ref = grokBotHotKeyRef {
            UnregisterEventHotKey(ref)
            grokBotHotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x47524F4B), id: 3)
        RegisterEventHotKey(preset.registeredKeyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &grokBotHotKeyRef)
    }
}

enum GrokBotSwitcher {
    static let pathKey = "grok.bot.appPath"

    static func resolvedURL() -> URL? {
        if let custom = UserDefaults.standard.string(forKey: pathKey), !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        let roots = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let names = ["Grok Bot.app", "GrokBot.app"]
        for root in roots {
            for name in names {
                let path = (root as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
            guard let folder = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in folder where name.hasSuffix(".app") {
                let base = (name as NSString).deletingPathExtension
                if base.localizedCaseInsensitiveContains("grok bot") {
                    return URL(fileURLWithPath: (root as NSString).appendingPathComponent(name))
                }
            }
        }
        return nil
    }

    static func toggle() {
        guard let url = resolvedURL() else {
            (NSApp.delegate as? AppDelegate)?.showSettings(nil)
            return
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        let alreadyFront = (bundleID != nil && front?.bundleIdentifier == bundleID) || front?.bundleURL?.path == url.path
        if alreadyFront {
            (NSApp.delegate as? AppDelegate)?.showMainWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static let bundleID = "com.anysphere.sand"
    static let downloadURL = URL(string: "https://x.ai/bot")!

    // MARK: - Week 4: bot switcher / routines / usage

    // Design decisions (Week 4 roadmap: "Bot switcher + routines + dual usage"):
    //  • Deep links — the native Grok Bot desktop app (`com.anysphere.sand`) registers
    //    the custom URL scheme `grokbot://`. Opening a `grokbot://app/v1/...` URL
    //    launches/foregrounds the app directly on a specific screen, so the switcher,
    //    routines, and usage items navigate for real (not just a generic launch).
    //    We open the URL with NSWorkspace and do NOT also separately foreground the
    //    app — opening the URL alone already foregrounds it (opening the URL *and*
    //    launching would race and briefly show the wrong window). If the open fails
    //    (scheme not registered / app not installed), we fall back to the Weeks 1-3
    //    desktop-app launcher so the control still does something sensible.
    //  • Switcher — data-driven from `grok.bot.switcherBots` (editable in Settings),
    //    seeded with Kevin's 7 bots by default so the switcher offers real choices
    //    out of the box. Each entry's URL is a per-bot `grokbot://app/v1/agent?id=…`.
    //  • Routines — `grokbot://app/v1/sidebar?tab=routines` opens the routines view.
    //  • Usage — `grokbot://app/v1/settings?id=usage` opens the usage screen. This is
    //    a real navigation, not a fabricated number; the grok.com bolt percent row is
    //    left untouched.

    static let switcherBotsKey = "grok.bot.switcherBots"
    /// Dedicated keys for the Routines/Usage shortcuts so they do NOT share the
    /// switcher's bot namespace (a bot named "Routines"/"Usage" must not silently
    /// become the shortcut target). Each holds a single deep-link string, validated
    /// by `isAllowedBotURL`. Seeded with the defaults below when absent.
    static let routinesURLKey = "grok.bot.routinesURL"
    static let usageURLKey = "grok.bot.usageURL"

    /// Grok Bot's custom URL scheme (registered by the native desktop app).
    static let deepLinkScheme = "grokbot"
    /// The only `grokbot://` path prefixes we will open. Validation is on scheme +
    /// path prefix so query strings (`?id=…`, `?tab=routines`) are preserved intact.
    private static let allowedDeepLinkPaths: Set<String> = [
        "/app/v1/agent",
        "/app/v1/sidebar",
        "/app/v1/settings"
    ]
    /// https hosts we still accept (kept from the prior allow-list; harmless and lets
    /// a user paste a grok.com/x.ai page if they ever want one).
    private static let allowedURLHosts: Set<String> = ["grok.com", "x.ai"]

    /// Default routines/usage deep links. Routines points at the App bot (where
    /// routines live): `grokbot://app/v1/sidebar?tab=routines` does nothing when
    /// opened from outside Grok Bot, so the item opens the App agent instead and
    /// then brings the app forward (see `openRoutines`).
    static let defaultRoutinesURL = "grokbot://app/v1/agent?id=6a759f88-706f-461c-b19f-0b2b3f3eb317"
    static let defaultUsageURL = "grokbot://app/v1/settings?id=usage"

    /// Kevin's bots, seeded as the default switcher list. Editable in Settings.
    static let defaultSwitcherBots: [[String: String]] = [
        ["name": "App",       "url": "grokbot://app/v1/agent?id=6a759f88-706f-461c-b19f-0b2b3f3eb317"],
        ["name": "Architect", "url": "grokbot://app/v1/agent?id=4ab54d19-a02f-4381-ad06-4e25fc2fd57e"],
        ["name": "Music",     "url": "grokbot://app/v1/agent?id=76b1eac7-ead5-44f0-90e9-490e6dc0b0c3"],
        ["name": "Finance",   "url": "grokbot://app/v1/agent?id=154f2612-0b93-4f1c-b9a7-3c6ce2198cb2"],
        ["name": "Email",     "url": "grokbot://app/v1/agent?id=36c5f33c-fddb-46d9-9b86-cc0fecc366d0"],
        ["name": "Job",       "url": "grokbot://app/v1/agent?id=609bbaa1-3844-44f3-804e-31a9d6dbe697"],
        ["name": "Health",    "url": "grokbot://app/v1/agent?id=7777b49d-1389-43c6-8ff1-f5e37d5de628"]
    ]

    /// One configurable Grok Bot destination.
    struct BotEntry {
        var name: String
        var url: URL?
    }

    /// True for an allowed destination: a `grokbot://` URL whose path is one of the
    /// three permitted `app/v1/{agent,sidebar,settings}` prefixes (query preserved),
    /// or an https grok.com/x.ai URL. Anything else is rejected so a stray defaults
    /// value can never send us somewhere unexpected via NSWorkspace.
    static func isAllowedBotURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case deepLinkScheme:
            // Normalize the path. For grokbot://app/v1/agent, URLComponents reports
            // host "app" and path "/v1/agent"; rebuild the full "/app/v1/agent" form.
            let host = url.host.map { "/" + $0 } ?? ""
            let fullPath = host + url.path
            return allowedDeepLinkPaths.contains(where: { fullPath == $0 || fullPath.hasPrefix($0 + "/") })
        case "https":
            guard let host = url.host?.lowercased() else { return false }
            return allowedURLHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        default:
            return false
        }
    }

    /// Reads the switcher bot list from UserDefaults, seeding Kevin's defaults when
    /// the key is absent. Each row is a `[String: String]` with a required `name`
    /// and an optional `url`; a `url` is only kept when it passes `isAllowedBotURL`.
    static func configuredBots() -> [BotEntry] {
        return bots(from: rawBots())
    }

    /// Parses stored rows into `BotEntry` values, keeping a `url` only when it is
    /// present and passes `isAllowedBotURL`. Pure so Settings and the runtime agree.
    static func bots(from rows: [[String: String]]) -> [BotEntry] {
        return rows.compactMap { row in
            guard let name = row["name"], !name.isEmpty else { return nil }
            let url: URL?
            if let raw = row["url"], !raw.isEmpty, let parsed = URL(string: raw), isAllowedBotURL(parsed) {
                url = parsed
            } else {
                url = nil
            }
            return BotEntry(name: name, url: url)
        }
    }

    /// The raw `[name:…, url:…]` rows backing the switcher, seeded with the defaults
    /// when the key is absent. This is what the Settings editor reads and rewrites so
    /// reordering and renaming round-trips through the same storage the runtime uses.
    static func rawBots() -> [[String: String]] {
        return (UserDefaults.standard.array(forKey: switcherBotsKey) as? [[String: String]]) ?? defaultSwitcherBots
    }

    /// Persists edited switcher rows (reordered and/or relabeled). Rows with an empty
    /// name are dropped; the `url` string is preserved verbatim so an existing bot's
    /// destination is never altered by a rename. The runtime picks the new order up on
    /// its next `configuredBots()` read.
    static func saveRawBots(_ rows: [[String: String]]) {
        let cleaned: [[String: String]] = rows.compactMap { row in
            let name = (row["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var out: [String: String] = ["name": name]
            if let url = row["url"], !url.isEmpty { out["url"] = url }
            return out
        }
        UserDefaults.standard.set(cleaned, forKey: switcherBotsKey)
    }

    /// Opens a validated deep link with NSWorkspace. Opening the `grokbot://` URL
    /// launches/foregrounds the native app at the right screen, so this is the single
    /// action — we do NOT also call the launcher. If the open fails (scheme not
    /// registered / app missing), we fall back to the desktop-app launcher.
    private static func openDeepLink(_ url: URL) {
        guard isAllowedBotURL(url) else {
            launchOrBringForward()
            return
        }
        if !NSWorkspace.shared.open(url) {
            launchOrBringForward()
        }
    }

    /// Opens a bot entry: open its validated deep link if present (which foregrounds
    /// the app at that bot); otherwise fall back to bringing the Grok Bot app forward.
    static func open(_ entry: BotEntry) {
        if let url = entry.url {
            openDeepLink(url)
        } else {
            launchOrBringForward()
        }
    }

    /// Opens the deep link stored under `defaultsKey` (seeded with `fallback` when the
    /// key is absent), falling back to the launcher if it is missing or invalid.
    private static func openDeepLink(forKey defaultsKey: String, fallback: String) {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        if !raw.isEmpty, let url = URL(string: raw) {
            openDeepLink(url)
        } else {
            launchOrBringForward()
        }
    }

    /// Routines shortcut — opens the App bot (where routines live) via
    /// `grokbot://app/v1/agent?id=…` and then brings Grok Bot forward. The old
    /// `sidebar?tab=routines` deep link did nothing when opened from outside the
    /// app, so we open the agent and explicitly foreground it.
    static func openRoutines() {
        openDeepLink(forKey: routinesURLKey, fallback: defaultRoutinesURL)
        launchOrBringForward()
    }

    /// "Open usage" action — opens the usage screen via `grokbot://app/v1/settings?id=usage`.
    /// Never fabricates a number.
    static func openUsage() {
        openDeepLink(forKey: usageURLKey, fallback: defaultUsageURL)
    }

    /// Grok Bot.app in /Applications, matched by name or bundle id.
    static func installedApplicationURL() -> URL? {
        let root = URL(fileURLWithPath: "/Applications", isDirectory: true)
        for name in ["Grok Bot.app", "GrokBot.app"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           url.path.hasPrefix("/Applications/") {
            return url
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return nil }
        for name in names where name.hasSuffix(".app") {
            let url = root.appendingPathComponent(name)
            let base = (name as NSString).deletingPathExtension
            if Bundle(url: url)?.bundleIdentifier == bundleID || base.localizedCaseInsensitiveContains("grok bot") {
                return url
            }
        }
        return nil
    }

    /// Launch Grok Bot, or bring it forward if it is already running.
    static func launchOrBringForward() {
        guard let url = installedApplicationURL() else {
            presentMissingNote()
            return
        }
        let identifier = Bundle(url: url)?.bundleIdentifier ?? bundleID
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func presentMissingNote() {
        let alert = NSAlert()
        alert.messageText = "Grok Bot isn't installed"
        alert.informativeText = "Download Grok Bot from x.ai/bot, then try again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }
}

/// Copies a Grok answer or code block and brings the Grok Bot app forward. Kevin pastes and sends.
enum SendToGrokBot {
    static let handlerName = "grokSendToBot"
    static let preface = "Review, build and install this on my Mac:"

    static func copyAndReveal(_ content: String) {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let clip = preface + "\n\n" + body
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip, forType: .string)
        GrokBotSwitcher.launchOrBringForward()
    }

    static func handle(_ message: WKScriptMessage) {
        let text: String?
        if let body = message.body as? [String: Any] {
            text = body["text"] as? String
        } else {
            text = message.body as? String
        }
        guard let text else { return }
        DispatchQueue.main.async { copyAndReveal(text) }
    }

    static func injectIfNeeded(into webView: WKWebView) {
        guard let host = webView.url?.host?.lowercased(),
              host == "grok.com" || host.hasSuffix(".grok.com") else { return }
        webView.evaluateJavaScript(pageScript, completionHandler: nil)
    }

    private static let pageScript = """
    (function() {
      if (window.__grokSendToBotInstalled) return;
      window.__grokSendToBotInstalled = true;
      window.__grokSendToBotText = "";

      function deliver(text) {
        text = (text || "").trim();
        if (!text) return;
        try {
          window.webkit.messageHandlers.grokSendToBot.postMessage({ text: text });
        } catch (e) {}
      }

      function plain(el) {
        if (!el) return "";
        var clone = el.cloneNode(true);
        var junk = clone.querySelectorAll(".grok-send-bot-btn, button, textarea, nav");
        for (var i = 0; i < junk.length; i++) junk[i].remove();
        return (clone.innerText || clone.textContent || "").trim();
      }

      function codeText(pre) {
        var code = pre.querySelector("code");
        return plain(code || pre);
      }

      function answerText(root) {
        var content = root;
        if (!root.matches || !root.matches(".response-content-markdown")) {
          var markdown = root.querySelector(".response-content-markdown");
          if (markdown) content = markdown;
          else {
            var assistant = root.querySelector("[data-testid='assistant-message'], .message-bubble.assistant");
            if (assistant) content = assistant;
          }
        }
        return plain(content);
      }

      function inComposer(el) {
        return !!(el && el.closest && el.closest("[data-testid='chat-input'], textarea"));
      }

      function userOnly(el) {
        if (!el || !el.closest) return false;
        if (el.closest("[data-testid='user-message']")) return true;
        if (el.id && el.id.indexOf("response-") === 0 && el.classList.contains("items-end")) {
          if (!el.querySelector("[data-testid='assistant-message'], .message-bubble.assistant, .response-content-markdown")) return true;
        }
        return false;
      }

      function targetText(node) {
        if (!node || !node.closest || inComposer(node)) return "";
        var pre = node.closest("pre");
        if (pre && !inComposer(pre)) {
          var code = codeText(pre);
          if (code) return code;
        }
        var answer = node.closest("[data-testid='assistant-message'], .message-bubble.assistant, .response-content-markdown, div[id^='response-']");
        if (!answer || userOnly(answer) || inComposer(answer)) return "";
        return answerText(answer);
      }

      function ensureStyle() {
        if (document.getElementById("grok-send-bot-style")) return;
        var style = document.createElement("style");
        style.id = "grok-send-bot-style";
        style.textContent = [
          ".grok-send-bot-btn{",
          "position:absolute;top:6px;right:8px;z-index:30;",
          "margin:0;padding:4px 8px;border-radius:6px;cursor:pointer;",
          "border:1px solid rgba(255,255,255,.22);background:rgba(18,18,18,.9);color:#fff;",
          "font:600 11px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;",
          "opacity:0;pointer-events:none;",
          "}",
          ".grok-send-bot-btn.is-code{right:auto;left:8px;top:8px;}",
          ".grok-send-bot-host:hover > .grok-send-bot-btn,.grok-send-bot-btn:focus{",
          "opacity:1;pointer-events:auto;",
          "}"
        ].join("");
        (document.head || document.documentElement).appendChild(style);
      }

      function hasOwnButton(host) {
        for (var child = host.firstElementChild; child; child = child.nextElementSibling) {
          if (child.classList && child.classList.contains("grok-send-bot-btn")) return true;
        }
        return false;
      }

      function attach(host, kind) {
        if (!host || hasOwnButton(host)) return;
        var text = kind === "code" ? codeText(host) : answerText(host);
        if (!text) return;
        ensureStyle();
        if (window.getComputedStyle(host).position === "static") host.style.position = "relative";
        host.classList.add("grok-send-bot-host");
        var button = document.createElement("button");
        button.type = "button";
        button.className = "grok-send-bot-btn" + (kind === "code" ? " is-code" : "");
        button.textContent = "Send to Grok Bot";
        button.setAttribute("aria-label", "Send to Grok Bot");
        button.addEventListener("click", function(event) {
          event.preventDefault();
          event.stopPropagation();
          deliver(kind === "code" ? codeText(host) : answerText(host));
        }, true);
        host.appendChild(button);
      }

      function scan() {
        var answers = [];
        var nodes = document.querySelectorAll("[data-testid='assistant-message'], .message-bubble.assistant, .response-content-markdown, div[id^='response-']");
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          if (userOnly(node) || inComposer(node)) continue;
          var nested = false;
          for (var j = 0; j < answers.length; j++) {
            if (answers[j].contains(node)) { nested = true; break; }
            if (node.contains(answers[j])) { answers.splice(j, 1); j--; }
          }
          if (!nested) answers.push(node);
        }
        for (var a = 0; a < answers.length; a++) attach(answers[a], "answer");
        var blocks = document.querySelectorAll("pre");
        for (var b = 0; b < blocks.length; b++) {
          if (inComposer(blocks[b])) continue;
          attach(blocks[b], "code");
        }
      }

      document.addEventListener("contextmenu", function(event) {
        var node = event.target && event.target.nodeType === 1 ? event.target : (event.target && event.target.parentElement);
        window.__grokSendToBotText = targetText(node);
      }, true);

      scan();
      var timer = null;
      var observer = new MutationObserver(function() {
        if (timer) return;
        timer = setTimeout(function() { timer = null; scan(); }, 250);
      });
      try { observer.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
    })();
    """
}
