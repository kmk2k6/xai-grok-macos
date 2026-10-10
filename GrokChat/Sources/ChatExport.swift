//
//  ChatExport.swift
//  Grok for Mac
//
//  Writes the current page's visible text to Markdown or PDF.
//

import AppKit
import CoreText
import UniformTypeIdentifiers
import WebKit

enum ChatExporter {
    static func export(from webView: WKWebView, window: NSWindow) {
        let js = """
        (function() {
            var root = document.querySelector('main') || document.body;
            var text = (root && root.innerText) ? root.innerText : '';
            return JSON.stringify({ title: document.title || 'Grok chat', text: text });
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            var title = "Grok chat"
            var text = ""
            if let raw = result as? String,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                title = object["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? title
                text = object["text"] ?? ""
            }
            DispatchQueue.main.async {
                presentSavePanel(title: title, text: text, window: window)
            }
        }
    }

    private static func presentSavePanel(title: String, text: String, window: NSWindow) {
        let panel = NSSavePanel()
        let markdown = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [markdown, .pdf]
        panel.nameFieldStringValue = sanitized(title) + ".md"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let document = "# \(title)\n\n\(body.isEmpty ? "No conversation text found." : body)\n"
            if url.pathExtension.lowercased() == "pdf" {
                try? writePDF(document, to: url)
            } else {
                try? document.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func sanitized(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Grok chat" : String(trimmed.prefix(80))
    }

    private static func writePDF(_ text: String, to url: URL) throws {
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = CGRect(x: 48, y: 48, width: 516, height: 696)
        var index = 0
        while index < attributed.length {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: media.height)
            context.scaleBy(x: 1, y: -1)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: index, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()
            if visible.length <= 0 { break }
            index += visible.length
        }
        context.closePDF()
        try (data as Data).write(to: url)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
