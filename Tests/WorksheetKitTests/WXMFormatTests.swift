// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import WorksheetKit

struct WXMFormatTests {
    static let dir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/wxm")

    func read(_ name: String) throws -> WXMFormat.ReadResult {
        WXMFormat.read(try String(contentsOf: Self.dir.appending(path: name), encoding: .utf8))
    }

    func counts(_ cells: [Cell]) -> [CellKind: Int] {
        cells.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    @Test func textCells() throws {
        let r = try read("textcells.wxm")
        #expect(counts(r.cells) == [.text: 10, .title: 1, .section: 1, .subsection: 1, .subsubsection: 1,
                                    .heading5: 1, .heading6: 1, .pageBreak: 1])
        #expect(r.warnings.isEmpty)
    }

    @Test func everyCellKindWithAnswers() throws {
        let r = try read("testbench_simple.wxm")
        #expect(counts(r.cells) == [.code: 149, .text: 49, .title: 1, .section: 6, .subsection: 49,
                                    .subsubsection: 21, .heading5: 1, .heading6: 1, .pageBreak: 1])
        let answered = r.cells.filter { $0.extraAttributes["question1"] != nil }
        #expect(answered.count == 2 && answered.allSatisfy { $0.extraAttributes["answer1"] != nil })
        #expect(r.cells.filter { $0.extraAttributes["auto_answer"] == "yes" }.count == 2)
    }

    /// Writing what was read and reading it again gives the same cells.
    @Test(arguments: ["textcells.wxm", "testbench_simple.wxm", "diffEquations.wxm", "solvingEquations.wxm"])
    func roundTrip(_ name: String) throws {
        let first = try read(name).cells
        let written = WXMFormat.document(Worksheet(cells: first))
        #expect(written.hasPrefix(WXMFormat.firstLine))
        let second = WXMFormat.read(written).cells
        #expect(second.map(\.kind) == first.map(\.kind))
        #expect(second.map(\.input) == first.map(\.input))
        #expect(second.map(\.extraAttributes) == first.map(\.extraAttributes))
    }

    /// Folded sections go between fold markers, nested ones too, and come back folded.
    @Test func foldedSections() {
        let cells = [Cell(kind: .section, input: "S", isFolded: true), Cell(kind: .code, input: "a;"),
                     Cell(kind: .subsection, input: "T", isFolded: true), Cell(kind: .code, input: "b;"),
                     Cell(kind: .section, input: "U"), Cell(kind: .code, input: "c;")]
        let text = WXMFormat.cells(cells)
        #expect(text.components(separatedBy: "/* [wxMaxima: fold    start ] */").count == 3)
        let back = WXMFormat.read(text).cells
        #expect(back.map(\.input) == cells.map(\.input))
        #expect(back.map(\.isFolded) == cells.map(\.isFolded))
    }

    @Test func textThatWouldEndTheComment() {
        let cells = [Cell(kind: .text, input: "a */ x:2$ /* b & c"),
                     Cell(kind: .code, input: "f(x) := x;\n/* [wxMaxima: input   end   ] */\ny;"),
                     Cell(kind: .code, input: "z;", extraAttributes: ["hide": "true"])]
        let text = WXMFormat.cells(cells)
        #expect(text.contains("a *&#47; x:2$ &#47;* b &amp; c"))
        #expect(text.contains("\n /* [wxMaxima: input   end   ] */\n"))
        let back = WXMFormat.read(text).cells
        #expect(back.map(\.input) == cells.map(\.input))
        #expect(back[2].extraAttributes["hide"] == "true")
        #expect(WXMFormat.looksLikeWXM(text) && !WXMFormat.looksLikeWXM("x+1;"))
    }
}
