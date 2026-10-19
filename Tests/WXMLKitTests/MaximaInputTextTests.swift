// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MaximaKit
import Testing
@testable import WXMLKit

struct MaximaInputTextTests {
    func input(_ xml: String) -> String { MathMLTranslator.translate(xml).plainText }

    @Test func displayForms() {
        let chunks = (try? MathFixtures.chunks("31-display-forms")) ?? []
        #expect(chunks.count > 45)
        let expected: [Int: String] = [
            0: "'sum(1/k^2,k,1,inf)",
            1: "'product(k,k,1,n)",
            2: "'integrate(f(x),x)",
            3: "'integrate(f(x),x,0,1)",
            4: "'limit(sin(x)/x,x,0)",
            5: "'limit(1/x,x,0,plus)",
            6: "'diff(f(x),x)",
            8: "'diff(g(x,y),x,1,y,2)",
            9: "at('diff(f(x),x),x=0)",
            10: "box(x^2+1)",
            11: "box(y,\"tag\")",
            12: "x[1]",
            23: "matrix([1/2,x^2],[sqrt(2),%pi])",
            24: "f(x):=x^2",
        ]
        for (i, want) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(input(chunks[i]) == want, "display form #\(i)")
        }
    }

    @Test func exponentsAndDenominatorsThatAreFractionsGetBrackets() {
        #expect(input("<math><msup><mi>x</mi><mfrac><mn>1</mn><mn>3</mn></mfrac></msup></math>") == "x^(1/3)")
        #expect(input("<math><mfrac><mi>a</mi><mrow><mfrac><mi>b</mi><mi>c</mi></mfrac></mrow></mfrac></math>") == "a/(b/c)")
        // A string value is quoted; the same text printed as a message is not.
        #expect(input(#"<math><lbl altCopy="%o1">(%o1) </lbl><st>say "hi"</st></math>"#) == #""say \"hi\"""#)
        #expect(input(#"<math><st>say "hi"</st></math>"#) == #"say "hi""#)
    }

    /// Every output of these fixtures, copied as input and read back by a
    /// real Maxima, equals the output it came from.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/maxima")))
    func readsBackAsTheSameExpression() async throws {
        let scenarios = ["03-expand", "09-solve", "10-matrix", "11-diff", "12-sum", "13-limit", "17-taylor",
                         "18-greek-sqrt", "31-display-forms.glue", "33-long-outputs.glue"]
        let dir = MathFixtures.testsDir.deletingLastPathComponent().appending(path: "Fixtures/transcripts/scenarios")
        let session = MaximaSession()
        try await session.start()
        // Each output is checked right away: later statements change what
        // its names mean (31 defines f after using it).
        var checked = 0
        for name in scenarios {
            let lines = try String(contentsOf: dir.appending(path: "\(name).scn"), encoding: .utf8)
                .split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.hasPrefix("!") && !$0.isEmpty }
            for line in lines {
                var copied: [(label: String, text: String)] = []
                for await event in try await session.evaluate(cellID: name, text: line) {
                    guard case .math(let xml) = event else { continue }
                    let out = MathMLTranslator.translate(xml)
                    if let label = out.label, label.hasPrefix("%o"), !out.plainText.isEmpty {
                        copied.append((label, out.plainText))
                    }
                }
                for c in copied {
                    // A Taylor series is a polynomial once read back.
                    let check = line.hasPrefix("taylor") ? "is(ratdisrep(\(c.label)) = (\(c.text)))" : "is(\(c.label) = (\(c.text)))"
                    var answer = ""
                    for await event in try await session.evaluate(cellID: "check", text: check + ";") {
                        if case .math(let xml) = event { answer += MathMLTranslator.translate(xml).plainText }
                        if case .error(_, let message) = event { answer += "error: \(message)" }
                    }
                    #expect(answer == "true", "\(line) → \(c.text) reads back as something else (\(answer))")
                    checked += 1
                }
            }
        }
        #expect(checked > 60)
        await session.shutdown()
    }
}
