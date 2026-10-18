// SPDX-License-Identifier: GPL-2.0-or-later

/// What a `<PROMPT>` asks for (wxMaxima's prompt classes, MaximaProtocol.h).
public enum PromptKind: Equatable, Sendable {
    /// A main input prompt such as `(%i3) `. The queue may send the next statement.
    case main(label: Int)
    /// The Maxima debugger, `(dbm:N)`.
    case debugger(level: Int)
    /// The Lisp REPL after `to_lisp()`, `MAXIMA>`.
    case lisp
    /// Anything else is a question for the user, such as `asksign`'s
    /// `<math><st>Is </st>…</math>`. Holds the prompt content unchanged.
    case question(String)
}

public enum PromptClassifier {
    /// Classifies the content between `<PROMPT>` and `</PROMPT>`. Observed with
    /// 5.50.0: main prompts are `(%iN) `, or `(%iN)` without the space after a
    /// `:lisp` line; Lisp and debugger prompts start with a newline.
    public static func classify(_ content: String) -> PromptKind {
        let trimmed = content.trimmingWhitespace
        if let n = number(in: trimmed, prefix: "(%i", suffix: ")") { return .main(label: n) }
        if let n = number(in: trimmed, prefix: "(dbm:", suffix: ")") { return .debugger(level: n) }
        if trimmed == "MAXIMA>" { return .lisp }
        return .question(content)
    }

    private static func number(in s: String, prefix: String, suffix: String) -> Int? {
        guard s.hasPrefix(prefix), s.hasSuffix(suffix), s.count > prefix.count + suffix.count else { return nil }
        let digits = s.dropFirst(prefix.count).dropLast(suffix.count)
        guard digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(digits)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

extension StringProtocol {
    var trimmingWhitespace: String {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = lastIndex { !$0.isWhitespace }.map { index(after: $0) } ?? endIndex
        return start < end ? String(self[start..<end]) : ""
    }
}
