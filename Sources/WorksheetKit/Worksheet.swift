// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The kinds of cell a `.wxmx` worksheet can hold. The editor creates only
/// code, text, title, section and subsection cells; the others are kept so
/// files from wxMaxima survive a round trip.
public enum CellKind: String, CaseIterable, Codable, Sendable {
    case title, section, subsection, subsubsection, heading5, heading6
    case text, code, image, pageBreak

    /// True for the heading-like kinds (title down to heading6).
    public var isHeading: Bool {
        [.title, .section, .subsection, .subsubsection, .heading5, .heading6].contains(self)
    }
}

/// One piece of a code cell's output.
public enum Output: Equatable, Sendable {
    /// A math chunk as Maxima printed it (raw XML, label included).
    case math(xml: String)
    /// Plain text (print output, `display2d:false` results, `tex()`).
    case text(String)
    /// An error. `kind` is MaximaKit's error kind (`maxima`, `syntax`,
    /// `lisp`), or nil when unknown; `message` may be empty.
    case error(kind: String?, message: String)
    /// An image (a plot) with its bytes, so it outlives Maxima's temp file.
    case image(data: Data, format: String, label: String?)
    /// A question Maxima asked (raw prompt XML) and the answer, once given.
    case question(prompt: String, answer: String?)
}

/// One cell of a worksheet.
public struct Cell: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: CellKind
    /// The editable text: code for code cells, prose or a heading otherwise.
    public var input: String
    public var outputs: [Output]
    /// The `(%iN)` label of the last evaluation, if any.
    public var inputLabel: Int?
    /// XML this app does not understand, kept verbatim for writing back.
    public var preserved: [String]

    public init(id: UUID = UUID(), kind: CellKind, input: String = "", outputs: [Output] = [],
                inputLabel: Int? = nil, preserved: [String] = []) {
        self.id = id
        self.kind = kind
        self.input = input
        self.outputs = outputs
        self.inputLabel = inputLabel
        self.preserved = preserved
    }
}

/// A worksheet: an ordered list of cells.
public struct Worksheet: Equatable, Sendable {
    public var cells: [Cell]
    /// Document-level XML this app does not understand, kept for writing back.
    public var preserved: [String]

    public init(cells: [Cell] = [], preserved: [String] = []) {
        self.cells = cells
        self.preserved = preserved
    }

    /// A new worksheet with one empty code cell.
    public static func empty() -> Worksheet { Worksheet(cells: [Cell(kind: .code)]) }

    public func index(of id: UUID) -> Int? { cells.firstIndex { $0.id == id } }

    public subscript(id: UUID) -> Cell? {
        get { index(of: id).map { cells[$0] } }
    }

    /// Inserts `cell` at `index` (clamped to the valid range).
    public mutating func insert(_ cell: Cell, at index: Int) {
        cells.insert(cell, at: min(max(0, index), cells.count))
    }

    /// Inserts `cell` right after the cell `id`, or at the end.
    @discardableResult
    public mutating func insert(_ cell: Cell, after id: UUID?) -> Int {
        let at = id.flatMap(index(of:)).map { $0 + 1 } ?? cells.count
        insert(cell, at: at)
        return at
    }

    /// Removes the cell `id`; returns it with its old index.
    @discardableResult
    public mutating func remove(_ id: UUID) -> (cell: Cell, index: Int)? {
        guard let i = index(of: id) else { return nil }
        return (cells.remove(at: i), i)
    }

    /// Moves the cell `id` to `index` (clamped).
    public mutating func move(_ id: UUID, to index: Int) {
        guard let removed = remove(id) else { return }
        insert(removed.cell, at: index)
    }

    public mutating func update(_ id: UUID, _ change: (inout Cell) -> Void) {
        guard let i = index(of: id) else { return }
        change(&cells[i])
    }

    public mutating func setInput(_ id: UUID, _ text: String) { update(id) { $0.input = text } }
    public mutating func setKind(_ id: UUID, _ kind: CellKind) { update(id) { $0.kind = kind } }

    public mutating func clearOutputs(_ id: UUID) {
        update(id) {
            $0.outputs = []
            $0.inputLabel = nil
        }
    }

    /// Code cells, in order (what "evaluate all" runs).
    public var codeCells: [Cell] { cells.filter { $0.kind == .code } }
}
