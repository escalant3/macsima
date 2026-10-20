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
    public static let readableContentTypes: [UTType] = [.wxmx, .wxm]
    public static let writableContentTypes: [UTType] = [.wxmx, .wxm]

    /// A `.wxm` larger than this is refused: it is untrusted input, and a
    /// real one is text without outputs.
    static let maxWXMBytes = 64 << 20

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
        if configuration.contentType.conforms(to: .wxm) {
            guard data.count <= Self.maxWXMBytes else {
                throw CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedFailureReasonErrorKey: "The .wxm file is over 64 MB."])
            }
            // wxMaxima writes UTF-8; older files may be Latin-1.
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let result = WXMFormat.read(text)
            worksheet = Worksheet(cells: result.cells.isEmpty ? [Cell(kind: .code)] : result.cells)
            openWarnings = result.warnings
            return
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

    /// `.wxm` keeps inputs, headings, text, images and answers, not outputs
    /// or zoom (as in wxMaxima); `.wxmx` keeps everything.
    public func fileWrapper(snapshot: Worksheet, configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType.conforms(to: .wxm) {
            return FileWrapper(regularFileWithContents: Data(WXMFormat.document(snapshot).utf8))
        }
        return FileWrapper(regularFileWithContents: try WXMXWriter.write(snapshot))
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

    /// Inserts `cells` at `index`, as one undoable action (paste).
    @MainActor
    public func insertCells(_ cells: [Cell], at index: Int, undo: UndoManager?, name: String = "Paste") {
        let start = min(max(0, index), worksheet.cells.count)
        for (k, cell) in cells.enumerated() { worksheet.insert(cell, at: start + k) }
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.deleteCells(cells.map(\.id), undo: undo, name: name) }
        }
        undo?.setActionName(name)
    }

    /// Deletes the cells `ids`, as one undoable action (cut, delete).
    @MainActor
    public func deleteCells(_ ids: [UUID], undo: UndoManager?, name: String = "Delete Cells") {
        // Removed in document order, put back in the same order.
        let removed = ids.compactMap { id in worksheet.index(of: id).map { (id, $0) } }
            .sorted { $0.1 < $1.1 }
        var restore: [(Cell, Int)] = []
        for (id, _) in removed.reversed() {
            if let (cell, index) = worksheet.remove(id) { restore.insert((cell, index), at: 0) }
        }
        guard !restore.isEmpty else { return }
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                for (cell, index) in restore { doc.worksheet.insert(cell, at: index) }
                doc.undoManagerRedoDelete(restore.map(\.0.id), undo: undo, name: name)
            }
        }
        undo?.setActionName(name)
        if worksheet.cells.isEmpty { worksheet.insert(Cell(kind: .code), at: 0) }
    }

    @MainActor
    private func undoManagerRedoDelete(_ ids: [UUID], undo: UndoManager?, name: String) {
        undo?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated { doc.deleteCells(ids, undo: undo, name: name) }
        }
        undo?.setActionName(name)
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
