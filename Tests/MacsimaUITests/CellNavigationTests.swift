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
