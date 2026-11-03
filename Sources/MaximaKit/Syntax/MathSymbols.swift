// SPDX-License-Identifier: GPL-2.0-or-later
//
// The Esc-sequence table is ported from wxMaxima's EscCodes()
// (src/Configuration.cpp, commit be6b76f), what Esc `alpha` Esc types there:
//
//  Copyright (C) 2004-2015 Andrej Vodopivec <andrej.vodopivec@gmail.com>
//            (C) 2016-2018 Gunter Königsmann <wxMaxima@physikbuch.de>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// Greek letters and math symbols to type: ⌃G and a letter for Greek
/// (`greek(forKey:)`), wxMaxima's Esc-sequence names as completions
/// (`completionNames`), and the Symbols panel (`panelGroups`).
public enum MathSymbols {
    public struct Entry: Hashable, Sendable {
        public var name: String
        public var glyph: String
    }

    /// wxMaxima's Esc-sequences, in its order. Some are operators (`<=`,
    /// `->`), which Macsima doesn't offer: completion only sees names.
    public static let escCodes: [Entry] = [
        Entry(name: "pm", glyph: "\u{00B1}"),
        Entry(name: "+/-", glyph: "\u{00B1}"),
        Entry(name: "alpha", glyph: "\u{03B1}"),
        Entry(name: "beta", glyph: "\u{03B2}"),
        Entry(name: "gamma", glyph: "\u{03B3}"),
        Entry(name: "delta", glyph: "\u{03B4}"),
        Entry(name: "epsilon", glyph: "\u{03B5}"),
        Entry(name: "zeta", glyph: "\u{03B6}"),
        Entry(name: "eta", glyph: "\u{03B7}"),
        Entry(name: "theta", glyph: "\u{03B8}"),
        Entry(name: "iota", glyph: "\u{03B9}"),
        Entry(name: "kappa", glyph: "\u{03BA}"),
        Entry(name: "lambda", glyph: "\u{03BB}"),
        Entry(name: "mu", glyph: "\u{03BC}"),
        Entry(name: "nu", glyph: "\u{03BD}"),
        Entry(name: "xi", glyph: "\u{03BE}"),
        Entry(name: "om", glyph: "\u{03BF}"),
        Entry(name: "omicron", glyph: "\u{03BF}"),
        Entry(name: "nabla", glyph: "\u{2207}"),
        Entry(name: "pi", glyph: "\u{03C0}"),
        Entry(name: "rho", glyph: "\u{03C1}"),
        Entry(name: "sigma", glyph: "\u{03C3}"),
        Entry(name: "tau", glyph: "\u{03C4}"),
        Entry(name: "upsilon", glyph: "\u{03C5}"),
        Entry(name: "phi", glyph: "\u{03C6}"),
        Entry(name: "chi", glyph: "\u{03C7}"),
        Entry(name: "psi", glyph: "\u{03C8}"),
        Entry(name: "omega", glyph: "\u{03C9}"),
        Entry(name: "Alpha", glyph: "\u{0391}"),
        Entry(name: "Beta", glyph: "\u{0392}"),
        Entry(name: "Gamma", glyph: "\u{0393}"),
        Entry(name: "Delta", glyph: "\u{0394}"),
        Entry(name: "Epsilon", glyph: "\u{0395}"),
        Entry(name: "Zeta", glyph: "\u{0396}"),
        Entry(name: "Eta", glyph: "\u{0397}"),
        Entry(name: "Theta", glyph: "\u{0398}"),
        Entry(name: "Iota", glyph: "\u{0399}"),
        Entry(name: "Kappa", glyph: "\u{039A}"),
        Entry(name: "Lambda", glyph: "\u{039B}"),
        Entry(name: "Mu", glyph: "\u{039C}"),
        Entry(name: "Nu", glyph: "\u{039D}"),
        Entry(name: "Xi", glyph: "\u{039E}"),
        Entry(name: "Omicron", glyph: "\u{039F}"),
        Entry(name: "Pi", glyph: "\u{03A0}"),
        Entry(name: "Rho", glyph: "\u{03A1}"),
        Entry(name: "Sigma", glyph: "\u{03A3}"),
        Entry(name: "Tau", glyph: "\u{03A4}"),
        Entry(name: "Upsilon", glyph: "\u{03A5}"),
        Entry(name: "Phi", glyph: "\u{03A6}"),
        Entry(name: "Chi", glyph: "\u{03A7}"),
        Entry(name: "Psi", glyph: "\u{03A8}"),
        Entry(name: "Omega", glyph: "\u{03A9}"),
        Entry(name: "Ohm", glyph: "\u{03A9}"),
        Entry(name: "^2", glyph: "\u{00B2}"),
        Entry(name: "^3", glyph: "\u{00B3}"),
        Entry(name: "/2", glyph: "\u{00BD}"),
        Entry(name: "sq", glyph: "\u{221A}"),
        Entry(name: "ii", glyph: "\u{2148}"),
        Entry(name: "ee", glyph: "\u{2147}"),
        Entry(name: "hb", glyph: "\u{210F}"),
        Entry(name: "in", glyph: "\u{2208}"),
        Entry(name: "impl", glyph: "\u{21D2}"),
        Entry(name: "inf", glyph: "\u{221e}"),
        Entry(name: "empty", glyph: "\u{2205}"),
        Entry(name: "TB", glyph: "\u{25b6}"),
        Entry(name: "tb", glyph: "\u{25b8}"),
        Entry(name: "and", glyph: "\u{22C0}"),
        Entry(name: "or", glyph: "\u{22C1}"),
        Entry(name: "xor", glyph: "\u{22BB}"),
        Entry(name: "nand", glyph: "\u{22BC}"),
        Entry(name: "nor", glyph: "\u{22BD}"),
        Entry(name: "implies", glyph: "\u{21D2}"),
        Entry(name: "=>", glyph: "\u{21D2}"),
        Entry(name: "<=>", glyph: "\u{21D4}"),
        Entry(name: "not", glyph: "\u{00AC}"),
        Entry(name: "union", glyph: "\u{22C3}"),
        Entry(name: "inter", glyph: "\u{22C2}"),
        Entry(name: "subseteq", glyph: "\u{2286}"),
        Entry(name: "subset", glyph: "\u{2282}"),
        Entry(name: "notsubseteq", glyph: "\u{2288}"),
        Entry(name: "notsubset", glyph: "\u{2284}"),
        Entry(name: "hbar", glyph: "\u{0127}"),
        Entry(name: "Hbar", glyph: "\u{0126}"),
        Entry(name: "partial", glyph: "\u{2202}"),
        Entry(name: "integral", glyph: "\u{222b}"),
        Entry(name: "approx", glyph: "\u{2245}"),
        Entry(name: "prop", glyph: "\u{221d}"),
        Entry(name: "propto", glyph: "\u{221d}"),
        Entry(name: "neq", glyph: "\u{2260}"),
        Entry(name: "!=", glyph: "\u{2260}"),
        Entry(name: "/=", glyph: "\u{2260}"),
        Entry(name: "#", glyph: "\u{2260}"),
        Entry(name: "<=", glyph: "\u{2264}"),
        Entry(name: "leq", glyph: "\u{2264}"),
        Entry(name: ">=", glyph: "\u{2265}"),
        Entry(name: "geq", glyph: "\u{2265}"),
        Entry(name: "ll", glyph: "\u{226A}"),
        Entry(name: "<<", glyph: "\u{226A}"),
        Entry(name: "gg", glyph: "\u{226B}"),
        Entry(name: ">>", glyph: "\u{226B}"),
        Entry(name: "qed", glyph: "\u{220E}"),
        Entry(name: "equiv", glyph: "\u{2263}"),
        Entry(name: "sum", glyph: "\u{2211}"),
        Entry(name: "prod", glyph: "\u{220F}"),
        Entry(name: "product", glyph: "\u{220F}"),
        Entry(name: "exists", glyph: "\u{2203}"),
        Entry(name: "nexists", glyph: "\u{2204}"),
        Entry(name: "parallel", glyph: "\u{2225}"),
        Entry(name: "perp", glyph: "\u{27C2}"),
        Entry(name: "perpendicular", glyph: "\u{27C2}"),
        Entry(name: "bot", glyph: "\u{27C2}"),
        Entry(name: "leadsto", glyph: "\u{219D}"),
        Entry(name: "->", glyph: "\u{2192}"),
        Entry(name: "-->", glyph: "\u{27F6}"),
        Entry(name: " --> ", glyph: "\u{27F6}"),
    ]

