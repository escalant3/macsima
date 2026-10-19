// SPDX-License-Identifier: GPL-2.0-or-later
//
// Ported from wxMaxima's src/SyntaxErrorLocation.cpp (commit 13e4aee, GH #289):
//
//  Copyright (C) 2026 Gunter Königsmann <wxMaxima@physikbuch.de>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// Finds where in a code cell a Maxima syntax error is. For a syntax error
/// Maxima's parser (mread-synerr in nparse.lisp) prints
///
///     incorrect syntax: , is not a prefix operator
///     f(a,,
///        ^
///
/// the message, then the last (up to 20) characters of the line it has read,
/// then a caret. The echo ends where the parser stopped, at or one character
/// after the offending token. This reads that text and finds the same
/// characters in the statement. If Maxima prints something else, nothing is
/// found and the whole statement stays marked. Offsets are UTF-16.
public enum SyntaxErrorLocation {
    /// Maxima's parser never echoes more than this many characters of a line.
    static let maxEchoLength = 20

    /// The line Maxima echoes under its first "incorrect syntax:" message, or
    /// nil when the output holds no complete report (the caret line tells
    /// that the echo is complete).
    public static func echo(in output: String) -> String? {
        guard let start = output.range(of: "incorrect syntax:") else { return nil }
        // "\r\n" is one Character in Swift, so split on any newline.
        let lines = output[start.lowerBound...].split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "\r", with: "") }
        // lines[0] is the message. Only look a few lines further: a caret that
        // far down belongs to something else.
        guard lines.count > 2 else { return nil }
        for i in 2..<min(lines.count, 5) where isCaretLine(lines[i]) {
            return lines[i - 1]
        }
        return nil
    }

    /// The characters to mark in `cellText` for the syntax error in `output`:
    /// the token Maxima stopped at, plus the one character after it it may
    /// have read ahead. `statement` is the failing statement's range.
    public static func locate(output: String, cellText: String, statement: Range<Int>) -> Range<Int>? {
        guard let echo = echo(in: output) else { return nil }
        let text = Array(cellText.utf16)
        let statement = statement.lowerBound..<min(statement.upperBound, text.count)
        for candidate in candidates(echo) {
            let e = Array(candidate.utf16)
            guard let pos = find(e, in: text, within: statement) else { continue }
            // Maxima stopped reading where the echo ends; trailing blanks it
            // read are not what's wrong.
            var end = pos + e.count
            while end > pos + 1, isSpace(text[end - 1]) { end -= 1 }
            // It may have read one character beyond the offending token, so
            // the mark starts one early and takes in all of that token.
            var start = end - pos >= 2 ? end - 2 : pos
            while start > pos, isTokenChar(text[start]), isTokenChar(text[start - 1]) { start -= 1 }
            return start..<end
        }
        return nil
    }

    /// The echo as printed, then with Maxima 5.46's spelled-out blanks.
    static func candidates(_ echo: String) -> [String] {
        var list = [echo]
        if echo.contains("Space") || echo.contains("Tab") {
            list.append(echo.replacingOccurrences(of: "Space", with: " ").replacingOccurrences(of: "Tab", with: "\t"))
        }
        return list
    }

    /// Where the echo is in `statement`. A short echo is the whole start of
    /// its line, so an occurrence starting a line wins over others.
    static func find(_ echo: [UInt16], in text: [UInt16], within statement: Range<Int>) -> Int? {
        guard !echo.isEmpty, echo.count <= statement.count else { return nil }
        let startsALine = echo.count < maxEchoLength
        var first: Int?
        var pos = statement.lowerBound
        while pos + echo.count <= statement.upperBound {
            defer { pos += 1 }
            guard Array(text[pos..<(pos + echo.count)]) == echo else { continue }
            if !startsALine { return pos }
            // Where the statement starts is a line start for Maxima's parser
            // too: the statement is sent on its own.
            if pos == statement.lowerBound || text[pos - 1] == 10 { return pos }
            if first == nil { first = pos }
        }
        return first
    }

    static func isCaretLine(_ line: String) -> Bool {
        var trimmed = line
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        guard trimmed.hasSuffix("^") else { return false }
        return trimmed.dropLast().allSatisfy { $0 == " " }
    }

    static func isTokenChar(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 37 || c > 127
    }

    static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
}
