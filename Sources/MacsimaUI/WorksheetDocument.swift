// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers
import WorksheetKit

/// A worksheet file. Structural edits (insert, delete, kind changes) register
/// their inverse with the window's undo manager; typing inside a cell is
/// undone by the text view itself, on the same undo manager.
///
/// Not main-actor isolated as a whole because SwiftUI creates, reads and
/// snapshots documents from its own contexts; the edit methods are
/// main-actor isolated, and SwiftUI takes snapshots on the main thread.
/// That is the invariant behind `@unchecked Sendable` (ReferenceFileDocument
/// requires Sendable): `worksheet` is only ever mutated on the main actor.
public final class WorksheetDocument: ReferenceFileDocument, @unchecked Sendable {
    public static let readableContentTypes: [UTType] = [.wxmx]

    @Published public var worksheet: Worksheet
    /// What the reader kept without being able to show it; shown when the file opens.
    @Published public var openWarnings: [String] = []

    public init(worksheet: Worksheet = .empty()) {
        self.worksheet = worksheet
    }

    public required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            let result = try WXMXReader.read(data)
            worksheet = result.worksheet.cells.isEmpty ? .empty() : result.worksheet
            openWarnings = result.warnings
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedFailureReasonErrorKey: "\(error)"])
        }
    }

    public func snapshot(contentType: UTType) throws -> Worksheet {
        worksheet
    }

    public func fileWrapper(snapshot: Worksheet, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try WXMXWriter.write(snapshot))
    }

    // MARK: - Undoable edits

    /// Inserts a new cell of `kind` after the cell `id` (or at the end) and returns its ID.
    @discardableResult
    @MainActor
    public func insertCell(_ kind: CellKind, after id: UUID?, undo: UndoManager?) -> UUID {
        let cell = Cell(kind: kind)
        let index = worksheet.insert(cell, after: id)
        registerInsertUndo(cell.id, undo: undo, name: "Insert Cell")
        _ = index
        return cell.id
    }

    @MainActor
    public func deleteCell(_ id: UUID, undo: UndoManager?) {
        guard let (cell, index) = worksheet.remove(id) else { return }
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.worksheet.insert(cell, at: index)
                doc.registerInsertUndo(cell.id, undo: undo, name: "Delete Cell")
            }
        }
        undo?.setActionName("Delete Cell")
        if worksheet.cells.isEmpty { worksheet.insert(Cell(kind: .code), at: 0) }
    }

    @MainActor
    public func setKind(_ id: UUID, _ kind: CellKind, undo: UndoManager?) {
        guard let old = worksheet[id]?.kind, old != kind else { return }
        worksheet.setKind(id, kind)
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.setKind(id, old, undo: undo) }
        }
        undo?.setActionName("Change Cell Type")
    }

    @MainActor
    public func setInput(_ id: UUID, _ text: String) {
        guard worksheet[id]?.input != text else { return }
        worksheet.setInput(id, text)
    }

    @MainActor
    private func registerInsertUndo(_ id: UUID, undo: UndoManager?, name: String) {
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.deleteCell(id, undo: undo) }
        }
        undo?.setActionName(name)
    }
}
