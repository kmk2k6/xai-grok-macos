import Cocoa
import WebKit

/// Types a prompt into the grok.com composer and submits it.
enum GrokChatInjector {
    static func inject(_ prompt: String, into webView: WKWebView, attempt: Int = 0) {
        let literal = jsonStringLiteral(prompt)
        let js = """
        (function() {
            var text = \(literal);
            var input = document.querySelector('textarea') ||
                        document.querySelector('[contenteditable="true"]') ||
                        document.querySelector('input[type="text"]');
            if (!input) { return false; }
            input.focus();
            if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
                var proto = input.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
                var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
                setter.call(input, text);
                input.dispatchEvent(new Event('input', { bubbles: true }));
            } else {
                input.textContent = text;
                input.dispatchEvent(new InputEvent('input', { bubbles: true, data: text }));
            }
            setTimeout(function() {
                var submitBtn = null;
                var buttons = document.querySelectorAll('button');
                for (var i = 0; i < buttons.length; i++) {
                    var btn = buttons[i];
                    var label = (btn.getAttribute('aria-label') || '').toLowerCase();
                    var title = (btn.textContent || '').toLowerCase();
                    if (label.indexOf('send') !== -1 || title.indexOf('send') !== -1) {
                        submitBtn = btn;
                        break;
                    }
                }
                if (!submitBtn) {
                    submitBtn = document.querySelector('button[type="submit"]') ||
                                document.querySelector('[data-testid="send-button"]');
                }
                if (submitBtn && !submitBtn.disabled) {
                    submitBtn.click();
                } else {
                    input.dispatchEvent(new KeyboardEvent('keydown', {
                        bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13
                    }));
                }
            }, 200);
            return true;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            let placed = (result as? Bool) ?? false
            if !placed && attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    inject(prompt, into: webView, attempt: attempt + 1)
                }
            }
        }
    }

    /// Puts text in the composer and leaves it there for the user to edit.
    static func fill(_ prompt: String, into webView: WKWebView, attempt: Int = 0) {
        let literal = jsonStringLiteral(prompt)
        let js = """
        (function() {
            var text = \(literal);
            var input = document.querySelector('textarea') ||
                        document.querySelector('[contenteditable="true"]') ||
                        document.querySelector('input[type="text"]');
            if (!input) { return false; }
            input.focus();
            if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
                var proto = input.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
                var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
                setter.call(input, text);
                input.dispatchEvent(new Event('input', { bubbles: true }));
            } else {
                input.textContent = text;
                input.dispatchEvent(new InputEvent('input', { bubbles: true, data: text }));
            }
            return true;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            let placed = (result as? Bool) ?? false
            if !placed && attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    fill(prompt, into: webView, attempt: attempt + 1)
                }
            }
        }
    }

    /// Puts files on the page upload control, or drops them on the composer. Returns whether an input or drop target existed.
    static func attach(_ files: [GrokAttachment], into webView: WKWebView, attempt: Int = 0, completion: @escaping (Bool) -> Void) {
        guard !files.isEmpty else {
            completion(false)
            return
        }
        let payload = files.map { file -> String in
            let name = jsonStringLiteral(file.filename)
            let mime = jsonStringLiteral(file.mime)
            let b64 = jsonStringLiteral(file.data.base64EncodedString())
            return "{name:\(name),mime:\(mime),b64:\(b64)}"
        }.joined(separator: ",")
        let js = """
        (function() {
            function fileFrom(spec) {
                var binary = atob(spec.b64);
                var bytes = new Uint8Array(binary.length);
                for (var i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
                return new File([bytes], spec.name, { type: spec.mime || 'application/octet-stream' });
            }
            var specs = [\(payload)];
            var made = specs.map(fileFrom);
            var input = document.querySelector('input[type="file"]');
            if (input && typeof DataTransfer !== 'undefined') {
                var transfer = new DataTransfer();
                made.forEach(function(file) { transfer.items.add(file); });
                input.files = transfer.files;
                input.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
            }
            var target = document.querySelector('textarea') || document.querySelector('[contenteditable="true"]') || document.body;
            if (!target || typeof DataTransfer === 'undefined') { return false; }
            var dropTransfer = new DataTransfer();
            made.forEach(function(file) { dropTransfer.items.add(file); });
            ['dragenter', 'dragover', 'drop'].forEach(function(type) {
                target.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dropTransfer }));
            });
            return true;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            if let placed = result as? Bool {
                completion(placed)
            } else if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    attach(files, into: webView, attempt: attempt + 1, completion: completion)
                }
            } else {
                completion(false)
            }
        }
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
    }
}

/// Spotlight-style Quick Ask field. Escape closes the panel.
private final class QuickAskField: NSTextField {
    override func cancelOperation(_ sender: Any?) {
        QuickAskController.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            QuickAskController.close()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Floating prompt panel. Enter is the text field action.
final class QuickAskPanel: NSPanel {
    fileprivate let textField = QuickAskField(frame: .zero)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 64),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        title = "Quick Ask"

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 640, height: 64))
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        contentView = effect

        textField.frame = NSRect(x: 18, y: 14, width: 604, height: 36)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 20, weight: .light)
        textField.placeholderString = "Ask Grok…"
        textField.autoresizingMask = [.width]
        textField.target = self
        textField.action = #selector(submit)
        textField.setAccessibilityLabel("Quick Ask")
        effect.addSubview(textField)
    }

    func prepare(prefill: String?) {
        textField.stringValue = prefill ?? ""
    }

    @objc private func submit() {
        let text = textField.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        (NSApp.delegate as? AppDelegate)?.submitQuickAsk(text)
    }

    override func cancelOperation(_ sender: Any?) {
        QuickAskController.close()
    }
}

enum QuickAskController {
    private static var panel: QuickAskPanel?

    static let prefillFromSelectionKey = "quickAsk.prefillFromSelection"

    static var prefillFromSelection: Bool {
        UserDefaults.standard.bool(forKey: prefillFromSelectionKey)
    }

    static func toggle(prefill: String? = nil) {
        if let panel, panel.isVisible, prefill == nil {
            close()
        } else if prefill == nil {
            captureSelectionThenShow()
        } else {
            show(prefill: prefill)
        }
    }

    /// Copies the frontmost app's selection only when the user turned the setting on.
    private static func captureSelectionThenShow() {
        guard prefillFromSelection else {
            show(prefill: nil)
            return
        }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let previous = pasteboard.string(forType: .string)
        postCopyShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let changed = pasteboard.changeCount != before
            let selected = changed ? pasteboard.string(forType: .string) : nil
            if changed {
                pasteboard.clearContents()
                if let previous {
                    pasteboard.setString(previous, forType: .string)
                }
            }
            let trimmed = selected?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefill = (trimmed?.isEmpty == false) ? trimmed : nil
            show(prefill: prefill)
        }
    }

    private static func postCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    static func show(prefill: String? = nil) {
        DispatchQueue.main.async {
            let delegate = NSApp.delegate as? AppDelegate
            if !NSApp.isActive, let window = delegate?.window, window.isVisible {
                window.orderOut(nil)
            }
            let panel = panel ?? QuickAskPanel()
            self.panel = panel
            panel.prepare(prefill: prefill)
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let visible = screen.visibleFrame
                let frame = panel.frame
                panel.setFrameOrigin(NSPoint(
                    x: visible.midX - frame.width / 2,
                    y: visible.midY + visible.height / 5
                ))
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeFirstResponder(panel.textField)
        }
    }

    static func close() {
        DispatchQueue.main.async {
            panel?.orderOut(nil)
            if let window = (NSApp.delegate as? AppDelegate)?.window, !window.isVisible {
                NSApp.hide(nil)
            }
        }
    }
}
