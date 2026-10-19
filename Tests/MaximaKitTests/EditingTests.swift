// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

struct EditingTests {
    @Test func indentAfterNewline() {
        #expect(MaximaEditing.indentAfterNewline(line: "x:1;") == "")
        #expect(MaximaEditing.indentAfterNewline(line: "  y:2,") == "  ")
        #expect(MaximaEditing.indentAfterNewline(line: "f(x):=block([a],") == "  ")
        #expect(MaximaEditing.indentAfterNewline(line: "  for i thru 3 do (") == "    ")
        #expect(MaximaEditing.indentAfterNewline(line: "  g(a)") == "  ", "closed brackets add nothing")
        #expect(MaximaEditing.indentAfterNewline(line: "print(\"(\"") == "  ", "brackets in strings don't count")
        #expect(MaximaEditing.indentAfterNewline(line: "  a)") == "  ", "a closing bracket keeps the line's indentation")
    }

    @Test func indentBeforeClosing() {
        #expect(MaximaEditing.indentBeforeClosing(line: "    ") == "  ")
        #expect(MaximaEditing.indentBeforeClosing(line: "  ") == "")
        #expect(MaximaEditing.indentBeforeClosing(line: " ") == nil)
        #expect(MaximaEditing.indentBeforeClosing(line: "") == nil)
        #expect(MaximaEditing.indentBeforeClosing(line: "  a") == nil)
    }

    private func toggle(_ text: String, _ location: Int, _ length: Int = 0) -> String {
        let edit = MaximaEditing.toggleComment(in: text, selection: NSRange(location: location, length: length))
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.text)
    }

    @Test func toggleComment() {
        // The caret's line, then back.
        #expect(toggle("a:1;\nb:2;", 7) == "a:1;\n/* b:2; */")
        #expect(toggle("a:1;\n/* b:2; */", 8) == "a:1;\nb:2;")
        // Indentation stays outside.
        #expect(toggle("  x;", 0) == "  /* x; */")
        #expect(toggle("  /* x; */", 3) == "  x;")
        // A selection over two lines: one comment around both.
        #expect(toggle("a;\nb;\nc;", 1, 3) == "/* a;\nb; */\nc;")
        // A selection ending at the start of a line doesn't take that line.
        #expect(toggle("a;\nb;\nc;", 0, 3) == "/* a; */\nb;\nc;")
        // Empty text.
        #expect(toggle("", 0) == "/*  */")
        let edit = MaximaEditing.toggleComment(in: "a;\nb;", selection: NSRange(location: 4, length: 0))
        #expect(edit.selection == NSRange(location: 3, length: 8), "the new block is selected")
    }
}
