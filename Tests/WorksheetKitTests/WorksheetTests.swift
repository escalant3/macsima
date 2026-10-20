// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import WorksheetKit

struct WorksheetTests {
    @Test func activeCell() throws {
        var section = Cell(kind: .section, input: "S")
        section.isFolded = true
        var w = Worksheet(cells: [Cell(kind: .code, input: "a"), section, Cell(kind: .code, input: "hidden"),
                                  Cell(kind: .section, input: "T"), Cell(kind: .code, input: "b")])
        #expect(w.activeCell == nil)
        // Top-level: a, S (with its folded section), T, b.
        w.extraAttributes["activecell"] = "2"
        #expect(w.activeCell == w.cells[3].id, "the folded cell doesn't count")
        w.extraAttributes["activecell"] = "99"
        #expect(w.activeCell == w.cells[4].id, "past the end: the last cell")
        w.extraAttributes["activecell"] = "-1"
        #expect(w.activeCell == nil)
        w.setActiveCell(w.cells[4].id)
        #expect(w.extraAttributes["activecell"] == "3")
        w.setActiveCell(w.cells[2].id)
        #expect(w.extraAttributes["activecell"] == "3", "a cell inside a fold has no position; unchanged")
        // wxMaxima's sample: four cells, activecell="4", the cursor after the last.
        let sample = try WXMXReader.read(try Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Fixtures/wxmx/wxmaxima-samples/intervals.wxmx"))).worksheet
        #expect(sample.cells.count == 4 && sample.activeCell == sample.cells[3].id)
    }

    @Test func watchedVariables() throws {
        var w = Worksheet.empty()
        #expect(w.watchedVariables.isEmpty)
        w.watchedVariables = ["x", "", "f"]
        // As wxMaxima writes it (WXMXformat.cpp): the count, the names, one empty extra.
        #expect(w.extraAttributes == ["variables_num": "2", "variables_0": "x", "variables_1": "f", "variables_2": ""])
        #expect(w.watchedVariables == ["x", "f"])
        let xml = WXMXWriter.contentXML(w)
        #expect(xml.contains("variables_0=\"x\" variables_1=\"f\" variables_2=\"\" variables_num=\"2\""))
        let back = try WXMXReader.read(try WXMXWriter.write(w)).worksheet
        #expect(back.watchedVariables == ["x", "f"])
        w.watchedVariables = []
        #expect(w.extraAttributes.isEmpty)
        // An untrusted count is capped.
        w.extraAttributes = ["variables_num": "999999999", "variables_0": "a"]
        #expect(w.watchedVariables == ["a"])
    }

    @Test func emptyHasOneCodeCell() {
        let w = Worksheet.empty()
        #expect(w.cells.count == 1)
        #expect(w.cells[0].kind == .code)
    }

    @Test func insertRemoveMove() {
        var w = Worksheet()
        let a = Cell(kind: .title, input: "A")
        let b = Cell(kind: .code, input: "1+1;")
        let c = Cell(kind: .text, input: "C")
        w.insert(a, after: nil)
        w.insert(c, after: a.id)
        w.insert(b, after: a.id)
        #expect(w.cells.map(\.input) == ["A", "1+1;", "C"])
        w.move(c.id, to: 0)
        #expect(w.cells.map(\.input) == ["C", "A", "1+1;"])
        let removed = w.remove(a.id)
        #expect(removed?.index == 1)
        #expect(w.cells.map(\.input) == ["C", "1+1;"])
        #expect(w.remove(a.id) == nil)
        w.insert(a, at: 99)
        #expect(w.cells.last?.id == a.id)
    }

    @Test func editsAndOutputs() {
        var w = Worksheet.empty()
        let id = w.cells[0].id
        w.setInput(id, "x^2;")
        w.update(id) {
            $0.outputs = [.math(xml: "<math><mn>1</mn></math>"), .error(kind: "maxima", message: "")]
            $0.inputLabel = 3
        }
        #expect(w[id]?.input == "x^2;")
        #expect(w[id]?.outputs.count == 2)
        w.clearOutputs(id)
        #expect(w[id]?.outputs.isEmpty == true)
        #expect(w[id]?.inputLabel == nil)
        w.setKind(id, .text)
        #expect(w.codeCells.isEmpty)
    }

    @Test func headingKinds() {
        #expect(CellKind.title.isHeading && CellKind.heading6.isHeading)
        #expect(!CellKind.code.isHeading && !CellKind.text.isHeading)
    }
}
