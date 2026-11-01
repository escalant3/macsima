// SPDX-License-Identifier: GPL-2.0-or-later

import CoreGraphics
import Foundation
import MaximaKit
import Testing
@testable import WXMLKit

struct MathSelectionTests {
    /// A layout with the given rectangles for numbered nodes.
    func layout(_ xml: String, _ rects: [Int: CGRect]) throws -> MathLayout {
        let tree = try #require(MathMLTranslator.translate(xml).tree)
        return MathLayout(tree: tree, measured: rects.mapValues { [$0] })
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 1, height: 1) }
    func drag(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: min(x0, x1), y: min(y0, y1), width: max(abs(x1 - x0), 1), height: max(abs(y1 - y0), 1))
    }

    func input(_ layout: MathLayout, _ selection: MathSelection?) -> String? {
        selection.map { MaximaInputText.of(layout.node(of: $0)) }
    }

    @Test func taggedMathMLIsTheMathMLWithNumbers() throws {
        let chunks = try MathFixtures.chunks("31-display-forms")
        #expect(chunks.count > 45)
        for (i, xml) in chunks.enumerated() {
            let out = MathMLTranslator.translate(xml)
            #expect(MathMLTranslator.untagged(out.taggedMathML) == out.mathML, "chunk \(i)")
            let tree = try #require(out.tree, "chunk \(i)")
            let numbers = out.taggedMathML.matches(of: #/data-p="(\d+)"/#).compactMap { Int($0.output.1) }
            #expect(Set(numbers).count == numbers.count, "chunk \(i): a number used twice")
            #expect(numbers.allSatisfy { tree.nodes.indices.contains($0) }, "chunk \(i)")
        }
    }

    @Test func treeNumbersFollowTheDocument() throws {
        let tree = try #require(MathMLTranslator.translate("<math><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow></math>").tree)
        #expect(tree.rootID == 0)
        #expect(tree.nodes.map(\.name) == ["math", "mrow", "mi", "mo", "mn"])
        #expect(tree.children[1] == [2, 3, 4])
        #expect(tree.parent[4] == 1)
        // Several top-level nodes: the wrapper row is numbered last.
        let wrapped = try #require(MathMLTranslator.translate("<mi>a</mi><mi>b</mi>").tree)
        #expect(wrapped.rootID == 2)
        #expect(wrapped.children[2] == [0, 1])
    }

    /// x + 2 + 1, each piece 10 points wide.
    let sum = "<math><mrow><mi>x</mi><mo>+</mo><mn>2</mn><mo>+</mo><mn>1</mn></mrow></math>"
    var sumRects: [Int: CGRect] {
        Dictionary(uniqueKeysWithValues: (2...6).map { ($0, CGRect(x: CGFloat($0 - 2) * 10, y: 0, width: 10, height: 20)) })
    }

    @Test func aClickSelectsTheSmallestPart() throws {
        let l = try layout(sum, sumRects)
        #expect(l.select(point(25, 10)) == .node(4))
        #expect(l.select(point(15, 10)) == .node(3))
        #expect(l.select(point(80, 10)) == nil)
    }

    @Test func aDragSelectsTheRunOfChildrenItTouches() throws {
        let l = try layout(sum, sumRects)
        let all = l.select(drag(5, 10, 45, 10))
        #expect(all == .run(parent: 1, first: 2, last: 6))
        #expect(input(l, all) == "x+2+1")
        // Started on the 2, ended on the second +: wxMaxima copies "2+" too.
        #expect(input(l, l.select(drag(25, 10, 35, 12))) == "2+")
        #expect(l.rects(of: try #require(all)) == [CGRect(x: 0, y: 0, width: 50, height: 20)])
    }

    @Test func enclosingGrowsToTheNextLargerPart() throws {
        let l = try layout(sum, sumRects)
        #expect(l.enclosing(.node(4)) == .node(1))
        #expect(l.enclosing(.run(parent: 1, first: 2, last: 4)) == .node(1))
        // The math element is the same size as its row: nothing larger.
        #expect(l.enclosing(.node(1)) == nil)
    }

    /// (x+1)/2: numerator row over the denominator, no rectangle for the bar.
    @Test func insideAFractionAndOverItsBar() throws {
        let xml = "<math><mfrac><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow><mn>2</mn></mfrac></math>"
        // math 0, mfrac 1, mrow 2, mi 3, mo 4, mn 5, mn 6.
        let l = try layout(xml, [3: CGRect(x: 0, y: 0, width: 10, height: 10), 4: CGRect(x: 10, y: 0, width: 10, height: 10),
                                 5: CGRect(x: 20, y: 0, width: 10, height: 10), 6: CGRect(x: 10, y: 14, width: 10, height: 10),
                                 1: CGRect(x: 0, y: 0, width: 30, height: 24)])
        #expect(input(l, l.select(drag(5, 5, 25, 5))) == "x+1")
        // From the numerator over the bar (y 10 to 14) and no further: the fraction.
        #expect(l.select(drag(5, 5, 5, 12)) == .node(1))
        #expect(input(l, l.select(drag(5, 5, 15, 20))) == "(x+1)/2")
    }

    /// matrix([1,2],[3,4]).
    let matrix = "<math><tb bracketParens=\"true\"><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr>"
        + "<mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></tb></math>"
    // math 0, tb 1, mtr 2, mtd 3, mn 4, mtd 5, mn 6, mtr 7, mtd 8, mn 9, mtd 10, mn 11.
    var matrixRects: [Int: CGRect] {
        [4: CGRect(x: 0, y: 0, width: 10, height: 10), 6: CGRect(x: 20, y: 0, width: 10, height: 10),
         9: CGRect(x: 0, y: 20, width: 10, height: 10), 11: CGRect(x: 20, y: 20, width: 10, height: 10)]
    }

    @Test func aDragOverMatrixEntriesSelectsABlock() throws {
        let l = try layout(matrix, matrixRects)
        let row = l.select(drag(5, 5, 25, 5))
        #expect(row == .block(table: 1, rows: 0...0, columns: 0...1))
        #expect(input(l, row) == "matrix([1,2])")
        let column = l.select(drag(25, 5, 25, 25))
        #expect(column == .block(table: 1, rows: 0...1, columns: 1...1))
        #expect(input(l, column) == "matrix([2],[4])")
        // One entry is that entry's math.
        #expect(input(l, l.select(point(5, 5))) == "1")
    }

    @Test func aBlockGrowsToTheMatrix() throws {
        let l = try layout(matrix, matrixRects)
        #expect(l.enclosing(.block(table: 1, rows: 0...0, columns: 0...0)) == .node(1))
    }

    @Test func eachSelectionCopiesAsLaTeXAndMathML() throws {
        let l = try layout(sum, sumRects)
        let node = l.node(of: .run(parent: 1, first: 4, last: 6))
        #expect(LaTeXTranslator.translate(node: node) == "2 + 1")
        #expect(MathMLTranslator.mathML(of: node) == "<math display=\"block\"><mrow><mn>2</mn><mo>+</mo><mn>1</mn></mrow></math>")
    }
}
