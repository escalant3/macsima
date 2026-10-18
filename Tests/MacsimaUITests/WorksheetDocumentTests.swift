// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import MacsimaUI

@MainActor
struct WorksheetDocumentTests {
    func makeUndo() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func insertUndoRedo() {
        let doc = WorksheetDocument()
        let undo = makeUndo()
        let first = doc.worksheet.cells[0].id
        var inserted = UUID()
        step(undo) { inserted = doc.insertCell(.text, after: first, undo: undo) }
        #expect(doc.worksheet.cells.map(\.kind) == [.code, .text])
        undo.undo()
        #expect(doc.worksheet.cells.map(\.kind) == [.code])
        undo.redo()
        #expect(doc.worksheet.cells.map(\.id) == [first, inserted])
    }

    @Test func deleteUndoRestoresPositionAndContent() {
        let doc = WorksheetDocument(worksheet: Worksheet(cells: [
            Cell(kind: .title, input: "T"), Cell(kind: .code, input: "1+1;", outputs: [.text("2")]), Cell(kind: .text, input: "x"),
        ]))
        let undo = makeUndo()
        let middle = doc.worksheet.cells[1]
        step(undo) { doc.deleteCell(middle.id, undo: undo) }
        #expect(doc.worksheet.cells.map(\.input) == ["T", "x"])
        undo.undo()
        #expect(doc.worksheet.cells[1] == middle)
        undo.redo()
        #expect(doc.worksheet.cells.count == 2)
    }

    @Test func deletingTheLastCellLeavesAnEmptyCodeCell() {
        let doc = WorksheetDocument()
        doc.deleteCell(doc.worksheet.cells[0].id, undo: nil)
        #expect(doc.worksheet.cells.count == 1)
        #expect(doc.worksheet.cells[0].kind == .code)
    }

    @Test func kindChangeUndo() {
        let doc = WorksheetDocument()
        let undo = makeUndo()
        let id = doc.worksheet.cells[0].id
        step(undo) { doc.setKind(id, .section, undo: undo) }
        #expect(doc.worksheet[id]?.kind == .section)
        undo.undo()
        #expect(doc.worksheet[id]?.kind == .code)
        undo.redo()
        #expect(doc.worksheet[id]?.kind == .section)
    }

    @Test func controllerInsertsAfterTheFocusedCellAndFocusesIt() {
        let doc = WorksheetDocument()
        let controller = WorksheetController(document: doc)
        controller.focusedCell = doc.worksheet.cells[0].id
        controller.insertCell(.title)
        controller.insertCell(.text)
        #expect(doc.worksheet.cells.map(\.kind) == [.code, .title, .text])
        #expect(controller.focusedCell == doc.worksheet.cells[2].id)
        controller.deleteFocusedCell()
        #expect(doc.worksheet.cells.map(\.kind) == [.code, .title])
        #expect(controller.focusedCell == doc.worksheet.cells[1].id)
    }
}
