// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

struct PromptClassifierTests {
    @Test func strings() {
        #expect(PromptClassifier.classify("(%i3) ") == .main(label: 3))
        #expect(PromptClassifier.classify("(%i1)") == .main(label: 1))
        #expect(PromptClassifier.classify("\n(dbm:2) ") == .debugger(level: 2))
        #expect(PromptClassifier.classify("\nMAXIMA> ") == .lisp)
        #expect(PromptClassifier.classify("(%o3) ") == .question("(%o3) "))
        #expect(PromptClassifier.classify("(%i) ") == .question("(%i) "))
        #expect(PromptClassifier.classify("Enter a number: ") == .question("Enter a number: "))
    }

    /// Every prompt in every glue fixture, classified.
    @Test func fixtures() throws {
        var kinds: [String: [PromptKind]] = [:]
        for name in Fixtures.names(.glue) {
            kinds[name] = scanWhole(try Fixtures.received(.glue, name)).compactMap {
                if case .prompt(let p) = $0 { PromptClassifier.classify(p) } else { nil }
            }
        }
        for (name, list) in kinds where !name.hasPrefix("25-") {
            #expect(list.last.map { if case .main = $0 { true } else { false } } == true, "\(name) ends idle")
        }
        let q = { (s: String) -> Bool in s.contains("<math>") }
        #expect(kinds["01-integrate"] == [.main(label: 2)])
        #expect(kinds["05-error-syntax"] == [.main(label: 1), .main(label: 2)])
        #expect(kinds["20-lisp"] == [.main(label: 1), .main(label: 2)])
        #expect(kinds["29-to-lisp"] == [.lisp, .lisp, .main(label: 2), .main(label: 3)])
        #expect(kinds["30-debugger"] == [.main(label: 2), .debugger(level: 1), .main(label: 3), .main(label: 4)])
        for name in ["07-asksign-integrate", "08-asksign"] {
            let list = kinds[name] ?? []
            #expect(list.count == 3)
            if case .question(let content) = list.first { #expect(q(content)) } else { Issue.record("\(name): no question") }
        }
    }
}

struct StatementSplitterTests {
    func texts(_ cell: String) throws -> [String] {
        try StatementSplitter.split(cell).map(\.text)
    }

    @Test func basics() throws {
        #expect(try StatementSplitter.split("a:3$ a;") == [
            Statement(text: "a:3$", terminator: .hide), Statement(text: "a;", terminator: .show),
        ])
        #expect(try texts("integrate(sin(x), x)") == ["integrate(sin(x), x);"])
        #expect(try texts("  \n ") == [])
        #expect(try texts("x;\n\ny;\n") == ["x;", "y;"])
    }

    @Test func stringsAndComments() throws {
        #expect(try texts(#"print("a;b$c"); 2;"#) == [#"print("a;b$c");"#, "2;"])
        #expect(try texts(#"s:"say \"hi;\""$"#) == [#"s:"say \"hi;\""$"#])
        #expect(try texts("/* a; b */ x; /* trailing; */") == ["x;"])
        #expect(try texts("x /* in; side */ + 1") == ["x /* in; side */ + 1;"])
        #expect(try texts("/* outer /* inner; */ still; */ y;") == ["y;"])
        #expect(try texts("/* only a comment */") == [])
        #expect(try texts(#"f("(")"#) == [#"f("(");"#])
        #expect(try texts("/* ( */ g(1);") == ["g(1);"])
        #expect(try texts(#"a\;b;"#) == [#"a\;b;"#])
    }

    @Test func lispLines() throws {
        #expect(try StatementSplitter.split(":lisp (+ 1 2)\n2+2;") == [
            Statement(text: ":lisp (+ 1 2)", terminator: .line), Statement(text: "2+2;", terminator: .show),
        ])
        #expect(try texts("x;\n:lisp (format t \"a;b\")\ny") == ["x;", #":lisp (format t "a;b")"#, "y;"])
        #expect(try texts("  :lisp-quiet (setq a 1)  ") == [":lisp-quiet (setq a 1)"])
        #expect(try texts("a:b; c:d;") == ["a:b;", "c:d;"], "a colon inside a statement is not a command")
    }

    @Test func brackets() throws {
        #expect(throws: SplitError.unclosed("(", at: SourcePosition(line: 1, column: 2))) {
            try StatementSplitter.split("f(x;")
        }
        #expect(throws: SplitError.unexpectedClose("]", at: SourcePosition(line: 2, column: 4), expected: ")")) {
            try StatementSplitter.split("1;\nf(x];")
        }
        #expect(throws: SplitError.unexpectedClose(")", at: SourcePosition(line: 1, column: 2), expected: nil)) {
            try StatementSplitter.split("x)")
        }
        #expect(throws: SplitError.unclosedString(at: SourcePosition(line: 1, column: 7))) {
            try StatementSplitter.split("print(\"abc);")
        }
        #expect(throws: SplitError.unclosedComment(at: SourcePosition(line: 1, column: 4))) {
            try StatementSplitter.split("x; /* never")
        }
        #expect(try texts("[{(a)}, b];") == ["[{(a)}, b];"])
        let message = SplitError.unexpectedClose("]", at: SourcePosition(line: 2, column: 4), expected: ")").description
        #expect(message == "Unbalanced parentheses: found \"]\" at line 2, column 4 where \")\" was expected.")
    }
}
