// SPDX-License-Identifier: GPL-2.0-or-later
//
// Ported from wxMaxima's src/WXMformat.cpp (TreeToWXM, TreeFromWXM and the
// marker table; commit 13e4aee) and the file frame in Worksheet::ExportToMAC:
//
//  Copyright (C) 2004-2015 Andrej Vodopivec <andrej.vodopivec@gmail.com>
//            (C) 2008-2009 Ziga Lenarcic <zigalenarcic@users.sourceforge.net>
//            (C) 2011-2011 cw.ahbong <cw.ahbong@gmail.com>
//            (C) 2012-2013 Doug Ilijev <doug.ilijev@gmail.com>
//            (C) 2015-2018 Gunter Königsmann <wxMaxima@physikbuch.de>
//            (C) 2020      Kuba Ober <kuba@bertec.com>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// The `.wxm` format: a Maxima batch file whose cells sit between comment
/// markers. It holds inputs, headings, text, page breaks, known answers and
/// the hide flag, but no outputs. wxMaxima also puts cells on the clipboard
/// in this form (`text/x-wxmaxima-batch`).
public enum WXMFormat {
    public static let firstLine = "/* [wxMaxima batch file version 1] [ DO NOT EDIT BY HAND! ]*/"
    static let createdWithPrefix = "/* [ Created with wxMaxima version "
    static let trailerComment = "/* Old versions of Maxima abort on loading files that end in a comment. */"

    enum Marker {
        static let inputStart = "/* [wxMaxima: input   start ] */"
        static let inputEnd = "/* [wxMaxima: input   end   ] */"
        static let pageBreak = "/* [wxMaxima: page break    ] */"
        static let imageStart = "/* [wxMaxima: image   start ]"
        static let imageEnd = "   [wxMaxima: image   end   ] */"
        static let answerStart = "/* [wxMaxima: answer  start ] */"
        static let answerEnd = "/* [wxMaxima: answer  end   ] */"
        static let questionStart = "/* [wxMaxima: question  start ] */"
        static let questionEnd = "/* [wxMaxima: question  end   ] */"
        static let foldStart = "/* [wxMaxima: fold    start ] */"
        static let foldEnd = "/* [wxMaxima: fold    end   ] */"
        static let hide = "/* [wxMaxima: hide output   ] */"
        static let autoAnswer = "/* [wxMaxima: autoanswer    ] */"
    }

    /// Text-like cells: (kind, marker word as in the start marker).
    static let textMarkers: [(CellKind, String)] = [
        (.title, "title  "), (.section, "section"), (.subsection, "subsect"), (.subsubsection, "subsubsect"),
        (.heading5, "heading5"), (.heading6, "heading6"), (.text, "comment"),
    ]
    static func textStart(_ word: String) -> String { "/* [wxMaxima: \(word) start ]" }
    static func textEnd(_ word: String) -> String { "   [wxMaxima: \(word) end   ] */" }
    static let captionWord = "caption"

    static let allMarkers: Set<String> = {
        var m: Set<String> = [Marker.inputStart, Marker.inputEnd, Marker.pageBreak, Marker.imageStart, Marker.imageEnd,
                              Marker.answerStart, Marker.answerEnd, Marker.questionStart, Marker.questionEnd,
                              Marker.foldStart, Marker.foldEnd, Marker.hide, Marker.autoAnswer]
        for (_, word) in textMarkers + [(.text, captionWord)] { m.insert(textStart(word)); m.insert(textEnd(word)) }
        return m
    }()

    // MARK: Writing

    /// A whole `.wxm` file.
    public static func document(_ worksheet: Worksheet, version: String = "Macsima") -> String {
        var out = firstLine + "\n" + createdWithPrefix + version + " ] */\n"
        for cell in worksheet.cells {
            let text = cells([cell])
            if !text.isEmpty { out += text + "\n\n" }
        }
        out += "\n" + trailerComment + "\n\"Created with \(version)\"$\n"
        return out
    }

    /// Cells as wxMaxima writes them, one after the other (the clipboard form).
    /// Cells `.wxm` can't hold (kept raw cells) are left out.
    public static func cells(_ cells: [Cell]) -> String {
        let sheet = Worksheet(cells: cells)
        return text(sheet, 0..<cells.count)
    }

    /// The cells in `range`; a folded heading's section goes between fold
    /// markers after it (TreeToWXM's hidden tree), nested folds included.
    static func text(_ sheet: Worksheet, _ range: Range<Int>) -> String {
        var out = ""
        var i = range.lowerBound
        while i < range.upperBound {
            let section = sheet.foldRange(of: i).clamped(to: range)
            out += cellText(sheet.cells[i])
            if sheet.cells[i].isFolded, !section.isEmpty {
                out += Marker.foldStart + "\n" + text(sheet, section) + Marker.foldEnd + "\n"
                i = section.upperBound
            } else {
                i += 1
            }
        }
        return out
    }

    static func cellText(_ cell: Cell) -> String {
        var out = ""
        for cell in [cell] {
            var text = ""
            if cell.extraAttributes["hide"] == "true" { text += Marker.hide + "\n" }
            switch cell.kind {
            case .code:
                text += Marker.inputStart + "\n" + escapeMarkers(cell.input) + "\n" + Marker.inputEnd + "\n"
                for (question, answer) in answers(of: cell) {
                    text += Marker.questionStart + "\n" + escapeText(question) + "\n" + Marker.questionEnd + "\n"
                    text += Marker.answerStart + "\n" + escapeText(answer) + "\n" + Marker.answerEnd + "\n"
                }
                if cell.extraAttributes["auto_answer"] == "yes" { text += Marker.autoAnswer + "\n" }
            case .pageBreak:
                text += Marker.pageBreak + "\n"
            case .raw, .image:
                continue
            default:
                guard let word = textMarkers.first(where: { $0.0 == cell.kind })?.1 else { continue }
                text += textStart(word) + "\n" + escapeText(cell.input) + "\n" + textEnd(word) + "\n"
            }
            out += text
        }
        return out
    }