    /// ⌃G then a letter: the Symbol font's layout, which most math apps use
    /// (q is θ, c is χ). Shift gives the capital; J and V, whose letters have
    /// none, give ϑ and ς.
    public static func greek(forKey key: Character) -> String? { greekKeys[key] }

    private static let greekKeys: [Character: String] = {
        let lower = "abcdefghijklmnopqrstuvwxyz", upper = lower.uppercased()
        let small = Array("αβχδεφγηιϕκλμνοπθρστυϖωξψζ"), capital = Array("ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ")
        var keys: [Character: String] = [:]
        for (k, c) in zip(lower, small) { keys[k] = String(c) }
        for (k, c) in zip(upper, capital) { keys[k] = String(c) }
        return keys
    }()

    /// The key that types `glyph` after ⌃G, if one does.
    public static func greekKey(for glyph: String) -> Character? {
        greekKeys.first { $0.value == glyph }?.key
    }

    /// The entries completion offers: those whose name is a Maxima name.
    /// Operators (`<=`) and keywords (`and`, `in`) are left out, since no word
    /// is being completed there.
    public static let completionNames: [Entry] = escCodes.filter { entry in
        let tokens = MaximaTokenizer.tokenize(entry.name)
        return tokens.count == 1 && tokens[0].kind == .identifier && tokens[0].range.count == (entry.name as NSString).length
    }

