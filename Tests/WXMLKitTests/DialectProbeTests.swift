// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import WXMLKit

/// The math in .wxmx files: wxMaxima writes its own names for the
/// constructs (r, v, n, f, e, i, fnm operators, ie with pos, ...).
/// On the main actor: some samples nest 155 levels deep (see MathMLTranslator.maxDepth).
@MainActor
struct WXMXMathTests {
    @Test func everyChunkInTheWXMXFixturesTranslates() throws {
        let base = MathFixtures.testsDir.deletingLastPathComponent().appending(path: "Fixtures/wxmx")
        var unknown: [String: Int] = [:]
        var total = 0
        for sub in ["wxmaxima-samples", "wxmaxima-written"] {
            let dir = base.appending(path: sub)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".wxmx") {
                guard let r = try? WXMXReader.read(try Data(contentsOf: dir.appending(path: name))) else { continue }
                for cell in r.worksheet.cells {
                    for output in cell.outputs {
                        let xml: String
                        switch output {
                        case .math(let m), .question(let m, _): xml = m
                        default: continue
                        }
                        total += 1
                        let out = MathMLTranslator.translate(xml)
                        #expect(out.wellFormed, "\(name): \(xml.prefix(200))")
                        if !out.mathML.isEmpty { #expect(isWellFormed(out.mathML), "\(name): MathML of \(xml.prefix(200))") }
                        for tag in out.unknownTags { unknown[tag, default: 0] += 1 }
                    }
                }
            }
        }
        print("translated \(total) chunks from .wxmx fixtures; unknown tags: \(unknown)")
        #expect(total > 600)
        #expect(Set(unknown.keys).isSubset(of: ["slide"]), "only animations are unknown (PARITY.md): \(unknown)")
    }

    func ml(_ xml: String) -> String { MathMLTranslator.translate(xml).mathML }

    @Test func savedDialect() {
        let cos = ml(#"<math><lbl breakline="true" altCopy="(%o1)&#x09;">(%o1) </lbl><fnm>−</fnm><fn><r><fnm>cos</fnm></r><r><p><v>x</v></p></r></fn></math>"#)
        #expect(cos.contains("<mo>−</mo>") && cos.contains("<mi>cos</mi>") && cos.contains("<mi>x</mi>"))
        #expect(ml("<math><f><r><n>1</n></r><r><n>2</n></r></f></math>").contains("<mfrac><mn>1</mn><mn>2</mn></mfrac>"))
        #expect(ml("<math><e><r><v>x</v></r><r><n>2</n></r></e></math>").contains("<msup><mi>x</mi><mn>2</mn></msup>"))
        #expect(ml("<math><i><r><v>x</v></r><r><n>1</n></r></i></math>").contains("<msub><mi>x</mi><mn>1</mn></msub>"))
        let multi = ml(#"<math><ie><r><v>O</v></r><r pos="presub"><v>a</v></r><r pos="postsup"><v>b</v></r></ie></math>"#)
        #expect(multi.contains("<mmultiscripts><mi>O</mi><none/><mi>b</mi><mprescripts/><mi>a</mi><none/></mmultiscripts>"))
        #expect(ml(#"<math><fnm></fnm></math>"#) == "")
        // wxMaxima's labels carry parens and a tab.
        #expect(MathMLTranslator.translate(#"<math><lbl altCopy="(%o3)&#x09;">(%o3) </lbl><n>1</n></math>"#).label == "%o3")
        // wxMaxima saves binomials without their <p>; the parens are drawn anyway, once.
        let saved = ml(#"<math><f line="no"><r><v>n</v></r><r><v>k</v></r></f></math>"#)
        let glue = ml(#"<math><p print="no"><mfrac line="no"><mrow><mi>n</mi></mrow><mrow><mi>k</mi></mrow></mfrac></p></math>"#)
        #expect(saved == glue)
        #expect(saved.components(separatedBy: "<mo>(</mo>").count == 2)
    }

    @Test func matrixBracketsFollowWxMaxima() {
        let cell = "<mtr><mtd><mn>1</mn></mtd></mtr>"
        #expect(ml(#"<math><tb bracketParens="true">\#(cell)</tb></math>"#).contains("<mo>[</mo><mtable>"))
        #expect(ml(#"<math><tb>\#(cell)</tb></math>"#).contains("<mo>(</mo><mtable>"))
        #expect(ml(#"<math><tb roundedParens="false" bracketParens="true">\#(cell)</tb></math>"#).contains("<mo>[</mo>"))
        #expect(ml(#"<math><tb straightParens="true">\#(cell)</tb></math>"#).contains("<mo>|</mo><mtable>"))
        #expect(!ml(#"<math><tb noneParens="true">\#(cell)</tb></math>"#).contains("<mo>"))
    }
}
