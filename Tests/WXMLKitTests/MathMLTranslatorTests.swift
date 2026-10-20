// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MaximaKit
import Testing
@testable import WXMLKit

enum MathFixtures {
    static let testsDir = URL(filePath: #filePath).deletingLastPathComponent()
    static let transcripts = testsDir.deletingLastPathComponent().appending(path: "Fixtures/transcripts/glue")
    static let snapshots = testsDir.appending(path: "Snapshots")

    static var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: transcripts.path)) ?? [])
            .filter { $0.hasSuffix(".txt") && !$0.hasSuffix(".sent.txt") && !$0.hasSuffix(".stdio.txt") }
            .map { String($0.dropLast(4)) }.sorted()
    }

    /// Every math chunk in a glue fixture: results, question prompts and
    /// the payload of `wxasync` blocks.
    static func chunks(_ name: String) throws -> [String] {
        var scanner = TagScanner()
        let data = try Data(contentsOf: transcripts.appending(path: "\(name).txt"))
        return (scanner.feed(data) + scanner.flush()).compactMap { event in
            switch event {
            case .math(let xml): xml
            case .prompt(let p) where p.contains("<math>"): p
            case .tag("wxasync", let c): c.range(of: "</id>").map { String(c[$0.upperBound...]) }
            default: nil
            }
        }
    }
}

/// True when `xml` parses as XML.
func isWellFormed(_ xml: String) -> Bool {
    XMLParser(data: Data(xml.utf8)).parse()
}

struct MathMLSnapshotTests {
    /// Set MACSIMA_RECORD_SNAPSHOTS=1 to rewrite the snapshot files.
    static let recording = ProcessInfo.processInfo.environment["MACSIMA_RECORD_SNAPSHOTS"] == "1"

    @Test(arguments: MathFixtures.names)
    func snapshot(_ name: String) throws {
        let chunks = try MathFixtures.chunks(name)
        var lines: [String] = []
        for (i, chunk) in chunks.enumerated() {
            let out = MathMLTranslator.translate(chunk)
            #expect(out.wellFormed, "\(name) #\(i + 1) parses")
            #expect(out.unknownTags.isEmpty, "\(name) #\(i + 1) unknown tags: \(out.unknownTags)")
            if !out.mathML.isEmpty { #expect(isWellFormed(out.mathML), "\(name) #\(i + 1) MathML is well formed") }
            lines += [
                "### \(i + 1)", "in:    \(chunk)", "label: \(out.label ?? "-")",
                "image: \(out.imagePaths.isEmpty ? "-" : out.imagePaths.joined(separator: " "))",
                "text:  \(out.plainText)", "out:   \(out.mathML)", "",
            ]
        }
        let text = lines.joined(separator: "\n")
        let file = MathFixtures.snapshots.appending(path: "\(name).txt")
        let existing = try? String(contentsOf: file, encoding: .utf8)
        if Self.recording || existing == nil {
            try text.write(to: file, atomically: true, encoding: .utf8)
            if !Self.recording { Issue.record("recorded a new snapshot for \(name); check it and rerun") }
        } else {
            #expect(existing == text, "snapshot \(name) changed; rerun with MACSIMA_RECORD_SNAPSHOTS=1 if intended")
        }
    }

    @Test func everyFixtureChunkKeepsItsText() throws {
        var total = 0
        for name in MathFixtures.names {
            for chunk in try MathFixtures.chunks(name) {
                total += 1
                let out = MathMLTranslator.translate(chunk)
                guard let tree = MathXMLParser.parse(chunk) else { Issue.record("no tree: \(chunk)"); continue }
                // Every identifier and number of the input shows up in the output.
                for leaf in leaves(tree) where !leaf.isEmpty {
                    #expect(out.mathML.contains(MathMLTranslator.escape(leaf)) || mapped(leaf),
                            "\(name): \(leaf) missing from \(out.mathML)")
                }
            }
        }
        print("translated \(total) math chunks")
        #expect(total > 80)
    }

