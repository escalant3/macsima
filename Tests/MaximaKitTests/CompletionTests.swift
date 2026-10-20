// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

struct CompletionTests {
    @Test func builtinList() {
        let index = CompletionIndex.builtin
        #expect(index.names.count > 2000)
        #expect(index.templates["integrate"] == ["integrate(<expr>, <x>)", "integrate(<expr>, <x>, <a>, <b>)"])
        #expect(index.templates["diff"]?.count == 5)
        #expect(index.names.contains("integrate_use_rootsof"))
        #expect(!index.names.contains { $0.hasPrefix("#") }, "the comment header is skipped")
    }

    @Test func wordUnderCaret() {
        let text = "x: integ"
        #expect(MaximaCompletion.word(in: text, caret: 8)?.prefix == "integ")
        #expect(MaximaCompletion.word(in: text, caret: 8)?.range == NSRange(location: 3, length: 5))
        // In the middle of a word: the part before the caret, the whole word replaced.
        let middle = MaximaCompletion.word(in: "integrate(x)", caret: 4)
        #expect(middle?.prefix == "inte")
        #expect(middle?.range == NSRange(location: 0, length: 9))
        #expect(MaximaCompletion.word(in: "x: ", caret: 3) == nil)
        #expect(MaximaCompletion.word(in: "\"integ", caret: 6) == nil, "not in strings")
        #expect(MaximaCompletion.word(in: "/* integ */", caret: 8) == nil, "not in comments")
        #expect(MaximaCompletion.word(in: "1.5", caret: 3) == nil, "not in numbers")
    }

    @Test func worksheetDefinitions() {
        let index = MaximaCompletion.symbols(in: """
            f(x, y) := x + y;
            g([l]) := length(l)$
            define(h(t), t^2);
            m(a, b:2) := a;
            p() := 1;
            sq[n] := n^2;
            r(x) ::= x;
            velocity: 3;
            """)
        #expect(index.templates["f"] == ["f(<x>, <y>)"])
        #expect(index.templates["g"] == ["g(<[l]>)"])
        #expect(index.templates["h"] == ["h(<t>)"])
        #expect(index.templates["m"] == nil, "a parameter that isn't a name gives no template")
        #expect(index.templates["p"] == ["p()"])
        #expect(index.templates["r"] == ["r(<x>)"])
        #expect(index.templates["length"] == nil, "a call is no definition")
        #expect(index.names.isSuperset(of: ["f", "g", "h", "sq", "velocity", "length"]))
    }

    @Test func skipsTheWordBeingTyped() {
        let text = "velocity: 3; velo"
        let word = MaximaCompletion.word(in: text, caret: 17)!
        #expect(MaximaCompletion.symbols(in: text, skipping: word.range).names == ["velocity"])
        #expect(MaximaCompletion.symbols(in: "velo", skipping: NSRange(location: 0, length: 4)).names.isEmpty)
    }

    @Test func completionOrder() {
        let maxima = CompletionIndex.builtin
        let sheet = MaximaCompletion.symbols(in: "integrand(x) := x^2; integration_mine: 1;")
        let items = MaximaCompletion.completions(of: "integra", maxima: maxima, worksheet: sheet)
        // Alphabetical; a name's templates shortest first.
        #expect(items.prefix(3).map(\.insertion) == ["integrand(<x>)", "integrate(<expr>, <x>)", "integrate(<expr>, <x>, <a>, <b>)"])
        #expect(items.contains(CompletionItem(name: "integrand", template: "integrand(<x>)", source: .worksheet)))
        #expect(items.contains(CompletionItem(name: "integration_mine", source: .worksheet)))
        #expect(items.contains(CompletionItem(name: "integrate_use_rootsof", source: .maxima)))
        // An exact name comes first.
        let exact = MaximaCompletion.completions(of: "diff", maxima: maxima, worksheet: CompletionIndex())
        #expect(exact.prefix(5).allSatisfy { $0.name == "diff" })
    }

    @Test func worksheetDefinitionReplacesMaximas() {
        let sheet = MaximaCompletion.symbols(in: "expand(e, n) := e;")
        let items = MaximaCompletion.completions(of: "expand", maxima: .builtin, worksheet: sheet)
        #expect(items.first == CompletionItem(name: "expand", template: "expand(<e>, <n>)", source: .worksheet))
        #expect(!items.contains { $0.template == "expand(<expr>)" })
    }

    @Test func caseFallback() {
        let items = MaximaCompletion.completions(of: "Integ", maxima: .builtin, worksheet: CompletionIndex())
        #expect(items.contains { $0.name == "integrate" }, "nothing starts with Integ, so the case is ignored")
        let sheet = MaximaCompletion.symbols(in: "Integral: 1;")
        #expect(MaximaCompletion.completions(of: "Integ", maxima: .builtin, worksheet: sheet).map(\.name) == ["Integral"])
    }

    @Test func showTemplate() {
        let items = MaximaCompletion.completions(of: "integrate", maxima: .builtin, worksheet: CompletionIndex(),
                                                 templatesOnly: true)
        #expect(items.map(\.insertion) == ["integrate(<expr>, <x>)", "integrate(<expr>, <x>, <a>, <b>)"])
        let partial = MaximaCompletion.completions(of: "makel", maxima: .builtin, worksheet: CompletionIndex(),
                                                   templatesOnly: true)
        #expect(partial.allSatisfy { $0.template != nil } && partial.contains { $0.name == "makelist" })
    }

    @Test func placeholders() {
        let text = "integrate(<expr>, <x>, <a>, <b>)"
        let found = MaximaCompletion.placeholders(in: text).map { (text as NSString).substring(with: $0) }
        #expect(found == ["<expr>", "<x>", "<a>", "<b>"])
        #expect(MaximaCompletion.placeholders(in: "is(a<b>c)").isEmpty, "a comparison is no placeholder")
        #expect(MaximaCompletion.placeholders(in: "print(\"<x>\") /* <y> */").isEmpty)
        #expect(MaximaCompletion.placeholders(in: "plot2d(<plot>, <x_range>, <[options]>)").count == 3)
    }

    @Test func tabOrder() {
        let text = "f(<a>, <b>) + g(<c>)"
        func next(_ at: NSRange, back: Bool = false) -> String? {
            MaximaCompletion.nextPlaceholder(in: text, after: at, backwards: back).map { (text as NSString).substring(with: $0) }
        }
        #expect(next(NSRange(location: 0, length: 0)) == "<a>")
        #expect(next(NSRange(location: 2, length: 3)) == "<b>", "from a selected placeholder to the next")
        #expect(next(NSRange(location: 16, length: 3)) == "<a>", "wraps round")
        #expect(next(NSRange(location: 7, length: 3), back: true) == "<a>")
        #expect(next(NSRange(location: 2, length: 3), back: true) == "<c>", "wraps round backwards")
        #expect(MaximaCompletion.nextPlaceholder(in: "x + 1", after: NSRange(location: 0, length: 0)) == nil)
        let one = NSRange(location: 2, length: 3)
        #expect(MaximaCompletion.nextPlaceholder(in: "f(<a>)", after: one) == one, "the only one stays selected")
        #expect(MaximaCompletion.nextPlaceholder(in: "f(<a>)", after: one, backwards: true) == one)
    }
}
