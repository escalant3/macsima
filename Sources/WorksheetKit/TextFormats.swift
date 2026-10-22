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
    }}
