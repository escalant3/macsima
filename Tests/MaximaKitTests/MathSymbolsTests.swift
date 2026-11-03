// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

struct MathSymbolsTests {
    @Test func wxMaximaTable() {
        #expect(MathSymbols.escCodes.count == 115)
        let codes = Dictionary(MathSymbols.escCodes.map { ($0.name, $0.glyph) }, uniquingKeysWith: { a, _ in a })
        #expect(codes["alpha"] == "α")
        #expect(codes["Omega"] == "Ω")
        #expect(codes["inf"] == "∞")
        #expect(codes["#"] == "≠")
        #expect(codes[" --> "] == "⟶")
    }

    @Test func greekKeys() {
        let small = "abcdefghijklmnopqrstuvwxyz".map { MathSymbols.greek(forKey: $0) ?? "?" }.joined()
        #expect(small == "αβχδεφγηιϕκλμνοπθρστυϖωξψζ")
        let capital = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { MathSymbols.greek(forKey: $0) ?? "?" }.joined()
        #expect(capital == "ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ")
        #expect(MathSymbols.greek(forKey: "1") == nil)
        #expect(MathSymbols.greek(forKey: "ñ") == nil)
        #expect(MathSymbols.greekKey(for: "θ") == "q")
    }

    @Test func panel() {
        let groups = MathSymbols.panelGroups
        #expect(groups.map(\.kind) == [.greekSmall, .greekCapital, .symbols])
        let glyphs = groups.flatMap(\.symbols).map(\.glyph)
        #expect(glyphs.count == Set(glyphs).count, "each glyph once")
        // Every Greek letter has a key, and every key's letter is in the panel.
        #expect(groups[0].symbols.allSatisfy { $0.key != nil } && groups[1].symbols.allSatisfy { $0.key != nil })
        for key in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            #expect(glyphs.contains(MathSymbols.greek(forKey: key)!))
        }
        // Every glyph of wxMaxima's table is in the panel, with all its names.
        for entry in MathSymbols.escCodes {
            #expect(groups.flatMap(\.symbols).contains { $0.glyph == entry.glyph && $0.names.contains(entry.name) })
        }
        let neq = groups[2].symbols.first { $0.glyph == "≠" }
        #expect(neq?.names == ["neq", "!=", "/=", "#"])
        #expect(groups[1].symbols.first { $0.glyph == "Ω" }?.names == ["Omega", "Ohm"])
        #expect(groups[0].symbols.first { $0.glyph == "ϕ" }?.names == ["varphi"])
    }

    @Test func completionNamesAreNames() {
        let names = MathSymbols.completionNames.map(\.name)
        #expect(names.contains("alpha") && names.contains("inf") && names.contains("Ohm"))
        #expect(!names.contains("<="), "operators")
        #expect(!names.contains("and") && !names.contains("in"), "keywords")
        #expect(!names.contains("^2"))
        for name in names {
            #expect(MaximaCompletion.word(in: name, caret: (name as NSString).length)?.prefix == name)
        }
    }
}
