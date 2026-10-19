// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A piece of Maxima input, for syntax highlighting and bracket matching.
/// Ranges are UTF-16 offsets, as NSString and the text views count.
public struct MaximaToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `/* ... */`; comments nest in Maxima.
        case comment
        /// `"..."`, with `\` escaping the next character.
        case string
        /// `12`, `1.`, `.5`, `1.5e-3`, `2b3` (bigfloat), `1.5d0`.
        case number
        /// `if`, `then`, `for`, `and`, ...
        case keyword
        /// A Maxima name: letters, digits, `_`, `%`, and `\`-escaped characters.
        case identifier
        /// `?name`: a Lisp symbol.
        case lispSymbol
        /// `(`, `[`, `{`, `)`, `]`, `}`.
        case bracket
        /// `,`.
        case separator
        /// `;` or `$`.
        case terminator
        /// Any other operator: `:`, `:=`, `+`, `'`, ...
        case `operator`
        /// A `:lisp` or `:lisp-quiet` line.
        case lispLine
    }

    public var kind: Kind
    public var range: Range<Int>

    public init(_ kind: Kind, _ range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// Splits Maxima input into tokens. The lexing rules were checked against
/// Maxima 5.50.0 (`Tests/Fixtures/transcripts/raw/32-lexing.txt`): comments
/// nest, `\` escapes in strings and names, `1.` is an integer, and `e`, `b`
/// and `d` start exponents. Unterminated comments and strings run to the end.
public enum MaximaTokenizer {
    public static let keywords: Set<String> = [
        "if", "then", "else", "elseif", "for", "from", "step", "thru", "while", "unless",
        "do", "in", "next", "and", "or", "not",
    ]

    public static func tokenize(_ text: String) -> [MaximaToken] {
        let s = Array(text.utf16)
        var tokens: [MaximaToken] = []
        var i = 0
        var lineStart = true   // only whitespace since the last newline
        func at(_ k: Int) -> UInt16 { k < s.count ? s[k] : 0 }

        while i < s.count {
            let c = s[i]
            let start = i
            if c == 10 { lineStart = true; i += 1; continue }
            if isSpace(c) { i += 1; continue }
            defer { lineStart = false }

            if c == ch("/"), at(i + 1) == ch("*") {
                i = endOfComment(s, from: i)
                tokens.append(MaximaToken(.comment, start..<i))
            } else if c == ch("\"") {
                i += 1
                while i < s.count, s[i] != ch("\"") { i += s[i] == ch("\\") ? 2 : 1 }
                i = min(i + 1, s.count)
                tokens.append(MaximaToken(.string, start..<i))
            } else if lineStart, c == ch(":"), startsWith(s, i, ":lisp") {
                while i < s.count, s[i] != 10 { i += 1 }
                tokens.append(MaximaToken(.lispLine, start..<i))
            } else if isDigit(c) || (c == ch(".") && isDigit(at(i + 1))) {
                i = endOfNumber(s, from: i)
                tokens.append(MaximaToken(.number, start..<i))
            } else if isNameStart(c) {
                i = endOfName(s, from: i)
                let word = String(utf16CodeUnits: Array(s[start..<i]), count: i - start)
                tokens.append(MaximaToken(keywords.contains(word) ? .keyword : .identifier, start..<i))
            } else if c == ch("?"), i + 1 < s.count, isNameStart(s[i + 1]) {
                i = endOfName(s, from: i + 1)
                tokens.append(MaximaToken(.lispSymbol, start..<i))
            } else if "([{)]}".utf16.contains(c) {
                i += 1
                tokens.append(MaximaToken(.bracket, start..<i))
            } else if c == ch(",") {
                i += 1
                tokens.append(MaximaToken(.separator, start..<i))
            } else if c == ch(";") || c == ch("$") {
                i += 1
                tokens.append(MaximaToken(.terminator, start..<i))
            } else {
                // A run of operator characters, stopping before a comment.
                i += 1
                while i < s.count, isOperator(s[i]), !(s[i] == ch("/") && at(i + 1) == ch("*")) { i += 1 }
                tokens.append(MaximaToken(.operator, start..<i))
            }
        }
        return tokens
    }

    /// The bracket next to the caret (the one before it first, else the one
    /// after it) and its partner, as UTF-16 offsets. Brackets in strings and
    /// comments don't count; nil when there is no bracket or no partner of
    /// the same type.
    public static func matchingBracket(in text: String, caret: Int) -> (Int, Int)? {
        let s = Array(text.utf16)
        let brackets = tokenize(text).filter { $0.kind == .bracket }.map(\.range.lowerBound)
        guard let here = brackets.firstIndex(of: caret - 1) ?? brackets.firstIndex(of: caret) else { return nil }
        let opens = Array("([{".utf16), closes = Array(")]}".utf16)
        let c = s[brackets[here]]
        var depth = 0
        if let type = opens.firstIndex(of: c) {
            for k in here..<brackets.count {
                let d = s[brackets[k]]
                if opens.contains(d) { depth += 1 } else { depth -= 1 }
                if depth == 0 { return closes[type] == d ? (brackets[here], brackets[k]) : nil }
            }
        } else if let type = closes.firstIndex(of: c) {
            for k in stride(from: here, through: 0, by: -1) {
                let d = s[brackets[k]]
                if closes.contains(d) { depth += 1 } else { depth -= 1 }
                if depth == 0 { return opens[type] == d ? (brackets[k], brackets[here]) : nil }
            }
        }
        return nil
    }

    // MARK: - Pieces

    private static func endOfComment(_ s: [UInt16], from start: Int) -> Int {
        var depth = 0
        var i = start
        while i < s.count {
            if s[i] == ch("/"), i + 1 < s.count, s[i + 1] == ch("*") {
                depth += 1
                i += 2
            } else if s[i] == ch("*"), i + 1 < s.count, s[i + 1] == ch("/") {
                depth -= 1
                i += 2
                if depth == 0 { return i }
            } else {
                i += 1
            }
        }
        return s.count
    }

    private static func endOfNumber(_ s: [UInt16], from start: Int) -> Int {
        var i = start
        while i < s.count, isDigit(s[i]) { i += 1 }
        if i < s.count, s[i] == ch(".") {
            i += 1
            while i < s.count, isDigit(s[i]) { i += 1 }
        }
        // An exponent only when digits follow: `2e` is a name after a number.
        if i < s.count, "eEbBdD".utf16.contains(s[i]) {
            var j = i + 1
            if j < s.count, s[j] == ch("+") || s[j] == ch("-") { j += 1 }
            if j < s.count, isDigit(s[j]) {
                while j < s.count, isDigit(s[j]) { j += 1 }
                i = j
            }
        }
        return i
    }

    private static func endOfName(_ s: [UInt16], from start: Int) -> Int {
        var i = start
        while i < s.count {
            if s[i] == ch("\\") {
                i = min(i + 2, s.count)
            } else if isNameStart(s[i]) || isDigit(s[i]) {
                i += 1
            } else {
                break
            }
        }
        return i
    }

    private static func startsWith(_ s: [UInt16], _ i: Int, _ prefix: String) -> Bool {
        let p = Array(prefix.utf16)
        return i + p.count <= s.count && Array(s[i..<(i + p.count)]) == p
    }

    private static func ch(_ c: Character) -> UInt16 { c.utf16.first! }
    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 13 || c == 0xA0 }
    private static func isNameStart(_ c: UInt16) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == ch("_") || c == ch("%") || c == ch("\\") || (c >= 0x80 && c != 0xA0)
    }
    private static func isOperator(_ c: UInt16) -> Bool {
        !(isDigit(c) || isNameStart(c) || isSpace(c) || c == 10 || "\"([{)]},;$?".utf16.contains(c))
    }
}