    /// Text of mi and mn leaves.
    func leaves(_ node: MathNode) -> [String] {
        if node.name == "mi" || node.name == "mn" {
            return [node.textContent.trimmingCharacters(in: .whitespaces)]
        }
        return node.children.flatMap(leaves)
    }

    /// Leaves the translator maps to other characters.
    func mapped(_ s: String) -> Bool { ["-", ",", "and", ".", "not"].contains(s) }
}

struct MathMLTranslatorTests {
    func ml(_ xml: String) -> String { MathMLTranslator.translate(xml).mathML }

    @Test func labelsAndImages() {
        let out = MathMLTranslator.translate(#"<math><lbl altCopy="%t1">(%t1) </lbl><img lisp="wxxml-tag">/tmp/a.png</img></math>"#)
        #expect(out.label == "%t1")
        #expect(out.imagePaths == ["/tmp/a.png"])
        #expect(out.mathML == "")
    }

    @Test func constructs() {
        #expect(ml("<math><mfrac><mrow><mn>1</mn></mrow><mrow><mn>2</mn></mrow></mfrac></math>")
                == #"<math display="block"><mfrac><mn>1</mn><mn>2</mn></mfrac></math>"#)
        #expect(ml("<math><q><mi>x</mi></q></math>").contains("<mi>x</mi></msqrt>"))
        #expect(ml(#"<math><munder lisp="wxxml-array-no-display-properties"><mrow><mi>x</mi></mrow><mrow><mn>1</mn></mrow></munder></math>"#)
                .contains("<msub><mi>x</mi><mn>1</mn></msub>"))
        #expect(ml(#"<math><sm type="prod"><mrow><mi>k</mi></mrow><mrow><mi>n</mi></mrow><mrow><mi>k</mi></mrow></sm></math>"#)
                .contains("<munderover><mo>&#x220F;</mo>"))
        #expect(ml(#"<math><p print="no"><mfrac line="no"><mrow><mi>n</mi></mrow><mrow><mi>k</mi></mrow></mfrac></p></math>"#)
                .contains(#"<mfrac linethickness="0">"#))
        #expect(ml("<math><mi> and </mi></math>").contains("<mo>and</mo>"))
        #expect(ml("<math><mo>-&gt;</mo></math>").contains("<mo>\u{2192}</mo>"))
        #expect(ml("<math><s>%pi</s></math>").contains("&#x03C0;"))
        #expect(ml("<math><g>%alpha</g></math>").contains("<mi>α</mi>"))
    }

    /// box(), box(expr, name) and box(expr, highlight) as the glue sends them (Maxima 5.50.0).
    @Test func boxes() {
        let inner = #"<msup><mrow><mi lisp="*var-tag*">x</mi></mrow><mn>2</mn></msup>"#
        #expect(ml("<math><mrow><hl>\(inner)</hl></mrow></math>").contains(#"<menclose notation="box"><msup>"#))
        let named = ml(#"<math><mrow><hl boxname="&quot;a label&quot;">"# + inner + "</hl></mrow></math>")
        #expect(named.contains(#"<mover><menclose notation="box">"#) && named.contains(">a label</mtext></mover>"),
                "the name above the box, without its quotes: \(named)")
        #expect(ml(#"<math><mrow><hl boxname="a&lt;b">"# + inner + "</hl></mrow></math>").contains(">a&lt;b</mtext>"))
        let highlight = ml(#"<math><mrow><hl boxname="highlight"><mi>b</mi><mo>+</mo><mi>a</mi></hl></mrow></math>"#)
        #expect(highlight.contains(##"<mstyle mathcolor="#d00">"##) && !highlight.contains("menclose"),
                "highlight colours, without a box: \(highlight)")
    }

