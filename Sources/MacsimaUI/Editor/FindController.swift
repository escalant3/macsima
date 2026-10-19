// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WorksheetKit

/// Find and Replace across a worksheet's cell inputs: the find bar's state
/// and its actions. Matches come from the model, so cells the lazy stack
/// hasn't created count too; replacements go through each cell's editor, so
/// they are undone like typing.
@MainActor
@Observable
public final class FindController {
    public var isVisible = false
    public var showsReplace = false
    public var query = "" { didSet { if query != oldValue { search(fromCaret: true) } } }
    public var replacement = ""
    public var caseSensitive = false { didSet { if caseSensitive != oldValue { search(fromCaret: true) } } }
    public private(set) var matches: [SearchMatch] = []
    /// The match shown as selected, an index into `matches`.
    public private(set) var current: Int?
    /// The query field, while the bar is on screen.
    @ObservationIgnored weak var field: NSTextField?

    @ObservationIgnored weak var controller: WorksheetController?

    init() {}

    /// "3 of 12", "No matches", or nothing for an empty query.
    public var status: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No matches" }
        return current.map { "\($0 + 1) of \(matches.count)" } ?? "\(matches.count) found"
    }

    // MARK: - Actions

    public func show(replace: Bool) {
        isVisible = true
        if replace { showsReplace = true }
        // Lay the window out now, so the field exists and takes the focus
        // before the next keystroke is handled.
        controller?.window?.contentView?.layoutSubtreeIfNeeded()
        if let field, let window = field.window {
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let field = self?.field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        search(fromCaret: true)
    }

    /// Esc: hides the bar and puts the focus on the current match.
    public func close() {
        isVisible = false
        markEditors([:])
        guard let controller else { return }
        if let current, current < matches.count {
            controller.focus(matches[current].cell, caret: .range(matches[current].range))
        } else {
            controller.requestFocus()
        }
    }

    public func next() { step(by: 1) }
    public func previous() { step(by: -1) }

    /// Cmd+E: the focused editor's selection becomes the query.
    public func useSelection() {
        guard let controller, let id = controller.focusedCell, let editor = controller.existingEditor(for: id) else { return }
        let selection = editor.selectedRange()
        guard selection.length > 0 else { return }
        query = (editor.string as NSString).substring(with: selection)
    }

    /// Replaces the current match, then shows the next one.
    public func replaceCurrent() {
        guard let controller, let current, current < matches.count else { return }
        let match = matches[current]
        controller.reveal(match.cell)
        let editor = controller.editor(for: match.cell)
        editor.breakUndoCoalescing()
        editor.replace(match.range, with: replacement)
        editor.undoManager?.setActionName("Replace")
        let cells = controller.document.worksheet
        search(from: (cells.index(of: match.cell) ?? 0, match.range.location + (replacement as NSString).length))
    }

    /// Replaces every match, as one undo step.
    public func replaceAll() {
        guard let controller, !matches.isEmpty else { return }
        let undo = controller.undoManager
        undo?.beginUndoGrouping()
        // Last match first, so earlier ranges in a cell stay valid.
        for match in matches.reversed() {
            let editor = controller.editor(for: match.cell)
            editor.breakUndoCoalescing()
            editor.replace(match.range, with: replacement)
        }
        undo?.setActionName("Replace All")
        undo?.endUndoGrouping()
        search(fromCaret: false)
    }

    // MARK: - Searching

    /// Recomputes the matches after the worksheet changed.
    func documentChanged() {
        guard isVisible else { return }
        let keep = current.flatMap { $0 < matches.count ? matches[$0] : nil }
        matches = Self.find(query, caseSensitive, in: controller?.document.worksheet)
        current = keep.flatMap { old in matches.firstIndex { $0.cell == old.cell && $0.range.location >= old.range.location } }
            ?? (matches.isEmpty ? nil : 0)
        markEditors(grouped())
    }

    private func search(fromCaret: Bool) {
        guard let controller else { return }
        var position = (cell: 0, offset: 0)
        if fromCaret, let id = controller.focusedCell, let index = controller.document.worksheet.index(of: id) {
            position = (index, controller.existingEditor(for: id)?.selectedRange().location ?? 0)
        }
        search(from: position)
    }

    private func search(from position: (cell: Int, offset: Int)) {
        guard let controller else { return }
        let sheet = controller.document.worksheet
        matches = Self.find(query, caseSensitive, in: sheet)
        current = WorksheetSearch.firstIndex(of: matches, from: position, cellIndex: sheet.index(of:))
        markEditors(grouped())
        reveal()
    }

    private func step(by delta: Int) {
        if matches.isEmpty { search(fromCaret: true) }
        guard !matches.isEmpty else { NSSound.beep(); return }
        current = ((current ?? -delta) + delta + matches.count) % matches.count
        reveal()
    }

    /// Selects the current match in its editor and scrolls to it, leaving
    /// the focus where it is (the find bar while typing a query).
    private func reveal() {
        guard let controller, let current, current < matches.count else { return }
        let match = matches[current]
        controller.reveal(match.cell)
        let editor = controller.editor(for: match.cell)
        editor.setSelectedRange(match.range)
        controller.scroll(to: match.cell) { editor.scrollRangeToVisible(match.range) }
    }

    private static func find(_ query: String, _ caseSensitive: Bool, in sheet: Worksheet?) -> [SearchMatch] {
        guard let sheet else { return [] }
        return WorksheetSearch.matches(in: sheet, for: query, caseSensitive: caseSensitive) { $0.hasEditor }
    }

    private func grouped() -> [UUID: [NSRange]] {
        Dictionary(grouping: matches, by: \.cell).mapValues { $0.map(\.range) }
    }

    /// Shows the matches in every editor made so far; editors made later
    /// ask for theirs (`marks(for:)`).
    private func markEditors(_ marks: [UUID: [NSRange]]) {
        controller?.forEachEditor { id, editor in editor.findMarks = marks[id] ?? [] }
    }

    func marks(for id: UUID) -> [NSRange] {
        isVisible ? matches.filter { $0.cell == id }.map(\.range) : []
    }
}
