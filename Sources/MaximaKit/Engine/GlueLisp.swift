// SPDX-License-Identifier: GPL-2.0-or-later
//
// The framing of the glue Lisp follows wxMaxima's wxMathML::GetCmd
// (src/wxMathml.cpp) and the setup lines its MaximaEvaluator sends;
// wxMaxima is Copyright (C) Andrej Vodopivec, Gunter Koenigsmann and the
// wxMaxima developers, GPL-2.0-or-later.

import Foundation

/// The glue Lisp (`wxMathML.lisp`) and the lines sent around it.
public enum GlueLisp {
    /// `wxMathML.lisp` as shipped in this package, unmodified from wxMaxima.
    public static func bundledSource() throws(MaximaError) -> String {
        guard let url = Bundle.module.url(forResource: "wxMathML", withExtension: "lisp"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw .glueMissing
        }
        return text
    }

    /// Builds the one-line `:lisp-quiet` command: strip leading indentation
    /// and `;` comments outside strings, join the lines with spaces.
    public static func command(from lisp: String) -> String {
        var out = ""
        var inString = false
        for line in lisp.split(separator: "\n", omittingEmptySubsequences: true) {
            let chars = Array(line)
            var kept = ""
            var atLineStart = true
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if atLineStart && (ch == " " || ch == "\t") { i += 1; continue }
                atLineStart = false
                if ch == "\\" {
                    kept.append(ch)
                    i += 1
                    if i < chars.count { kept.append(chars[i]) }
                    i += 1
                    continue
                }
                if ch == "\"" { inString.toggle() }
                if ch == ";" && !inString { break }
                kept.append(ch)
                i += 1
            }
            out += kept + " "
        }
        return ":lisp-quiet " + out + "\n"
    }

    /// The lines sent once the session is authenticated. None of them is
    /// answered with a prompt (checked against 5.50.0), so nobody waits.
    public static func setupLines(gnuplotPath: String, port: UInt16, token: String, tempDirectory: String) -> [String] {
        [
            ":lisp-quiet (setf $gnuplot_command \(lispString(gnuplotPath)))\n",
            ":lisp-quiet (setf $maxima_tempdir \(lispString(tempDirectory)))\n",
            ":lisp-quiet (when (fboundp 'wx-open-interrupt-channel) (wx-open-interrupt-channel \"127.0.0.1\" \(port) \(lispString(token))))\n",
            ":lisp-quiet (ignore-errors (setf (symbol-value '*lisp-quiet-suppressed-prompt*) \"<PROMPT>(%i1)</PROMPT>\"))\n",
            ":lisp-quiet (setf *prompt-suffix* \"</PROMPT>\") (setf *prompt-prefix* \"<PROMPT>\") (setf $in_netmath nil) (setf $show_openplot t) \n",
        ]
    }

    /// Sent before each statement (not in Lisp mode).
    public static func lineWidthLine(_ columns: Int) -> String {
        ":lisp-quiet (setq $linel \(columns))\n"
    }

    /// Sent before the first statement of a cell (not in Lisp mode).
    public static func cellIDLine(_ id: String) -> String {
        ":lisp-quiet (setq *wx-cell-id* \(lispString(id)))\n"
    }

    /// A Lisp string literal.
    static func lispString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
