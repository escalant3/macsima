// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

struct TokenizerTests {
    /// Each token as (kind, text).
    private func lex(_ text: String) -> [(MaximaToken.Kind, String)] {
        let ns = text as NSString
        return MaximaTokenizer.tokenize(text).map {
            ($0.kind, ns.substring(with: NSRange(location: $0.range.lowerBound, length: $0.range.count)))
        }
    }

    private func kinds(_ text: String) -> [MaximaToken.Kind] { lex(text).map(\.0) }
    private func texts(_ text: String) -> [String] { lex(text).map(\.1) }

    @Test func statement() {
        #expect(texts("f(x):=x^2+1;") == ["f", "(", "x", ")", ":=", "x", "^", "2", "+", "1", ";"])
        #expect(kinds("f(x):=x^2+1;") == [.identifier, .bracket, .identifier, .bracket, .operator,
                                          .identifier, .operator, .number, .operator, .number, .terminator])
        #expect(kinds("a:3$ [a,b]") == [.identifier, .operator, .number, .terminator,
                                        .bracket, .identifier, .separator, .identifier, .bracket])
    }

    /// The cases checked against Maxima in transcripts/raw/32-lexing.
    @Test func lexingAsMaximaDoes() {
        #expect(lex("/* outer /* inner */ still a comment */ 1;").map(\.0) == [.comment, .number, .terminator])
        #expect(texts(#""a\"b"; x"#) == [#""a\"b""#, ";", "x"])
        #expect(texts(#""a\\b" y"#) == [#""a\\b""#, "y"])
        #expect(lex(#"a\+b;"#).map(\.0) == [.identifier, .terminator])
        for number in ["1e3", "1.5e-3", ".5", "1.", "2b3", "1.5B-2", "1.5d0", "42"] {
            #expect(lex(number).map(\.0) == [.number], "\(number)")
        }
        #expect(lex("?atom(1)").map(\.0) == [.lispSymbol, .bracket, .number, .bracket])
        #expect(lex("x_1%2 %pi").map(\.0) == [.identifier, .identifier])
        #expect(kinds("if 1>0 then 2 else 3") == [.keyword, .number, .operator, .number, .keyword, .number,
                                                 .keyword, .number])
    }

    @Test func edges() {
        // An exponent letter without digits is a name after the number.
        #expect(texts("2e") == ["2", "e"])
        // The dot is an operator between names.
        #expect(kinds("a.b") == [.identifier, .operator, .identifier])
        // Unterminated comments and strings run to the end.
        #expect(lex("1 /* open").map(\.0) == [.number, .comment])
        #expect(lex("\"open").map(\.0) == [.string])
        // An operator run stops before a comment.
        #expect(texts("x-/*c*/1") == ["x", "-", "/*c*/", "1"])
        // :lisp lines, only at the start of a line.
        #expect(kinds("1;\n  :lisp (+ 1 2)\n2;") == [.number, .terminator, .lispLine, .number, .terminator])
        #expect(kinds("a :lisp") == [.identifier, .operator, .identifier])
        // Non-ASCII names, and UTF-16 offsets.
        let tokens = MaximaTokenizer.tokenize("α+𝑥;")
        #expect(tokens.map(\.range) == [0..<1, 1..<2, 2..<4, 4..<5])
        #expect(MaximaTokenizer.tokenize("").isEmpty)
    }
}
