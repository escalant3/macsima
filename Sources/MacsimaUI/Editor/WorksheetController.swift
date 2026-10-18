// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WorksheetKit

/// Per-window state and actions: which cell has focus, and (from step 5)
/// the Maxima session that evaluates the worksheet.
@MainActor
@Observable
public final class WorksheetController {
    public let document: WorksheetDocument
    public var focusedCell: UUID?
    public var undoManager: UndoManager?

    public init(document: WorksheetDocument) {
        self.document = document
    }

    /// Controllers of open windows, most recently focused last.
    private static var live: [WeakController] = []
    private struct WeakController { weak var controller: WorksheetController? }

    /// Records this controller as the one of the key window.
    func becameKey() {
        Self.live.removeAll { $0.controller == nil || $0.controller === self }
        Self.live.append(WeakController(controller: self))
    }

    /// The controller of the window used last.
    static var keyController: WorksheetController? { live.last(where: { $0.controller != nil })?.controller }

    /// Every open window's controller.
    static var all: [WorksheetController] { live.compactMap(\.controller) }

    // MARK: - Cells

    public func insertCell(_ kind: CellKind) {
        let id = document.insertCell(kind, after: focusedCell ?? document.worksheet.cells.last?.id,
                                     undo: undoManager)
        focusedCell = id
    }

    public func deleteFocusedCell() {
        guard let id = focusedCell, let index = document.worksheet.index(of: id) else { return }
        document.deleteCell(id, undo: undoManager)
        let cells = document.worksheet.cells
        focusedCell = cells.isEmpty ? nil : cells[min(index, cells.count - 1)].id
    }

    public func setFocusedKind(_ kind: CellKind) {
        guard let id = focusedCell else { return }
        document.setKind(id, kind, undo: undoManager)
    }

    // MARK: - Evaluation (wired to Maxima in step 5)

    public func evaluate(_ id: UUID) {}
    public func evaluateAll() {}
    public func interrupt() {}
    public func restart() {}
}