    /// Known answers as a `.wxmx` keeps them: `questionN` and `answerN`.
    static func answers(of cell: Cell) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var n = 1
        while let q = cell.extraAttributes["question\(n)"], let a = cell.extraAttributes["answer\(n)"] {
            pairs.append((q, a))
            n += 1
        }
        return pairs
    }

    /// A line that looks like a marker gets a leading space (EscapeWXMContent).
    static func escapeMarkers(_ content: String) -> String {
        content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { allMarkers.contains(String($0)) ? " " + $0 : String($0) }.joined(separator: "\n")
    }

    /// Text inside a comment: "&" and a "/" next to a "*" as entities, so the
    /// comment can't end early (GH #1907), then marker lines escaped.
    static func escapeText(_ content: String) -> String {
        let amp = content.replacingOccurrences(of: "&", with: "&amp;")
        let chars = Array(amp)
        var out = ""
        for (i, c) in chars.enumerated() {
            if c == "/", (i > 0 && chars[i - 1] == "*") || (i + 1 < chars.count && chars[i + 1] == "*") {
                out += "&#47;"
            } else {
                out.append(c)
            }
        }
        return escapeMarkers(out)
    }

    static func unescapeText(_ content: String) -> String {
        content.replacingOccurrences(of: "&#47;", with: "/").replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Reading

    public struct ReadResult: Sendable {
        public var cells: [Cell]
        /// What was dropped or changed (images, folds).
        public var warnings: [String]
    }

    /// True when `text` holds `.wxm` cells (a file, or wxMaxima's clipboard).
    public static func looksLikeWXM(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).prefix(400).contains { line in
            let l = line.hasPrefix(" ") ? String(line.dropFirst()) : String(line)
            return l == Marker.inputStart || l == Marker.pageBreak || textMarkers.contains { l == textStart($0.1) }
        }
    }

    /// Cells from `.wxm` text. Folded cells follow their heading, which is
    /// marked folded; images are left out.
    public static func read(_ text: String) -> ReadResult {
        var warnings: Set<String> = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var i = 0
        var cells: [Cell] = []
        var hide = false
        var question: String?

        func unmarked(_ line: String) -> String {
            line.hasPrefix(" ") && allMarkers.contains(String(line.dropFirst())) ? String(line.dropFirst()) : line
        }
        /// Lines up to the end marker, joined; consumes the marker. An
        /// escaped marker (" " + marker) is content, not the end. (wxMaxima
        /// removes the space before comparing, so such a line ends its cell.)
        func until(_ end: String) -> String {
            var parts: [String] = []
            while i < lines.count {
                let raw = lines[i]
                i += 1
                if raw == end { break }
                parts.append(unmarked(raw))
            }
            return parts.joined(separator: "\n")
        }
        func append(_ cell: Cell) {
            var cell = cell
            if hide { cell.extraAttributes["hide"] = "true"; hide = false }
            cells.append(cell)
        }

        while i < lines.count {
            var line = unmarked(lines[i])
            i += 1
            // The combined "hide output + start" forms wxMaxima also reads.
            if line.hasPrefix(Marker.hide), line.count > Marker.hide.count {
                hide = true
                line = String(line.dropFirst(Marker.hide.count))
            }
            if line == Marker.hide {
                hide = true
            } else if line == Marker.inputStart {
                append(Cell(kind: .code, input: until(Marker.inputEnd)))
            } else if let (kind, word) = textMarkers.first(where: { line == textStart($0.1) }) {
                append(Cell(kind: kind, input: unescapeText(until(textEnd(word)))))
            } else if line == textStart(captionWord) {
                _ = until(textEnd(captionWord))
                warnings.insert("image cells (left out: Macsima can't show them yet)")
            } else if line == Marker.imageStart {
                if i < lines.count { i += 1 }   // the image type
                _ = until(Marker.imageEnd)
            } else if line == Marker.questionStart {
                question = unescapeText(until(Marker.questionEnd))
            } else if line == Marker.answerStart {
                let answer = unescapeText(until(Marker.answerEnd))
                if let q = question, !cells.isEmpty {
                    var n = 1
                    while cells[cells.count - 1].extraAttributes["question\(n)"] != nil { n += 1 }
                    cells[cells.count - 1].extraAttributes["question\(n)"] = q
                    cells[cells.count - 1].extraAttributes["answer\(n)"] = answer
                }
                question = nil
            } else if line == Marker.autoAnswer {
                if !cells.isEmpty { cells[cells.count - 1].extraAttributes["auto_answer"] = "yes" }
            } else if line == Marker.pageBreak {
                append(Cell(kind: .pageBreak))
            } else if line == Marker.foldStart {
                // The cells up to the matching end are the section of the
                // heading before; they stay in the list, folded under it.
                if let last = cells.indices.last, cells[last].kind.isHeading { cells[last].isFolded = true }
            } else if line == Marker.foldEnd {
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty, !cells.isEmpty,
                      [.code, .text].contains(cells[cells.count - 1].kind) || cells[cells.count - 1].kind.isHeading,
                      !line.hasPrefix(trailerComment), !line.hasPrefix("\"Created with "), line != firstLine,
                      !line.hasPrefix(createdWithPrefix) {
                // Text outside any marker joins the cell before it, as in wxMaxima.
                let last = cells.count - 1
                cells[last].input += (cells[last].input.isEmpty ? "" : "\n") + line
            }
        }
        return ReadResult(cells: cells, warnings: warnings.sorted())
    }
}
