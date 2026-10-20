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

    @Test func imageCells() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        var image = Cell(kind: .image, input: "A */ caption")
        image.outputs = [.image(data: png, format: "png", label: nil)]
        let sheet = Worksheet(cells: [Cell(kind: .code, input: "x;"), image])
        let text = WXMFormat.document(sheet)
        // As TreeToWXM writes it: the caption's markers, then type and base64.
        #expect(text.contains("/* [wxMaxima: caption start ]\nA *&#47; caption\n   [wxMaxima: caption end   ] */\n"
            + "/* [wxMaxima: image   start ]\npng\n\(png.base64EncodedString())\n   [wxMaxima: image   end   ] */\n"))
        let back = WXMFormat.read(text)
        #expect(back.warnings.isEmpty)
        #expect(back.cells.map(\.kind) == [.code, .image])
        #expect(back.cells[1].input == "A */ caption")
        #expect(back.cells[1].outputs == [.image(data: png, format: "png", label: nil)])
    }

    @Test func badImageIsLeftOut() {
        let text = "/* [wxMaxima: caption start ]\nc\n   [wxMaxima: caption end   ] */\n"
            + "/* [wxMaxima: image   start ]\npng\n!!not base64!!\n   [wxMaxima: image   end   ] */\n"
        let r = WXMFormat.read(text)
        #expect(r.cells.count == 1 && r.cells[0].outputs.isEmpty)
        #expect(r.warnings == ["an image Macsima could not read (left out)"])
    }

    @Test func macExport() {
        var folded = Cell(kind: .section, input: "Part")
        folded.isFolded = true
        let sheet = Worksheet(cells: [
            Cell(kind: .title, input: "Notes & more"),
            Cell(kind: .text, input: "Plain prose."),
            Cell(kind: .text, input: "ends */ early"),
            Cell(kind: .code, input: "f(x) := x^2;\nf(3);"),
            folded,
            Cell(kind: .code, input: "inside: 1$"),
            Cell(kind: .pageBreak),
        ])
        #expect(WXMFormat.mac(sheet) == """
            /* [wxMaxima: title   start ]
            Notes &amp; more
               [wxMaxima: title   end   ] */

            /* Plain prose. */

            /* ends *&#47; early */

            f(x) := x^2;
            f(3);

            /* [wxMaxima: section start ]
            Part
               [wxMaxima: section end   ] */

            inside: 1$

            /* [wxMaxima: page break    ] */



            """)
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
