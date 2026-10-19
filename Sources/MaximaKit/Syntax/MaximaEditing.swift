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
}
