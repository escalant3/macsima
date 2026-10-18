// SPDX-License-Identifier: GPL-2.0-or-later

/// Recognizes errors and interrupts in a statement's plain-text output.
///
/// Relies on these strings from Maxima 5.50.0 on SBCL (fixtures 04, 05, 06,
/// 21, 22, 28, 30):
/// - `-- an error.` inside a line: merror and error(), with the message on
///   the lines before it (or in a `math` chunk); also
///   ` -- an error.  Entering the Maxima debugger.` with debugmode(true).
/// - A line starting `incorrect syntax:`, then the input echo and a caret line.
/// - A line `Maxima encountered a Lisp error:`, the message, then
///   `Automatically continuing.` The message ` User interrupt` comes from the
///   interrupt channel, ` Interactive interrupt at #x…` from SIGINT.
enum OutputClassifier {
    enum Verdict: Equatable {
        case error(ErrorKind, message: String)
        case interrupted
    }

    static func classify(_ lines: [String]) -> Verdict? {
        if let start = lines.firstIndex(where: { $0.hasPrefix("Maxima encountered a Lisp error:") }) {
            let rest = lines[(start + 1)...]
            let end = rest.firstIndex(where: { $0.hasPrefix("Automatically continuing.") }) ?? rest.endIndex
            let body = rest[..<end].map(\.trimmingWhitespace).filter { !$0.isEmpty }
            if body == ["User interrupt"] || body.first?.hasPrefix("Interactive interrupt at") == true {
                return .interrupted
            }
            return .error(.lisp, message: body.joined(separator: "\n"))
        }
        if let start = lines.firstIndex(where: { $0.hasPrefix("incorrect syntax:") }) {
            return .error(.syntax, message: lines[start...].joined(separator: "\n"))
        }
        if let marker = lines.lastIndex(where: { $0.contains("-- an error.") }) {
            let body = lines[..<marker].filter { !$0.trimmingWhitespace.isEmpty }
            return .error(.maxima, message: body.joined(separator: "\n"))
        }
        return nil
    }
}
