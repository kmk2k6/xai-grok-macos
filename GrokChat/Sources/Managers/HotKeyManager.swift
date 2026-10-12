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