    // MARK: - Panel

    /// One glyph of the Symbols panel, with every name wxMaxima has for it
    /// and its ⌃G key.
    public struct Symbol: Hashable, Sendable, Identifiable {
        public var glyph: String
        public var names: [String]
        public var key: Character?
        public var id: String { glyph }
    }

    public struct Group: Hashable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable { case greekSmall, greekCapital, symbols }
        public var kind: Kind
        public var symbols: [Symbol]
        public var id: Kind { kind }
    }

    /// Small Greek letters (the variants after ω), capitals, then wxMaxima's
    /// other symbols in its order. Each glyph shows once.
    public static let panelGroups: [Group] = {
        // The variants have no Esc-sequence; these are LaTeX's names.
        let variants = ["ς": "varsigma", "ϑ": "vartheta", "ϕ": "varphi", "ϖ": "varpi"]
        func names(_ glyph: String) -> [String] {
            let own = escCodes.filter { $0.glyph == glyph }.map(\.name)
            return own.isEmpty ? variants[glyph].map { [$0] } ?? [] : own
        }
        func symbol(_ glyph: Character) -> Symbol {
            Symbol(glyph: String(glyph), names: names(String(glyph)), key: greekKey(for: String(glyph)))
        }
        let small = Array("αβγδεζηθικλμνξοπρστυφχψως" + "ϑϕϖ").map(symbol)
        let capital = Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ").map(symbol)
        let greek = Set((small + capital).map(\.glyph))
        var others: [Symbol] = []
        for entry in escCodes where !greek.contains(entry.glyph) {
            if let i = others.firstIndex(where: { $0.glyph == entry.glyph }) {
                others[i].names.append(entry.name)
            } else {
                others.append(Symbol(glyph: entry.glyph, names: [entry.name], key: nil))
            }
        }
        return [Group(kind: .greekSmall, symbols: small), Group(kind: .greekCapital, symbols: capital),
                Group(kind: .symbols, symbols: others)]
    }()
}
