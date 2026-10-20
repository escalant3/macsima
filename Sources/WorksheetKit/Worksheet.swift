// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The kinds of cell a `.wxmx` worksheet can hold. The editor creates only
/// code, text, title, section and subsection cells; the others are kept so
/// files from wxMaxima survive a round trip.
public enum CellKind: String, CaseIterable, Codable, Sendable {
    case title, section, subsection, subsubsection, heading5, heading6
    case text, code, image, pageBreak
    /// A cell this app cannot show (an unknown type, or an image cell): its
    /// XML is kept in `preserved` and written back unchanged.
    case raw

    /// True for the heading-like kinds (title down to heading6).
    public var isHeading: Bool {
        [.title, .section, .subsection, .subsubsection, .heading5, .heading6].contains(self)
    }

    /// 1 for a title down to 6 for heading 6; nil for other kinds.
    public var headingLevel: Int? {
        switch self {
        case .title: 1
        case .section: 2
        case .subsection: 3
        case .subsubsection: 4
        case .heading5: 5
        case .heading6: 6
        default: nil
        }
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
    /// `attributes` keeps what a `.wxmx` said about it (`ppi`, gnuplot data).
    case image(data: Data, format: String, label: String?, attributes: [String: String] = [:])
    /// An animation (`with_slider`, `wxanimate`): its frames' bytes, in order.
    /// `attributes` keeps the `slide` element's (`fr` frame rate, `running`,
    /// `frame`, gnuplot sources).
    case animation(frames: [Data], format: String, label: String?, attributes: [String: String] = [:])
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
    /// XML this app does not understand, kept verbatim for writing back:
    /// unknown child elements (folded cells, for example), or the whole cell
    /// for `.raw`.
    public var preserved: [String]
    /// Attributes of the `.wxmx` cell element this app does not act on
    /// (`hide`, `auto_answer`, unmatched `questionN`/`answerN`, ...).
    public var extraAttributes: [String: String]
    /// The editor XML as read, while it carries formatting this app cannot
    /// edit; written back as long as `input` still equals `text`.
    public var preservedEditor: PreservedEditor?
    /// Bold, italic, ... per Unicode scalar of `input` (text cells; empty
    /// when plain).
    public var textFormats: TextFormats = []
    /// A heading whose section is folded: the cells after it, up to the next
    /// heading of its level or higher, are hidden (wxMaxima keeps them in a
    /// `<fold>` inside the heading).
    public var isFolded = false

    /// A code or text cell shown as its first line only, outputs hidden
    /// (wxMaxima's `hide="true"`).
    public var isHidden: Bool {
        get { extraAttributes["hide"] == "true" }
        set { extraAttributes["hide"] = newValue ? "true" : nil }
    }

    public init(id: UUID = UUID(), kind: CellKind, input: String = "", outputs: [Output] = [],
                inputLabel: Int? = nil, preserved: [String] = [], extraAttributes: [String: String] = [:],
                preservedEditor: PreservedEditor? = nil, isFolded: Bool = false, textFormats: TextFormats = []) {
        self.id = id
        self.kind = kind
        self.input = input
        self.outputs = outputs
        self.inputLabel = inputLabel
        self.preserved = preserved
        self.extraAttributes = extraAttributes
        self.preservedEditor = preservedEditor
        self.isFolded = isFolded
        self.textFormats = textFormats
    }
}

/// An editor element kept verbatim, with the text it held.
public struct PreservedEditor: Equatable, Sendable {
    public var text: String
    public var xml: String

    public init(text: String, xml: String) {
        self.text = text
        self.xml = xml
    }
}

/// A worksheet: an ordered list of cells.
public struct Worksheet: Equatable, Sendable {
    public var cells: [Cell]
    /// Document-level XML this app does not understand, kept for writing back.
    public var preserved: [String]
    /// The `.wxmx` zoom in percent.
    public var zoom: Int
    /// Attributes of `wxMaximaDocument` this app does not act on
    /// (`activecell`, the variables list, ...).
    public var extraAttributes: [String: String]
    /// Files from a `.wxmx` that no output of this app uses (images of
    /// preserved cells, gnuplot data): written back under the same names.
    public var attachments: [String: Data]

    public init(cells: [Cell] = [], preserved: [String] = [], zoom: Int = 100,
                extraAttributes: [String: String] = [:], attachments: [String: Data] = [:]) {
        self.cells = cells
        self.preserved = preserved
        self.zoom = zoom
        self.extraAttributes = extraAttributes
        self.attachments = attachments
    }

    /// A new worksheet with one empty code cell.
    public static func empty() -> Worksheet { Worksheet(cells: [Cell(kind: .code)]) }

    /// The variables panel's watch list, kept where wxMaxima keeps it: the
    /// root's `variables_num` and `variables_0` ... attributes, so a file
    /// round-trips unchanged. wxMaxima writes one more `variables_N` than
    /// `variables_num` counts (its grid's empty last row, WXMXformat.cpp);
    /// so does this. Capped at 1000 names: the count is untrusted input.
    public var watchedVariables: [String] {
        get {
            let count = min(max(0, Int(extraAttributes["variables_num"] ?? "") ?? 0), 1000)
            return (0..<count).compactMap { extraAttributes["variables_\($0)"] }.filter { !$0.isEmpty }
        }
        set {
            for key in extraAttributes.keys where key.hasPrefix("variables_") { extraAttributes[key] = nil }
            let names = newValue.filter { !$0.isEmpty }
            guard !names.isEmpty else { return }
            extraAttributes["variables_num"] = String(names.count)
            for (i, name) in names.enumerated() { extraAttributes["variables_\(i)"] = name }
            extraAttributes["variables_\(names.count)"] = ""
        }
    }

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

    /// The cells a heading at `index` folds: up to the next heading of its
    /// level or higher (wxMaxima's GroupCell::Fold). Empty for other cells.
    public func foldRange(of index: Int) -> Range<Int> {
        guard cells.indices.contains(index), let level = cells[index].kind.headingLevel else { return index..<index }
        var end = index + 1
        while end < cells.count {
            if let l = cells[end].kind.headingLevel, l <= level { break }
            end += 1
        }
        return (index + 1)..<end
    }

    /// Indices of the cells a reader sees: those inside a folded heading's
    /// section are left out.
    public var visibleIndices: [Int] {
        var out: [Int] = []
        var hidingBelow: Int?   // level of the folded heading being skipped
        for (i, cell) in cells.enumerated() {
            if let hiding = hidingBelow {
                if let l = cell.kind.headingLevel, l <= hiding { hidingBelow = nil } else { continue }
            }
            out.append(i)
            if cell.isFolded, let l = cell.kind.headingLevel, !foldRange(of: i).isEmpty { hidingBelow = l }
        }
        return out
    }

    /// The folded headings that hide the cell at `index`, outermost first.
    public func foldedAncestors(of index: Int) -> [Int] {
        var out: [Int] = []
        var level = cells.indices.contains(index) ? (cells[index].kind.headingLevel ?? 7) : 7
        var i = index - 1
        while i >= 0 {
            if let l = cells[i].kind.headingLevel, l < level {
                if cells[i].isFolded { out.insert(i, at: 0) }
                level = l
            }
            i -= 1
        }
        return out
    }

    /// Code cells, in order (what "evaluate all" runs).
    public var codeCells: [Cell] { cells.filter { $0.kind == .code } }
}
