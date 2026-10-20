// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import WXMLKit

/// On the main actor: the translator is recursive and needs the main thread's stack.
@MainActor
struct LaTeXTranslatorTests {
    nonisolated static let lualatex = "/Library/TeX/texbin/lualatex"

    @Test func displayForms() throws {
        let chunks = try MathFixtures.chunks("31-display-forms")
        let expected: [Int: String] = [
            0: #"\sum_{k = 1}^{\infty} \frac{1}{{k}^{2}}"#,
            2: #"\int f(x)\,\mathrm{d} x"#,
            3: #"\int_{0}^{1} f(x)\,\mathrm{d} x"#,
            4: #"\lim_{x \to 0} \frac{\sin(x)}{x}"#,
            5: #"\lim_{x \to 0^{+}} \frac{1}{x}"#,
            23: #"\begin{bmatrix} \frac{1}{2} & {x}^{2} \\ \sqrt{2} & \pi \end{bmatrix}"#,
        ]
        for (i, want) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(LaTeXTranslator.translate(chunks[i]) == want, "display form #\(i)")
        }
    }

    @Test func boxes() {
        let x2 = #"<msup><mrow><mi lisp="*var-tag*">x</mi></mrow><mn>2</mn></msup>"#
        #expect(LaTeXTranslator.translate("<math><mrow><hl>\(x2)</hl></mrow></math>") == #"\boxed{{x}^{2}}"#)
        #expect(LaTeXTranslator.translate(#"<math><mrow><hl boxname="&quot;a_b&quot;">"# + x2 + "</hl></mrow></math>")
                == #"\overset{\scriptstyle\text{a\_b}}{\boxed{{x}^{2}}}"#)
        #expect(LaTeXTranslator.translate(#"<math><mrow><hl boxname="highlight">"# + x2 + "</hl></mrow></math>") == "{x}^{2}")
    }

    /// The math of the .wxmx fixtures (wxMaxima's own dialect).
    static func wxmxChunks() throws -> [(String, String)] {
        let base = MathFixtures.testsDir.deletingLastPathComponent().appending(path: "Fixtures/wxmx")
        var out: [(String, String)] = []
        for sub in ["wxmaxima-samples", "wxmaxima-written", "macsima-written"] {
            let dir = base.appending(path: sub)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".wxmx") {
                guard let r = try? WXMXReader.read(try Data(contentsOf: dir.appending(path: name))) else { continue }
                for cell in r.worksheet.cells {
                    for output in cell.outputs {
                        if case .math(let m) = output { out.append((name, m)) }
                    }
                }
            }
        }
        return out
    }

    /// Every math output of every glue and .wxmx fixture compiles (LuaLaTeX:
    /// the samples hold Cyrillic letters, which pdflatex needs extra fonts for).
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: lualatex)))
    func everyFixtureOutputCompiles() throws {
        var body = ""
        var count = 0
        for name in MathFixtures.names {
            for (i, chunk) in try MathFixtures.chunks(name).enumerated() {
                guard let tex = LaTeXTranslator.translate(chunk), !tex.isEmpty else { continue }
                body += "% \(name) #\(i + 1)\n\\[ \(tex) \\]\n"
                count += 1
            }
        }
        for (i, (name, chunk)) in try Self.wxmxChunks().enumerated() {
            guard let tex = LaTeXTranslator.translate(chunk), !tex.isEmpty else { continue }
            body += "% \(name) (\(i))\n\\[ \(tex) \\]\n"
            count += 1
        }
        #expect(count > 600)
        let dir = FileManager.default.temporaryDirectory.appending(path: "macsima-latex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = "\\documentclass{article}\n\\usepackage{amsmath,amssymb}\n"
            + "\\begin{document}\n\(body)\\end{document}\n"
        try doc.write(to: dir.appending(path: "all.tex"), atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(filePath: Self.lualatex)
        p.arguments = ["-interaction=nonstopmode", "-halt-on-error", "all.tex"]
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        let log = (try? String(contentsOf: dir.appending(path: "all.log"), encoding: .utf8)) ?? ""
        let errors = log.split(separator: "\n").filter { $0.hasPrefix("!") }.prefix(5)
        if let keep = ProcessInfo.processInfo.environment["MACSIMA_KEEP_LATEX"] {
            try? FileManager.default.removeItem(at: URL(filePath: keep))
            try? FileManager.default.copyItem(at: dir.appending(path: "all.pdf"), to: URL(filePath: keep))
            try? doc.write(to: URL(filePath: keep).deletingPathExtension().appendingPathExtension("tex"), atomically: true, encoding: .utf8)
        }
        #expect(p.terminationStatus == 0, "lualatex: \(errors.joined(separator: "; "))")
    }
}
