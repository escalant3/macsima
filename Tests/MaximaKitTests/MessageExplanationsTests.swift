// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import MaximaKit

struct MessageExplanationsTests {
    @Test func knownMessages() {
        // The first error of 03-errors, which wxMaxima 26.09 marks in yellow.
        #expect(MessageExplanations.explanation(
            for: "expt: undefined: 0 to a negative exponent.\n -- an error. To debug this try: debugmode(true);")
            == "Division by 0.")
        #expect(MessageExplanations.explanation(for: "incorrect syntax: , is not a prefix operator\nf(a,,\n   ^")?
            .hasPrefix("Most probable cause: Two commas") == true)
        #expect(MessageExplanations.explanation(for: "part: fell off the end.")?.hasPrefix("part() or the []") == true)
        #expect(MessageExplanations.explanation(for: "at: improper argument: x")?.contains("at()") == true)
        #expect(MessageExplanations.explanation(for: "subst: improper argument: x")?.contains("subst()") == true)
    }

    @Test func unknownMessages() {
        #expect(MessageExplanations.explanation(for: "custom failure") == nil)
        #expect(MessageExplanations.explanation(for: "incorrect syntax: Premature termination of input at ;.\nx+;\n ^") == nil)
        #expect(MessageExplanations.explanation(for: "") == nil)
    }
}
