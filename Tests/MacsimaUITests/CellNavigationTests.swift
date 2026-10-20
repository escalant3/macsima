// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import MacsimaUI

@MainActor
struct CellNavigationTests {
    @Test func upAndDownSkipCellsWithoutEditors() {
        let cells = [Cell(kind: .code, input: "a"), Cell(kind: .pageBreak), Cell(kind: .raw), Cell(kind: .text, input: "b")]
        let controller = WorksheetController(document: WorksheetDocument(worksheet: Worksheet(cells: cells)))
        controller.focusedCell = cells[3].id

        #expect(controller.leave(cells[3].id, up: true, x: 12))
        #expect(controller.focusedCell == cells[0].id)
        #expect(controller.caretRequest?.place == .lastLine(x: 12))

        #expect(controller.leave(cells[0].id, up: false, x: 5))
        #expect(controller.focusedCell == cells[3].id)
        #expect(controller.caretRequest?.place == .firstLine(x: 5))

        // Nothing above the first cell or below the last.
        #expect(!controller.leave(cells[0].id, up: true, x: 0))
        #expect(!controller.leave(cells[3].id, up: false, x: 0))
        #expect(controller.focusedCell == cells[3].id)
    }

    @Test func goToError() {
        var a = Cell(kind: .code, input: "1/0;")
        a.outputs = [.error(kind: "maxima", message: "expt: undefined")]
        var b = Cell(kind: .code, input: "x;")
        b.outputs = [.error(kind: "interrupted", message: "Interrupted")]
        var c = Cell(kind: .code, input: "f(a,,b);")
        c.outputs = [.error(kind: "syntax", message: "incorrect syntax")]
        let cells = [a, Cell(kind: .text, input: "t"), b, c]
        let controller = WorksheetController(document: WorksheetDocument(worksheet: Worksheet(cells: cells)))
        controller.focusedCell = cells[1].id
        #expect(controller.goToError())
        #expect(controller.focusedCell == c.id, "the next error after the focus; an interrupt is none")
        #expect(controller.goToError())
        #expect(controller.focusedCell == a.id, "round the worksheet")
        #expect(controller.goToError(forward: false))
        #expect(controller.focusedCell == c.id, "backwards, round again")
        let clean = WorksheetController(document: WorksheetDocument(worksheet: Worksheet(cells: [Cell(kind: .code)])))
        #expect(!clean.goToError())
    }

    @Test func activeCellRestoresAndSaves() throws {
        var w = Worksheet(cells: [Cell(kind: .code, input: "a"), Cell(kind: .pageBreak), Cell(kind: .code, input: "b")])
        w.extraAttributes["activecell"] = "1"
        let document = WorksheetDocument(worksheet: w)
        let controller = WorksheetController(document: document)
        #expect(controller.initialFocus() == w.cells[2].id, "the page break has no editor: the next cell that has")
        controller.focusedCell = w.cells[0].id
        #expect(try document.snapshot(contentType: .wxmx).extraAttributes["activecell"] == "0", "saved where the focus is")
        #expect(document.worksheet.extraAttributes["activecell"] == "1", "the live model is untouched")
    }

    @Test func caretRequestsAreNumbered() {
        let cells = [Cell(kind: .code)]
        let controller = WorksheetController(document: WorksheetDocument(worksheet: Worksheet(cells: cells)))
        controller.focus(cells[0].id, caret: .start)
        let first = controller.caretRequest?.serial
        let request = controller.focusRequest
        controller.focus(cells[0].id, caret: .start)
        #expect(controller.caretRequest?.serial != first)
        #expect(controller.focusRequest != request, "focusing the focused cell again still asks for the focus")
    }
}
