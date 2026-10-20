// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A page of Maxima's manual: what `macsima-help` (macsima.lisp) replies.
public struct HelpPage: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// `diff`, or `diff <1>` when the manual has several.
        public var name: String
        /// The manual section, `Functions and Variables for Integration`.
        public var section: String
        /// The text `describe` prints.
        public var text: String
    }

    public var topic: String
    public var entries: [Entry]
    /// Inexact matches: topics whose names contain this one.
    public var related: [String]
    /// Set when Maxima could not read its manual.
    public var error: String?

    public init(topic: String, entries: [Entry] = [], related: [String] = [], error: String? = nil) {
        self.topic = topic
        self.entries = entries
        self.related = related
        self.error = error
    }
}

/// A piece of a manual entry (`MaximaHelp.blocks`).
public enum HelpBlock: Equatable, Sendable {
    /// `Function: integrate`.
    case heading(String)
    /// `integrate (<expr>, <x>)`, one call form.
    case signature(String)
    /// A paragraph, or a list item (`bullet`), `level` steps in.
    case prose(String, level: Int, bullet: Bool)
    /// Lines kept as they are: examples, tables.
    case code(String)
}

public enum MaximaHelp {
    /// Parses the content of a `<macsima-help>` tag.
    public static func parse(_ content: String) -> HelpPage {
        func one(_ tag: String, in s: Substring) -> String? {
            guard let a = s.range(of: "<\(tag)>"), let b = s.range(of: "</\(tag)>", range: a.upperBound..<s.endIndex) else { return nil }
            return unescape(String(s[a.upperBound..<b.lowerBound]))
        }
        let all = Substring(content)
        var page = HelpPage(topic: one("topic", in: all) ?? "")
        for match in content.matches(of: /<entry>(.*?)<\/entry>/.dotMatchesNewlines()) {
            let body = match.1
            page.entries.append(HelpPage.Entry(name: one("name", in: body) ?? "", section: one("section", in: body) ?? "",
                                               text: one("text", in: body) ?? ""))
        }
        if let a = content.range(of: "<related>"), let b = content.range(of: "</related>") , a.upperBound <= b.lowerBound {
            page.related = content[a.upperBound..<b.lowerBound].matches(of: /<name>(.*?)<\/name>/).map { unescape(String($0.1)) }
        }
        page.error = one("error", in: all)
        return page
    }

    /// The topic for the caret: the name it is in or next to, else the
    /// operator there (`:=`, `''`), as wxMaxima's F1 takes the word under
    /// the caret. Nil in strings, comments and white space.
    public static func topic(in text: String, caret: Int) -> String? {
        let tokens = MaximaTokenizer.tokenize(text)
        let ns = text as NSString
        let near = tokens.filter { $0.range.lowerBound <= caret && caret <= $0.range.upperBound }
        let token = near.first { $0.kind == .identifier || $0.kind == .keyword }
            ?? near.first { $0.kind == .operator }
        guard let token else { return nil }
        let piece = ns.substring(with: NSRange(location: token.range.lowerBound, length: token.range.count))
        // A name with escapes (`a\-b`) is looked up without the backslashes.
        return piece.replacingOccurrences(of: "\\", with: "")
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The names a page refers to, quoted the way the info manual quotes
    /// them (‘quad_qag’), as ranges in `text`.
    public static func references(in text: String) -> [(range: Range<String.Index>, name: String)] {
        text.matches(of: /‘([^’\n]+)’/).map { ($0.range, String($0.1)) }
    }

    /// An entry's text in pieces a panel can lay out: the info manual's
    /// lines are filled to 70 columns, so prose is joined into paragraphs
    /// that wrap at any width, and the rest keeps its lines. Info's
    /// `*note name::` references become ‘name’.
    public static func blocks(_ text: String) -> [HelpBlock] {
        let text = text.replacing(/\*[Nn]ote\s+([^:]+?)::/) { "‘" + $0.1.split(whereSeparator: \.isWhitespace).joined(separator: " ") + "’" }
        var blocks: [HelpBlock] = []
        var lines: [Substring] = []
        func indent(_ line: Substring) -> Int { line.prefix { $0 == " " }.count }
        func flush() {
            defer { lines = [] }
            guard let first = lines.first else { return }
            let body = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            if first.hasPrefix(" -- ") {
                blocks.append(.heading(String(first.dropFirst(4))))
                blocks += body.dropFirst().map { .signature($0) }
            } else if lines.allSatisfy({ indent($0) == 5 }) {
                blocks.append(.prose(body.joined(separator: " "), level: 0, bullet: false))
            } else if body[0].hasPrefix("• "), lines.dropFirst().allSatisfy({ indent($0) == indent(first) + 2 }) {
                blocks.append(.prose(String(body.joined(separator: " ").dropFirst(2)), level: max(0, (indent(first) - 5) / 3), bullet: true))
            } else {
                let least = lines.map(indent).min() ?? 0
                blocks.append(.code(lines.map { String($0.dropFirst(least)) }.joined(separator: "\n")))
            }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() } else { lines.append(line) }
        }
        flush()
        return blocks
    }
}
