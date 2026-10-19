// SPDX-License-Identifier: GPL-2.0-or-later
//
// Cases ported from wxMaxima's test/unit_tests/test_SyntaxErrorLocation.cpp
// (commit 13e4aee, Copyright (C) 2026 Gunter Königsmann, GPL-2.0-or-later).
// The Maxima outputs are from real Maxima runs: the ones with "Space" from
// Maxima 5.46, which spells blanks out that way.

import Foundation
import Testing
@testable import MaximaKit

struct SyntaxErrorLocationTests {
    private func statement(_ cell: String, _ part: String) -> Range<Int> {
        let r = (cell as NSString).range(of: part)
        return r.location..<NSMaxRange(r)
    }

    private func marked(_ cell: String, _ output: String, _ part: String? = nil) -> String? {
        guard let r = SyntaxErrorLocation.locate(output: output, cellText: cell,
                                                 statement: statement(cell, part ?? cell)) else { return nil }
        return (cell as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count))
    }

    @Test func echo() {
        #expect(SyntaxErrorLocation.echo(in: "\nincorrect syntax: , is not a prefix operator\nf(a,,\n   ^\n") == "f(a,,")
        #expect(SyntaxErrorLocation.echo(in: "\nincorrect syntax: , is not a prefix operator\nf(a,,\n") == nil,
                "no caret line yet")
        #expect(SyntaxErrorLocation.echo(in: "incorrect syntax: Missing )\r\nsin(x)+(2;\r\n        ^\r\n") == "sin(x)+(2;")
        #expect(SyntaxErrorLocation.echo(in: "incorrect syntax: , is not a prefix operator\nSpaceSpaceb:x,,\n     ^\n"
                                         + "incorrect syntax: Too many )'s\nSpaceSpaceb)\n  ^\n") == "SpaceSpaceb:x,,")
        #expect(SyntaxErrorLocation.echo(in: "length: argument cannot be a symbol; found y\n -- an error. To debug this try: debugmode(true);\n") == nil)
        // As MaximaKit delivers it (transcript glue/05-error-syntax).
        #expect(SyntaxErrorLocation.echo(in: "incorrect syntax: Premature termination of input at ;.\nx+;\n ^") == "x+;")
    }

    @Test func locate() {
        #expect(marked("a: 1$\nf(a,,b);\n", "incorrect syntax: , is not a prefix operator\nf(a,,\n   ^\n", "f(a,,b);") == ",,")
        #expect(marked("x: 2 34;", "incorrect syntax: 34 is not an infix operator\nx:Space2Space34;\n      ^\n") == "34;")
        #expect(marked("sin(x)+(2;", "incorrect syntax: Missing )\nsin(x)+(2;\n        ^\n") == "2;")
        let block = "a: 1$\nf(x):=block(\n  [b],\n  b:x,,\n  b)$\nc: 3;"
        #expect(marked(block, "incorrect syntax: , is not a prefix operator\nSpaceSpaceb:x,,\n     ^\n",
                       "f(x):=block(\n  [b],\n  b:x,,\n  b)$") == ",,")
        let twice = "f(x):=g(  a,,\n  a,,\n  b)$"
        let r = SyntaxErrorLocation.locate(output: "incorrect syntax: , is not a prefix operator\n  a,,\n   ^\n",
                                           cellText: twice, statement: 0..<(twice as NSString).length)
        #expect(r?.lowerBound == (twice as NSString).range(of: "\n  a,,").location + 4, "the occurrence starting a line wins")
        #expect(marked("verylongvariablename1 + verylongvariablename2 ) ;",
                       "incorrect syntax: Too many )'s\nylongvariablename2Space)\n                  ^\n") == " )")
        #expect(marked("mySpace: 1 2;", "incorrect syntax: 2 is not an infix operator\nmySpace: 1 2;\n           ^\n") == "2;")
        #expect(marked("a: 1$ b: 2 /* note */ 3;",
                       "incorrect syntax: 3 is not an infix operator\nb:Space2SpaceSpace3;\n       ^\n",
                       "b: 2 /* note */ 3;") == nil)
        #expect(marked("x+;", "incorrect syntax: Premature termination of input at ;.\nx+;\n ^") == "+;")
    }

    @Test func statementRanges() throws {
        let cell = "a:1$  /* c */ b:2;\n:lisp (+ 1 2)\n f(x)"
        let ns = cell as NSString
        let ranges = try StatementSplitter.ranges(cell)
        #expect(ranges.map { ns.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
                == ["a:1$", "b:2;", ":lisp (+ 1 2)", "f(x)"])
        #expect(try StatementSplitter.ranges("🙂x;") == [0..<4], "UTF-16 offsets")
    }

    @Test func splitErrorPositions() {
        let cell = "a:1;\nf(x:=2;"
        do {
            _ = try StatementSplitter.split(cell)
            Issue.record("expected a split error")
        } catch {
            #expect(error.position.utf16Offset(in: cell) == 6, "the unclosed ( on line 2")
        }
        #expect(SourcePosition(line: 1, column: 3).utf16Offset(in: "🙂ab") == 3)
        #expect(SourcePosition(line: 3, column: 1).utf16Offset(in: "a") == nil)
    }
}
