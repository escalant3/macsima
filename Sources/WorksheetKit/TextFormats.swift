// SPDX-License-Identifier: GPL-2.0-or-later
//
// Ported from wxMaxima's src/cells/TextFormat.cpp and TextFormat.h (commit
// 13e4aee; GH #492, after wxMaxima 26.09):
//
//  Copyright (C) 2026 Gunter Königsmann <wxMaxima@physikbuch.de>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// Character formatting in a text cell: bold, italic, underline, strike
/// through, superscript, subscript. wxMaxima stores it as attributes of a
/// `<line>`, each a list of half-open ranges of Unicode code points counted
/// from the start of the line: `<line bold="0-4,10-12" italic="6-9">`.
/// wxMaxima 26.09 and older ignore the attributes and show the text plain.
public struct TextFormat: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let bold = TextFormat(rawValue: 1)
    public static let italic = TextFormat(rawValue: 2)
    public static let underline = TextFormat(rawValue: 4)
    public static let strikethrough = TextFormat(rawValue: 8)
    /// Smaller, raised above the baseline.
    public static let raised = TextFormat(rawValue: 16)
    /// Smaller, lowered below the baseline.
    public static let lowered = TextFormat(rawValue: 32)

    /// The attribute names, in the order wxMaxima writes them.
    public static let attributeNames: [(TextFormat, String)] = [
        (.bold, "bold"), (.italic, "italic"), (.underline, "underline"),
        (.strikethrough, "strikethrough"), (.raised, "superscript"), (.lowered, "subscript"),
    ]

    /// `self` with `flag` switched on; superscript and subscript exclude each other.
    public func with(_ flag: TextFormat) -> TextFormat {
        var f = self
        if !flag.intersection([.raised, .lowered]).isEmpty { f.subtract([.raised, .lowered]) }
        return f.union(flag)
    }
}

/// One format per Unicode scalar (code point) of a cell's text; empty when
/// the text is plain.
public typealias TextFormats = [TextFormat]

public enum TextFormatting {
    public static func isPlain(_ formats: TextFormats) -> Bool { formats.allSatisfy(\.isEmpty) }

    /// The formats a `<line>`'s attributes give its text, and the attributes
    /// that are not formats (kept by the caller).
    public static func read(line text: String, attributes: [String: String])
        -> (formats: TextFormats, unknown: [String: String]) {
        let count = text.unicodeScalars.count
        var formats = TextFormats(repeating: [], count: count)
        var unknown: [String: String] = [:]
        for (name, value) in attributes {
            guard let flag = TextFormat.attributeNames.first(where: { $0.1 == name })?.0,
                  !ranges(value).isEmpty || value.isEmpty else {
                // Not a format, or one this reader can't parse: kept as it is.
                unknown[name] = value
                continue
            }
            for (start, end) in ranges(value) {
                for i in start..<min(end, count) { formats[i] = formats[i].with(flag) }
            }
        }
        return (isPlain(formats) ? [] : formats, unknown)
    }

