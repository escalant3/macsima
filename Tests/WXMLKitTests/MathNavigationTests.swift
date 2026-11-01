// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import WXMLKit

struct MathNavigationTests {
    func navigation(_ xml: String) throws -> MathNavigation {
        try #require(MathNavigation(MathMLTranslator.translate(xml)))
    }

    func text(_ nav: MathNavigation, _ selection: MathSelection) -> String {
        MaximaInputText.of(nav.tree.node(of: selection))
    }

    func texts(_ nav: MathNavigation, _ selections: [MathSelection]) -> [String] {
        selections.map { text(nav, $0) }
    }

    // e + d + c, as the glue prints it, with its label.
    let sum = #"<math><lbl altCopy="%o1">(%o1) </lbl><mi>e</mi><mo>+</mo><mi>d</mi><mo>+</mo><mi>c</mi></math>"#

    @Test func returnGoesIntoTheTermsAndEscapeBackOut() throws {
        let nav = try navigation(sum)
        let terms = nav.children(of: nav.whole)
        #expect(texts(nav, terms) == ["e", "+", "d", "+", "c"])
        #expect(nav.children(of: terms[0]).isEmpty)
        #expect(nav.parent(of: terms[2]) == nav.whole)
        #expect(nav.parent(of: nav.whole) == nil)
    }

    @Test func leftAndRightStopAtTheEnds() throws {
        let nav = try navigation(sum)
        let terms = nav.children(of: nav.whole)
        #expect(nav.neighbour(of: terms[0], right: true) == terms[1])
        #expect(nav.neighbour(of: terms[0], right: false) == terms[0])
        #expect(nav.neighbour(of: terms[4], right: true) == terms[4])
    }

    @Test func shiftGrowsARunAndShrinksItBack() throws {
        let nav = try navigation(sum)
        let terms = nav.children(of: nav.whole)
        var s = nav.extend(terms[2], anchor: terms[2], right: true)
        #expect(text(nav, s) == "d+")
        s = nav.extend(s, anchor: terms[2], right: true)
        #expect(text(nav, s) == "d+c")
        s = nav.extend(s, anchor: terms[2], right: false)
        #expect(text(nav, s) == "d+")
        // A run's neighbours are beyond its ends; Escape leaves it.
        #expect(nav.neighbour(of: s, right: false) == terms[1])
        #expect(nav.parent(of: s) == nav.whole)
    }

    /// (x+1)/2 alone: the whole output is the fraction, so Return goes on
    /// into the numerator and denominator, and one Escape gets back.
    let fraction = "<math><mfrac><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow><mn>2</mn></mfrac></math>"

    @Test func aWholeOutputThatIsOneFraction() throws {
        let nav = try navigation(fraction)
        let parts = nav.children(of: nav.whole)
        #expect(texts(nav, parts) == ["x+1", "2"])
        #expect(texts(nav, nav.children(of: parts[0])) == ["x", "+", "1"])
        #expect(nav.parent(of: parts[0]) == nav.whole)
        // Numerator and denominator are neighbours, but no run spans both.
        #expect(nav.neighbour(of: parts[0], right: true) == parts[1])
        #expect(nav.extend(parts[0], anchor: parts[0], right: true) == parts[0])
    }

    /// matrix([1/2, x], [3, 4]).
    let matrix = "<math><tb bracketParens=\"true\"><mtr><mtd><mfrac><mn>1</mn><mn>2</mn></mfrac></mtd><mtd><mi>x</mi></mtd></mtr>"
        + "<mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></tb></math>"

    @Test func aMatrixIsWalkedEntryByEntry() throws {
        let nav = try navigation(matrix)
        let entries = nav.children(of: nav.whole)
        #expect(texts(nav, entries) == ["1/2", "x", "3", "4"])
        let first = entries[0]
        #expect(nav.isEntry(first))
        #expect(texts(nav, [try #require(nav.step(first, rows: 0, columns: 1))]) == ["x"])
        #expect(texts(nav, [try #require(nav.step(first, rows: 1, columns: 0))]) == ["3"])
        // At the edge the entry stays.
        #expect(nav.step(first, rows: -1, columns: 0) == first)
        // Shift: a block from the anchor.
        let block = try #require(nav.step(first, rows: 1, columns: 1, anchor: (0, 0)))
        #expect(text(nav, block) == "matrix([1/2,x],[3,4])")
        let column = try #require(nav.step(block, rows: 0, columns: -1, anchor: (0, 0)))
        #expect(text(nav, column) == "matrix([1/2],[3])")
        #expect(nav.parent(of: first) == nav.whole)
    }

    @Test func anEntryHoldingAFractionOpensTheFraction() throws {
        let nav = try navigation(matrix)
        let first = nav.children(of: nav.whole)[0]
        let parts = nav.children(of: first)
        #expect(texts(nav, parts) == ["1", "2"])
        #expect(nav.parent(of: parts[0]) == first)
        // A leaf entry has nothing inside.
        #expect(nav.children(of: nav.children(of: nav.whole)[1]).isEmpty)
    }

    @Test func aMouseSelectionOfAMatrixCellIsItsEntry() throws {
        let nav = try navigation(matrix)
        // The node of the second row's first cell.
        let cell = try #require(nav.tree.nodes.indices.first { nav.tree.nodes[$0].name == "mtd" && text(nav, .node($0)) == "3" })
        #expect(nav.parent(of: .node(cell)) == nav.whole)
        #expect(texts(nav, [nav.neighbour(of: .node(cell), right: true)]) == ["4"])
    }

    /// Every part of every display form: Escape from each part of a level
    /// gets back to that level's parent, so Return and Escape agree.
    @Test func returnAndEscapeAgreeOnTheFixtures() throws {
        let chunks = try MathFixtures.chunks("31-display-forms")
        var visited = 0
        for (i, xml) in chunks.enumerated() {
            guard let nav = MathNavigation(MathMLTranslator.translate(xml)) else { continue }
            var queue = [nav.whole]
            while let s = queue.popLast(), visited < 20_000 {
                for child in nav.children(of: s) {
                    #expect(nav.parent(of: child) == s, "chunk \(i): \(text(nav, child)) in \(text(nav, s))")
                    #expect(child != s, "chunk \(i): Return selects the same")
                    queue.append(child)
                    visited += 1
                }
            }
        }
        #expect(visited > 300)
    }
}
