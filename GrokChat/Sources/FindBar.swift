//
//  FindBar.swift
//  Grok for Mac
//
//  Native find bar for the web view. Uses window.find in the page.
//

import AppKit

final class GrokFindField: NSTextField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class GrokFindBar: NSView {
    let field = GrokFindField(string: "")
    var onFind: ((String, Bool) -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.94).cgColor

        field.placeholderString = "Find"
        field.setAccessibilityLabel("Find in page")
        field.target = self
        field.action = #selector(findNext)
        field.onEscape = { [weak self] in self?.onClose?() }
        field.translatesAutoresizingMaskIntoConstraints = false

        let previous = NSButton(title: "Previous", target: self, action: #selector(findPrevious))
        previous.bezelStyle = .rounded
        previous.setAccessibilityLabel("Find previous")
        let next = NSButton(title: "Next", target: self, action: #selector(findNext))
        next.bezelStyle = .rounded
        next.setAccessibilityLabel("Find next")
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.setAccessibilityLabel("Close find bar")

        let stack = NSStackView(views: [field, previous, next, done])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        setAccessibilityLabel("Find bar")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func findNext() {
        onFind?(field.stringValue, false)
    }

    @objc private func findPrevious() {
        onFind?(field.stringValue, true)
    }

    @objc private func close() {
        onClose?()
    }
}
