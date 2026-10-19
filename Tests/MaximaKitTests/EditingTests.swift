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
}
