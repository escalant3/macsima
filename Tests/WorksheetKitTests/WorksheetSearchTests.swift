// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import WorksheetKit

struct WorksheetSearchTests {
    @Test func ranges() {
        #expect(WorksheetSearch.ranges(of: "x", in: "x+x^2", caseSensitive: true)
                == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
        #expect(WorksheetSearch.ranges(of: "aa", in: "aaaa", caseSensitive: true).count == 2, "no overlaps")
        #expect(WorksheetSearch.ranges(of: "Sin", in: "sin(x)+SIN", caseSensitive: false).count == 2)
        #expect(WorksheetSearch.ranges(of: "Sin", in: "sin(x)+SIN", caseSensitive: true).isEmpty)
        #expect(WorksheetSearch.ranges(of: "", in: "abc", caseSensitive: true).isEmpty)
        // UTF-16 offsets, as the text views count.
        #expect(WorksheetSearch.ranges(of: "x", in: "🙂x", caseSensitive: true) == [NSRange(location: 2, length: 1)])
    }

    @Test func acrossCells() {
        let a = Cell(kind: .code, input: "f(x):=x^2;"), b = Cell(kind: .pageBreak), c = Cell(kind: .text, input: "x marks")
        let sheet = Worksheet(cells: [a, b, c])
        let all = WorksheetSearch.matches(in: sheet, for: "x", caseSensitive: true)
        #expect(all.map(\.cell) == [a.id, a.id, c.id])
        let codeOnly = WorksheetSearch.matches(in: sheet, for: "x", caseSensitive: true) { $0.kind == .code }
        #expect(codeOnly.count == 2)

        let index = { (id: UUID) in sheet.index(of: id) }
        #expect(WorksheetSearch.firstIndex(of: all, from: (0, 0), cellIndex: index) == 0)
        #expect(WorksheetSearch.firstIndex(of: all, from: (0, 3), cellIndex: index) == 1)
        #expect(WorksheetSearch.firstIndex(of: all, from: (1, 0), cellIndex: index) == 2)
        #expect(WorksheetSearch.firstIndex(of: all, from: (2, 1), cellIndex: index) == 0, "wraps")
        #expect(WorksheetSearch.firstIndex(of: [], from: (0, 0), cellIndex: index) == nil)
    }
}
