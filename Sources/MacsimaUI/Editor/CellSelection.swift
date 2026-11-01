// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WorksheetKit

/// Takes the keyboard while whole cells are selected: Copy, Cut, Paste,
/// Delete and Select All from the Edit menu (they go to the first
/// responder), Shift+Up/Down to grow or shrink the selection, Up, Down and
/// Escape to go back to editing. Also while part of a math output is
/// selected: Copy, Escape, Return and the arrow keys
/// (MathOutputSelection.swift). An empty view in the window, first
/// responder only while cells or math are selected.
final class CellSelectionResponder: NSView, NSMenuItemValidation {
    weak var controller: WorksheetController?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if controller.mathSelection != nil {
            let shift = event.modifierFlags.contains(.shift)
            let other = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            if other || !controller.handleOutputKey(keyCode: event.keyCode, shift: shift) { super.keyDown(with: event) }
            return
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 126: shift ? controller.extendCellSelection(up: true) : controller.endCellSelection(at: .first)
        case 125: shift ? controller.extendCellSelection(up: false) : controller.endCellSelection(at: .last)
        case 53: controller.endCellSelection(at: .anchor)
        case 51, 117: controller.deleteSelectedCells()
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        if controller?.mathSelection != nil { controller?.copyMathSelection(as: .input) } else { controller?.copySelectedCells() }
    }
    @objc func cut(_ sender: Any?) { controller?.cutSelectedCells() }
    @objc func paste(_ sender: Any?) { controller?.pasteCells() }
    @objc func delete(_ sender: Any?) { controller?.deleteSelectedCells() }
    override func selectAll(_ sender: Any?) { controller?.selectAllCells() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)): CellClipboard.hasCells
        case #selector(copy(_:)): !(controller?.selectedCells.isEmpty ?? true) || controller?.mathSelection != nil
        case #selector(cut(_:)), #selector(delete(_:)): !(controller?.selectedCells.isEmpty ?? true)
        default: true
        }
    }
}

extension WorksheetController {
    enum SelectionEnd { case first, last, anchor }

    /// The selected cells in document order.
    var selectedCellsInOrder: [Cell] {
        document.worksheet.cells.filter { selectedCells.contains($0.id) }
    }

    /// A click on a cell's bar: selects it, or with Shift the cells from
    /// the anchor to it.
    func clickBar(_ id: UUID, extend: Bool) {
        if extend, let anchor = selectionAnchor ?? focusedCell {
            selectCells(from: anchor, to: id)
        } else {
            selectCells(from: id, to: id)
        }
    }

    /// Selects the cells between `anchor` and `head`, both included.
    func selectCells(from anchor: UUID, to head: UUID) {
        let cells = document.worksheet.cells
        guard let a = cells.firstIndex(where: { $0.id == anchor }),
              let h = cells.firstIndex(where: { $0.id == head }) else { return }
        clearMathSelection()
        selectionAnchor = anchor
        selectionHead = head
        selectedCells = cells[min(a, h)...max(a, h)].map(\.id)
        if let window, let responder = selectionResponder, window.firstResponder !== responder {
            window.makeFirstResponder(responder)
        }
    }

    func selectAllCells() {
        guard let first = document.worksheet.cells.first, let last = document.worksheet.cells.last else { return }
        selectCells(from: first.id, to: last.id)
    }

    /// Shift+Up or Down: moves the selection's moving end one cell.
    func extendCellSelection(up: Bool) {
        let cells = document.worksheet.cells
        guard let anchor = selectionAnchor, let head = selectionHead,
              let h = cells.firstIndex(where: { $0.id == head }) else { return }
        let next = up ? h - 1 : h + 1
        guard cells.indices.contains(next) else { return }
        selectCells(from: anchor, to: cells[next].id)
    }

    /// Shift+Up from the start of a cell (or Shift+Down from its end):
    /// selects that cell and the next one in that direction.
    func startCellSelection(from id: UUID, up: Bool) {
        selectCells(from: id, to: id)
        extendCellSelection(up: up)
    }

    /// Back to editing, in the first, last or anchor cell of the selection.
    func endCellSelection(at end: SelectionEnd) {
        let cells = selectedCellsInOrder
        let target: Cell? = switch end {
        case .first: cells.first
        case .last: cells.last
        case .anchor: cells.first { $0.id == selectionAnchor }
        }
        clearCellSelection()
        if let target, target.hasEditor {
            focus(target.id, caret: end == .last ? .end : .start)
        } else if let target {
            focusedCell = target.id
        }
    }

    func clearCellSelection() {
        guard !selectedCells.isEmpty else { return }
        selectedCells = []
        selectionAnchor = nil
        selectionHead = nil
    }

    func copySelectedCells() {
        let cells = selectedCellsInOrder
        if !cells.isEmpty { CellClipboard.write(cells) }
    }

    func cutSelectedCells() {
        copySelectedCells()
        deleteSelectedCells(name: String(localized: "Cut", comment: "Undo action name"))
    }

    func deleteSelectedCells(name: String = String(localized: "Delete Cells", comment: "Undo action name")) {
        let ids = selectedCellsInOrder.map(\.id)
        guard !ids.isEmpty, let first = document.worksheet.index(of: ids[0]) else { return }
        clearCellSelection()
        document.deleteCells(ids, undo: undoManager, name: name)
        let cells = document.worksheet.cells
        let next = cells[min(first, cells.count - 1)]
        if next.hasEditor { focus(next.id, caret: .start) } else { focusedCell = next.id }
    }

    /// Pastes cells after the selection, or after the focused cell, and
    /// selects them. False when the pasteboard holds no cells.
    @discardableResult
    func pasteCells(after id: UUID? = nil) -> Bool {
        guard let cells = CellClipboard.read() else { return false }
        let after = id ?? selectedCellsInOrder.last?.id ?? focusedCell
        let index = after.flatMap { document.worksheet.index(of: $0) }.map { $0 + 1 } ?? document.worksheet.cells.count
        document.insertCells(cells, at: index, undo: undoManager)
        selectCells(from: cells[0].id, to: cells[cells.count - 1].id)
        return true
    }
}
