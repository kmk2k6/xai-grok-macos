//
//  GrokChatTabs.swift
//  Grok for Mac
//
//  Simple grok.com tab strip. Glass chrome is left alone; the strip sits under it.
//

import AppKit
import WebKit

struct GrokChatTab {
    let id: UUID
    let webView: WKWebView
    var title: String
}

final class GrokChatTabStrip: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityLabel("Chat tabs")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(titles: [String], active: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.isBordered = index == active
            button.font = .systemFont(ofSize: 11, weight: index == active ? .semibold : .regular)
            button.lineBreakMode = .byTruncatingTail
            button.setAccessibilityLabel("Chat tab \(index + 1), \(title)")
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
            stack.addArrangedSubview(button)

            if titles.count > 1 {
                let close = NSButton(title: "×", target: self, action: #selector(closeTab(_:)))
                close.tag = index
                close.isBordered = false
                close.font = .systemFont(ofSize: 12)
                close.setAccessibilityLabel("Close tab \(index + 1)")
                stack.addArrangedSubview(close)
            }
        }
        let plus = NSButton(title: "+", target: self, action: #selector(newTab))
        plus.isBordered = false
        plus.font = .systemFont(ofSize: 14, weight: .medium)
        plus.setAccessibilityLabel("New chat tab")
        stack.addArrangedSubview(plus)
    }

    @objc private func selectTab(_ sender: NSButton) {
        onSelect?(sender.tag)
    }

    @objc private func closeTab(_ sender: NSButton) {
        onClose?(sender.tag)
    }

    @objc private func newTab() {
        onNew?()
    }
}

extension AppDelegate {
    func adoptInitialChatTab() {
        guard chatTabs.isEmpty, let webView else { return }
        webView.autoresizingMask = []
        chatTabs = [GrokChatTab(id: UUID(), webView: webView, title: "Grok")]
        activeChatTabIndex = 0
    }

    func makeAdditionalChatWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.userContentController.add(self, name: WebToBuildBridge.messageHandlerName)
        config.userContentController.add(self, name: GrokUsageBadge.messageHandlerName)
        config.userContentController.add(self, name: SendToGrokBot.handlerName)
        GrokUsageBadge.installUserScript(into: config.userContentController)

        let wv = SilentWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.autoresizingMask = []
        let solid = GlassAppearance.solidMatteNSColor
        wv.setValue(false, forKey: "drawsBackground")
        wv.wantsLayer = true
        wv.layer?.backgroundColor = solid.cgColor
        if #available(macOS 12.0, *) {
            wv.underPageBackgroundColor = solid
        }
        return wv
    }

    @objc func newChatTab(_ sender: Any?) {
        showMainWindow(nil)
        updateMode(to: .chat)
        let wv = makeAdditionalChatWebView()
        chatTabs.append(GrokChatTab(id: UUID(), webView: wv, title: "Grok"))
        activeChatTabIndex = chatTabs.count - 1
        webView = wv
        if let url = URL(string: "https://grok.com") {
            wv.load(URLRequest(url: url))
        }
        layoutChatTabs()
        window?.makeFirstResponder(wv)
    }

    func selectChatTab(_ index: Int) {
        guard chatTabs.indices.contains(index) else { return }
        activeChatTabIndex = index
        webView = chatTabs[index].webView
        if currentMode != .chat {
            updateMode(to: .chat)
        }
        layoutChatTabs()
        window?.makeFirstResponder(webView)
    }

    @objc func selectChatTabFromMenu(_ sender: NSMenuItem) {
        selectChatTab(sender.tag - 1)
    }

    func closeChatTab(at index: Int) {
        guard chatTabs.count > 1, chatTabs.indices.contains(index) else { return }
        let removed = chatTabs.remove(at: index)
        removed.webView.removeFromSuperview()
        if activeChatTabIndex >= chatTabs.count {
            activeChatTabIndex = chatTabs.count - 1
        } else if index < activeChatTabIndex {
            activeChatTabIndex -= 1
        }
        webView = chatTabs[activeChatTabIndex].webView
        layoutChatTabs()
        window?.makeFirstResponder(webView)
    }

    func isChatTab(_ webView: WKWebView) -> Bool {
        chatTabs.contains { $0.webView === webView }
    }

    func noteChatTabTitle(for webView: WKWebView) {
        guard let index = chatTabs.firstIndex(where: { $0.webView === webView }) else { return }
        let raw = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = raw.isEmpty ? "Grok" : String(raw.prefix(40))
        chatTabs[index].title = title
        if currentMode == .chat {
            chatTabStrip?.reload(titles: chatTabs.map(\.title), active: activeChatTabIndex)
        }
    }

    func layoutChatTabs() {
        guard currentMode == .chat, let content = mainContainerView, !chatTabs.isEmpty else {
            chatTabStrip?.removeFromSuperview()
            return
        }
        if chatTabStrip == nil {
            let strip = GrokChatTabStrip(frame: .zero)
            strip.onSelect = { [weak self] index in self?.selectChatTab(index) }
            strip.onClose = { [weak self] index in self?.closeChatTab(at: index) }
            strip.onNew = { [weak self] in self?.newChatTab(nil) }
            chatTabStrip = strip
        }
        let chrome = currentChromeHeight()
        let stripHeight: CGFloat = 30
        let width = content.bounds.width
        let stripY = max(0, content.bounds.height - chrome - stripHeight)
        guard let strip = chatTabStrip else { return }
        strip.frame = NSRect(x: 0, y: stripY, width: width, height: stripHeight)
        if strip.superview !== content {
            content.addSubview(strip)
        }
        let webFrame = NSRect(x: 0, y: 0, width: width, height: stripY)
        for (index, tab) in chatTabs.enumerated() {
            let active = index == activeChatTabIndex
            tab.webView.isHidden = !active
            if active {
                if tab.webView.superview !== content {
                    content.addSubview(tab.webView, positioned: .below, relativeTo: chromeEffectView)
                }
                tab.webView.frame = webFrame
            }
        }
        strip.reload(titles: chatTabs.map(\.title), active: activeChatTabIndex)
        content.addSubview(strip, positioned: .below, relativeTo: chromeEffectView)
    }

    func currentChromeHeight() -> CGFloat {
        guard let content = mainContainerView, let window else { return 52 }
        var chromeHeight = max(0, content.bounds.height - window.contentLayoutRect.height)
        if chromeHeight < 1 { chromeHeight = 52 }
        return chromeHeight
    }
}
