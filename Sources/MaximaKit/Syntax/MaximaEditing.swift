// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Text edits the code editor makes for the user: indentation and comments.
/// Offsets are UTF-16, as NSString and the text views count.
public enum MaximaEditing {
    public static let indentUnit = "  "

    /// What follows a newline typed at the end of `line` (the current line up
    /// to the caret): its indentation, one level deeper when the line leaves
    /// a bracket open.
    public static func indentAfterNewline(line: String) -> String {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var depth = 0
        for token in MaximaTokenizer.tokenize(line) where token.kind == .bracket {
            let c = (line as NSString).substring(with: NSRange(location: token.range.lowerBound, length: 1))
            depth += "([{".contains(c) ? 1 : -1
        }
        return depth > 0 ? indent + indentUnit : indent
    }

    /// When a closing bracket is typed on a line holding only indentation
    /// (`line`, up to the caret), the indentation it should get instead:
    /// one level less. Nil when nothing changes.
    public static func indentBeforeClosing(line: String) -> String? {
        guard !line.isEmpty, line.allSatisfy({ $0 == " " }), line.count >= indentUnit.count else { return nil }
        return String(line.dropLast(indentUnit.count))
    }

    /// Cmd+/: comments out the lines the selection touches (the caret's line
    /// when nothing is selected) as one `/* ... */`, or removes that comment
    /// when the lines already are one. Returns the range to replace, its new
    /// text, and the selection afterwards.
    public static func toggleComment(in text: String, selection: NSRange) -> (range: NSRange, text: String, selection: NSRange) {
        let ns = text as NSString
        var lines = ns.lineRange(for: selection)
        // The newline that ends the last line stays outside the comment, and
        // a selection ending at the start of a line doesn't take that line.
        if selection.length > 0, NSMaxRange(selection) > lines.location,
           ns.length >= NSMaxRange(selection), NSMaxRange(selection) > 0,
           ns.character(at: NSMaxRange(selection) - 1) == 10, NSMaxRange(selection) < NSMaxRange(lines) {
            lines = ns.lineRange(for: NSRange(location: selection.location, length: selection.length - 1))
        }
        if lines.length > 0, ns.character(at: NSMaxRange(lines) - 1) == 10 { lines.length -= 1 }
        let block = ns.substring(with: lines)
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        let new: String
        if trimmed.hasPrefix("/*"), trimmed.hasSuffix("*/"), trimmed.count >= 4 {
            let lead = String(block.prefix { $0 == " " || $0 == "\t" })
            var inner = String(trimmed.dropFirst(2).dropLast(2))
            if inner.hasPrefix(" ") { inner.removeFirst() }
            if inner.hasSuffix(" ") { inner.removeLast() }
            new = lead + inner
        } else {
            let lead = String(block.prefix { $0 == " " || $0 == "\t" })
            new = lead + "/* " + block.dropFirst(lead.count) + " */"
        }
        return (lines, new, NSRange(location: lines.location, length: (new as NSString).length))
    }
}
