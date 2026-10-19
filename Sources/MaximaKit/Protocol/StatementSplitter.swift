// SPDX-License-Identifier: GPL-2.0-or-later

/// One statement to send to Maxima.
public struct Statement: Equatable, Sendable {
    public enum Terminator: String, Sendable {
        /// `;` shows the result.
        case show = ";"
        /// `$` hides it.
        case hide = "$"
        /// A `:lisp`-style line command, sent without a terminator.
        case line = ""
    }

    /// The text to send, terminator included.
    public var text: String
    public var terminator: Terminator

    public init(text: String, terminator: Terminator) {
        self.text = text
        self.terminator = terminator
    }
}

/// A place in a cell's text, 1-based; the column counts Characters.
public struct SourcePosition: Equatable, Sendable, CustomStringConvertible {
    public var line: Int
    public var column: Int
    public var description: String { "line \(line), column \(column)" }

    /// The same place as a UTF-16 offset into `text`, or nil past its end.
    public func utf16Offset(in text: String) -> Int? {
        var line = 1, column = 1, offset = 0
        for c in text {
            if line == self.line && column == self.column { return offset }
            if c == "\n" { line += 1; column = 1 } else { column += 1 }
            offset += c.utf16.count
        }
        return line == self.line && column == self.column ? offset : nil
    }
}

public enum SplitError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A closing bracket with no matching opener, or the wrong kind.
    case unexpectedClose(Character, at: SourcePosition, expected: Character?)
    /// An opening bracket that is never closed in its statement.
    case unclosed(Character, at: SourcePosition)
    case unclosedString(at: SourcePosition)
    case unclosedComment(at: SourcePosition)

    /// Where the problem is.
    public var position: SourcePosition {
        switch self {
        case .unexpectedClose(_, let at, _), .unclosed(_, let at), .unclosedString(let at), .unclosedComment(let at): at
        }
    }

    public var description: String {
        switch self {
        case let .unexpectedClose(c, at, expected?):
            "Unbalanced parentheses: found \"\(c)\" at \(at) where \"\(expected)\" was expected."
        case let .unexpectedClose(c, at, nil):
            "Unbalanced parentheses: \"\(c)\" at \(at) closes nothing."
        case let .unclosed(c, at):
            "Unbalanced parentheses: \"\(c)\" at \(at) is never closed."
        case let .unclosedString(at):
            "The string starting at \(at) is never closed."
        case let .unclosedComment(at):
            "The comment starting at \(at) is never closed."
        }
    }
}

/// Splits a code cell into statements, as wxMaxima's evaluation queue does:
/// on `;` and `$` outside strings and `/* */` comments (which nest, as in
/// Maxima), with `:lisp` and other `:command` lines running to the end of
/// their line. Adds `;` when the last statement has no terminator, skips
/// pieces holding only comments, and refuses unbalanced brackets so that
/// nothing is sent that would leave Maxima waiting for more input.
public enum StatementSplitter {
    public static func split(_ cell: String) throws(SplitError) -> [Statement] {
        try splitWithSpans(cell).map(\.statement)
    }

    /// Where each statement `split` returns is in `cell`, as UTF-16 offsets
    /// (as NSString and text views count): from its first character to its
    /// terminator, included.
    public static func ranges(_ cell: String) throws(SplitError) -> [Range<Int>] {
        let spans = try splitWithSpans(cell)
        var utf16: [Int] = [0]   // UTF-16 offset of each Character index
        utf16.reserveCapacity(cell.count + 1)
        for c in cell { utf16.append(utf16.last! + c.utf16.count) }
        return spans.map { utf16[$0.span.lowerBound]..<utf16[$0.span.upperBound] }
    }

    /// The statements with the Character range each one covers in `cell`.
    static func splitWithSpans(_ cell: String) throws(SplitError) -> [(statement: Statement, span: Range<Int>)] {
        let chars = Array(cell)
        var positions: [SourcePosition] = []
        positions.reserveCapacity(chars.count + 1)
        var line = 1, column = 1
        for c in chars {
            positions.append(SourcePosition(line: line, column: column))
            if c == "\n" { line += 1; column = 1 } else { column += 1 }
        }
        positions.append(SourcePosition(line: line, column: column))

        var statements: [(statement: Statement, span: Range<Int>)] = []
        var i = 0
        while i < chars.count {
            // Skip whitespace and comments up to the statement's first code character.
            if chars[i].isWhitespace { i += 1; continue }
            if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i = try skipComment(chars, from: i, positions: positions)
                continue
            }
            let start = i
            if chars[i] == ":", i + 1 < chars.count, chars[i + 1].isLetter {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                var end = i
                while end > start, chars[end - 1].isWhitespace { end -= 1 }
                statements.append((Statement(text: String(chars[start..<i]).trimmingWhitespace, terminator: .line), start..<end))
                continue
            }
            var brackets: [(Character, Int)] = []
            var terminator: Statement.Terminator?
            while i < chars.count, terminator == nil {
                let c = chars[i]
                switch c {
                case "\"":
                    i = try skipString(chars, from: i, positions: positions)
                    continue
                case "/" where i + 1 < chars.count && chars[i + 1] == "*":
                    i = try skipComment(chars, from: i, positions: positions)
                    continue
                case "\\":
                    i += 2   // an escaped character, as in a\;b
                    continue
                case "(", "[", "{":
                    brackets.append((c, i))
                case ")", "]", "}":
                    let want: Character = c == ")" ? "(" : c == "]" ? "[" : "{"
                    guard let (open, _) = brackets.last, open == want else {
                        let expected = brackets.last.map { closer(for: $0.0) }
                        throw .unexpectedClose(c, at: positions[i], expected: expected)
                    }
                    brackets.removeLast()
                case ";": terminator = .show
                case "$": terminator = .hide
                default: break
                }
                i += 1
            }
            if let (open, at) = brackets.last { throw .unclosed(open, at: positions[at]) }
            var end = min(i, chars.count)
            var text = String(chars[start..<end]).trimmingWhitespace
            if terminator == nil { text += ";" }
            while end > start, chars[end - 1].isWhitespace { end -= 1 }
            statements.append((Statement(text: text, terminator: terminator ?? .show), start..<end))
        }
        return statements
    }

    private static func closer(for open: Character) -> Character {
        open == "(" ? ")" : open == "[" ? "]" : "}"
    }

    /// Returns the index after the string that starts at `from`.
    private static func skipString(_ chars: [Character], from: Int,
                                   positions: [SourcePosition]) throws(SplitError) -> Int {
        var i = from + 1
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "\"" { return i + 1 }
            i += 1
        }
        throw .unclosedString(at: positions[from])
    }

    /// Returns the index after the (possibly nested) comment that starts at `from`.
    private static func skipComment(_ chars: [Character], from: Int,
                                    positions: [SourcePosition]) throws(SplitError) -> Int {
        var depth = 0
        var i = from
        while i + 1 < chars.count {
            if chars[i] == "/" && chars[i + 1] == "*" { depth += 1; i += 2; continue }
            if chars[i] == "*" && chars[i + 1] == "/" {
                depth -= 1
                i += 2
                if depth == 0 { return i }
                continue
            }
            i += 1
        }
        throw .unclosedComment(at: positions[from])
    }
}