    /// `"0-4,10-12"` → [(0, 4), (10, 12)]; malformed or empty ranges are skipped.
    static func ranges(_ value: String) -> [(Int, Int)] {
        value.split(separator: ",").compactMap { token in
            let parts = token.trimmingCharacters(in: .whitespaces).split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), b > a, a >= 0 else { return nil }
            return (a, b)
        }
    }

    /// The attributes that store `formats` for a line holding the whole text
    /// (wxMaxima's LineAttributes); empty for plain text.
    public static func attributes(_ formats: TextFormats) -> [(String, String)] {
        guard !isPlain(formats) else { return [] }
        var out: [(String, String)] = []
        for (flag, name) in TextFormat.attributeNames {
            var ranges: [String] = []
            var pos = 0
            while pos < formats.count {
                guard formats[pos].contains(flag) else { pos += 1; continue }
                var end = pos
                while end < formats.count, formats[end].contains(flag) { end += 1 }
                ranges.append("\(pos)-\(end)")
                pos = end
            }
            if !ranges.isEmpty { out.append((name, ranges.joined(separator: ","))) }
        }
        return out
    }

    /// The formats of `newText`, made from `oldText` by editing: characters
    /// that were there keep theirs, new ones take the format of what they
    /// replaced, or else of the character before them (wxMaxima's Reconcile).
    public static func reconcile(old oldText: String, _ oldFormats: TextFormats, new newText: String) -> TextFormats {
        guard !isPlain(oldFormats) else { return [] }
        let o = Array(oldText.unicodeScalars), n = Array(newText.unicodeScalars)
        var old = oldFormats
        if old.count < o.count { old += TextFormats(repeating: [], count: o.count - old.count) }
        var result = TextFormats(repeating: [], count: n.count)
        let maxCommon = min(o.count, n.count)
        var prefix = 0
        while prefix < maxCommon, o[prefix] == n[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < maxCommon - prefix, o[o.count - 1 - suffix] == n[n.count - 1 - suffix] { suffix += 1 }
        for i in 0..<prefix { result[i] = old[i] }
        for k in 0..<suffix { result[n.count - 1 - k] = old[o.count - 1 - k] }
        let oldEnd = o.count - suffix, newEnd = n.count - suffix
        let om = oldEnd - prefix, nm = newEnd - prefix
        if nm > 0 {
            if om == 0 {
                let f = inherited(n, result, prefix, following: oldEnd < o.count ? old[oldEnd] : nil)
                for i in prefix..<newEnd { result[i] = f }
            } else if om == nm {
                for i in 0..<nm { result[prefix + i] = old[prefix + i] }
            } else if om * nm <= 1_000_000 {
                diff(o, old, prefix, oldEnd, n, &result, prefix, newEnd)
            } else {
                for i in 0..<nm { result[prefix + i] = i < om ? old[prefix + i] : result[prefix + i - 1] }
            }
        }
        return isPlain(result) ? [] : result
    }

    /// The format a character inserted at `pos` gets: the one before it on
    /// its line, else the one after it.
    static func inherited(_ text: [Unicode.Scalar], _ result: TextFormats, _ pos: Int, following: TextFormat?) -> TextFormat {
        if pos > 0, text[pos - 1] != "\n" { return result[pos - 1] }
        if let following { return following }
        if pos > 0 { return result[pos - 1] }
        return []
    }

    /// A longest-common-subsequence map of the changed region.
    static func diff(_ o: [Unicode.Scalar], _ old: TextFormats, _ oldStart: Int, _ oldEnd: Int,
                     _ n: [Unicode.Scalar], _ result: inout TextFormats, _ newStart: Int, _ newEnd: Int) {
        let om = oldEnd - oldStart, nm = newEnd - newStart
        var lcs = [UInt16](repeating: 0, count: (om + 1) * (nm + 1))
        func at(_ i: Int, _ j: Int) -> UInt16 { lcs[i * (nm + 1) + j] }
        for i in stride(from: om - 1, through: 0, by: -1) {
            for j in stride(from: nm - 1, through: 0, by: -1) {
                lcs[i * (nm + 1) + j] = o[oldStart + i] == n[newStart + j] ? at(i + 1, j + 1) + 1 : max(at(i + 1, j), at(i, j + 1))
            }
        }
        var i = 0, j = 0
        var gapHasDeleted = false
        var gapFormat = TextFormat()
        while j < nm {
            if i < om, o[oldStart + i] == n[newStart + j], at(i, j) == at(i + 1, j + 1) + 1 {
                result[newStart + j] = old[oldStart + i]
                gapHasDeleted = false
                i += 1; j += 1
            } else if i < om, at(i + 1, j) >= at(i, j + 1) {
                if !gapHasDeleted { gapHasDeleted = true; gapFormat = old[oldStart + i] }
                i += 1
            } else {
                result[newStart + j] = gapHasDeleted ? gapFormat
                    : inherited(n, result, newStart + j, following: oldStart + i < old.count ? old[oldStart + i] : nil)
                j += 1
            }
        }
    }
}
