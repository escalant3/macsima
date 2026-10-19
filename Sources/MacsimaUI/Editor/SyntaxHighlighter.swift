// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit

/// The names Maxima knows, from the `<wxxml-symbols>` the glue Lisp prints
/// when a session starts (and again when a package loads). Every window's
/// Maxima is the same program, so one list serves the whole app.
@MainActor
final class MaximaSymbols {
    static let shared = MaximaSymbols()
    init() {}
    static let didChange = Notification.Name("MacsimaMaximaSymbolsDidChange")

    /// Names highlighted as built-ins.
    private(set) var names: Set<String> = []
    /// Function templates (`name` → `name(<x>, <y>)`), for autocompletion later.
    private(set) var templates: [String: String] = [:]

    /// Adds the names in one `<wxxml-symbols>` tag's content.
    func ingest(_ content: String) {
        add(Self.parse(content))
    }

    /// Parses off the main thread (the tag is about 60 KB), then adds.
    func ingestInBackground(_ content: String) {
        Task {
            let parsed = await Task.detached { Self.parse(content) }.value
            add(parsed)
        }
    }

    private func add(_ parsed: (names: Set<String>, templates: [String: String])) {
        let before = names.count
        names.formUnion(parsed.names)
        templates.merge(parsed.templates) { _, new in new }
        if names.count != before { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    nonisolated static func parse(_ content: String) -> (names: Set<String>, templates: [String: String]) {
        var names: Set<String> = [], templates: [String: String] = [:]
        for match in content.matches(of: /<value>([^<]*)<\/value>/) {
            let name = unescape(String(match.1))
            // The list holds every name Maxima's own code interned, single
            // letters like x, a or t among them; those stay plain.
            if name.count > 1 { names.insert(name) }
        }
        for match in content.matches(of: /<function>([^<]*)<\/function><template>([^<]*)<\/template>/) {
            let name = unescape(String(match.1))
            templates[name] = unescape(String(match.2))
            if name.count > 1 { names.insert(name) }
        }
        return (names, templates)
    }

    nonisolated static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Colours a code cell's text. The colours are TextKit 2 rendering
/// attributes: they never touch the text storage, so they never reach undo
/// or the clipboard. System colours follow light and dark mode.
@MainActor
enum SyntaxHighlighter {
    static func color(for kind: MaximaToken.Kind, text: Substring, builtins: Set<String>) -> NSColor? {
        switch kind {
        case .comment: .systemGray
        case .string: .systemRed
        case .number: .systemBlue
        case .keyword: .systemPurple
        case .lispSymbol, .lispLine: .systemOrange
        case .terminator: .secondaryLabelColor
        case .identifier: builtins.contains(String(text)) ? .systemTeal : nil
        case .bracket, .separator, .operator: nil
        }
    }

    /// Replaces the view's syntax colours with ones for its current text;
    /// with `enabled` false (text and heading cells), only removes them.
    static func apply(to view: NSTextView, enabled: Bool) {
        guard let layout = view.textLayoutManager, let content = layout.textContentManager else { return }
        layout.removeRenderingAttribute(.foregroundColor, for: layout.documentRange)
        guard enabled else { return }
        let text = view.string
        let ns = text as NSString
        let builtins = MaximaSymbols.shared.names
        let start = layout.documentRange.location
        for token in MaximaTokenizer.tokenize(text) {
            let piece = ns.substring(with: NSRange(location: token.range.lowerBound, length: token.range.count))
            guard let color = color(for: token.kind, text: Substring(piece), builtins: builtins),
                  let from = content.location(start, offsetBy: token.range.lowerBound),
                  let to = content.location(from, offsetBy: token.range.count),
                  let range = NSTextRange(location: from, end: to) else { continue }
            layout.addRenderingAttribute(.foregroundColor, value: color, for: range)
        }
    }
}
