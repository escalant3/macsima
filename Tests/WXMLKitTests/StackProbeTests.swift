// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
import WorksheetKit
@testable import WXMLKit

/// Deeply nested input must not crash: the parsers refuse more than 512
/// levels, and the translator renders more than 400 levels as text.
@MainActor
struct DeepNestingTests {
    func nested(_ depth: Int) -> String {
        String(repeating: "<r>", count: depth) + "x" + String(repeating: "</r>", count: depth)
    }

    @Test func parsersRefuseExtremeNesting() {
        #expect(MathXMLParser.parse(nested(500)) != nil)
        #expect(MathXMLParser.parse(nested(100_000)) == nil)
        #expect((try? XMLTree.parseFragment(nested(500))) != nil)
        #expect(throws: XMLTreeError.self) { try XMLTree.parseFragment(nested(100_000)) }
    }

    @Test func translatorCapsDepth() {
        let out = MathMLTranslator.translate("<math>" + nested(510) + "</math>")
        #expect(out.wellFormed)
        #expect(out.mathML.contains("<mtext>x</mtext>"))
    }
}