    /// Fixes for WebKit's MathML layout, chosen with `macsima-render lab` (Phase 2, step 3b).
    @Test func webKitLayoutWorkarounds() {
        // Parens around short content do not stretch (WebKit raises them); around fractions they do.
        #expect(ml("<math><fn><fnm>cos</fnm><mrow><p><mi>x</mi></p></mrow></fn></math>")
                .contains(#"<mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo>"#))
        #expect(ml("<math><p><mfrac><mrow><mi>x</mi></mrow><mrow><mn>2</mn></mrow></mfrac></p></math>")
                .contains("<mo>(</mo><mfrac>"))
        // Lists follow the same rule, and abs too.
        #expect(ml(#"<math><mrow list="true"><t listdelim="true">[</t><mn>1</mn><t listdelim="true">]</t></mrow></math>"#)
                .contains(#"<mo stretchy="false">[</mo>"#))
        #expect(ml("<math><a><mi>x</mi></a></math>").contains(#"<mo stretchy="false">|</mo>"#))
        // Every radical gets the same invisible strut.
        #expect(ml("<math><q><mi>a</mi></q></math>")
                .contains(#"<msqrt><mpadded width="0"><mphantom><mo stretchy="false">(</mo></mphantom></mpadded><mi>a</mi></msqrt>"#))
        // Conjugate is an overline drawn by menclose.
        #expect(ml("<math><cj><mi>z</mi></cj></math>").contains(#"<menclose notation="top"><mi>z</mi></menclose>"#))
    }

    @Test func stringSpacesSurvive() {
        let q = ml(#"<math><st>Is </st><mi>y</mi><st> positive?</st></math>"#)
        #expect(q.contains("<mtext>Is&#xA0;</mtext><mi>y</mi><mtext>&#xA0;positive?</mtext>"))
    }

    @Test func binomialKeepsItsParens() {
        let out = MathMLTranslator.translate(#"<math><p print="no"><mfrac line="no"><mrow><mi>n</mi></mrow><mrow><mi>k</mi></mrow></mfrac></p></math>"#)
        #expect(out.mathML.contains(#"<mo>(</mo><mfrac linethickness="0"><mi>n</mi><mi>k</mi></mfrac><mo>)</mo>"#))
        #expect(out.plainText == "binomial(n,k)")
    }

    @Test func hiddenMultiplication() {
        #expect(ml("<math><mrow><mn>1.5</mn><h>*</h><msup><mn>10</mn><mn>-10</mn></msup></mrow></math>").contains("&#x22C5;"))
        #expect(!ml("<math><mn>2</mn><h>*</h><mi>x</mi></math>").contains("&#x22C5;"))
        // The differential's d sits right against its variable; dx and dy stay apart.
        let denominator = ml(#"<math><mrow><s lisp="wxxml-tag">d</s><h>*</h><mi>x</mi><h>*</h><s lisp="wxxml-tag">d</s><h>*</h><mi>y</mi></mrow></math>"#)
        #expect(denominator == #"<math display="block"><mrow><mi mathvariant="normal">d</mi><mi>x</mi><mspace width="0.17em"/><mi mathvariant="normal">d</mi><mi>y</mi></mrow></math>"#)
    }

    @Test func functionNamedByText() {
        // return(c) as the glue prints it (fixture 33, #10): the name is bare text.
        let out = ml(#"<math><fn lisp="wxxml-function">return<mrow><p><mrow><mi>c</mi></mrow></p></mrow></fn></math>"#)
        #expect(out.hasPrefix(#"<math display="block"><mrow><mi>return</mi><mo>&#x2061;</mo>"#))
    }

    @Test func unknownTagsKeepTheirText() {
        let out = MathMLTranslator.translate("<math><mi>a</mi><gadget><mi>frame</mi></gadget></math>")
        #expect(out.unknownTags == ["gadget"])
        #expect(out.mathML.contains("frame"))
    }

    @Test func malformedXMLKeepsText() {
        let out = MathMLTranslator.translate("<math><mi>x</math>")
        #expect(!out.wellFormed)
        #expect(out.mathML.contains("x"))
    }
}
