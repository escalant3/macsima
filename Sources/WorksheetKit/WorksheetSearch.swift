// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// One place a search matched: a range (UTF-16) in a cell's input.
public struct SearchMatch: Equatable, Sendable {
    public var cell: UUID
    public var range: NSRange

    public init(cell: UUID, range: NSRange) {
        self.cell = cell
        self.range = range
    }
}

/// Plain-text search over the cells' inputs, for Find and Replace.
public enum WorksheetSearch {
    /// Every match of `query` in the inputs of the cells `include` accepts,
    /// in document order. Matches don't overlap.
    public static func matches(in worksheet: Worksheet, for query: String, caseSensitive: Bool,
                               include: (Cell) -> Bool = { _ in true }) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }
        return worksheet.cells.filter(include).flatMap { cell in
            ranges(of: query, in: cell.input, caseSensitive: caseSensitive).map { SearchMatch(cell: cell.id, range: $0) }
        }
    }

    public static func ranges(of query: String, in text: String, caseSensitive: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var found: [NSRange] = []
        var from = 0
        while from < ns.length {
            let range = ns.range(of: query, options: options, range: NSRange(location: from, length: ns.length - from))
            guard range.location != NSNotFound, range.length > 0 else { break }
            found.append(range)
            from = NSMaxRange(range)
        }
        return found
    }

    /// The index of the first match at or after `position` (a cell index and
    /// an offset in it); wraps to the first match.
    public static func firstIndex(of matches: [SearchMatch], from position: (cell: Int, offset: Int),
                                  cellIndex: (UUID) -> Int?) -> Int? {
        guard !matches.isEmpty else { return nil }
        let index = matches.firstIndex { match in
            guard let c = cellIndex(match.cell) else { return false }
            return c > position.cell || (c == position.cell && match.range.location >= position.offset)
        }
        return index ?? 0
    }
}
