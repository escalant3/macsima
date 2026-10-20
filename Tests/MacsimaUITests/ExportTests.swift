// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import MacsimaUI

/// File › Export on the `.wxmx` fixtures: HTML that parses as XML (so its
/// MathML is well formed), LaTeX that LuaLaTeX compiles.
@MainActor
struct ExportTests {
    static let wxmx = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/wxmx")
    nonisolated static let lualatex = "/Library/TeX/texbin/lualatex"

    /// Every readable fixture except the deliberately broken ones.
    static func fixtures() throws -> [(name: String, worksheet: Worksheet)] {
        var all: [(String, Worksheet)] = []
        for folder in ["macsima-written", "wxmaxima-written", "wxmaxima-samples"] {
            let dir = wxmx.appending(path: folder)
            for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            where file.hasSuffix(".wxmx") && !file.hasPrefix("corrupt") {
                all.append(("\(folder)/\(file)", try WXMXReader.read(try Data(contentsOf: dir.appending(path: file))).worksheet))
            }
        }
        return all
    }

    final class ParseCheck: NSObject, XMLParserDelegate {
        var mathCount = 0, imageCount = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "math" { mathCount += 1 }
            if name == "img" { imageCount += 1 }
        }
    }

    @Test func htmlIsWellFormed() throws {
        var maths = 0, images = 0
        for (name, sheet) in try Self.fixtures() {
            let html = WorksheetExport.html(sheet, title: name)
            let parser = XMLParser(data: Data(html.dropFirst("<!DOCTYPE html>\n".count).utf8))
            let check = ParseCheck()
            parser.delegate = check
            #expect(parser.parse(), "\(name): \(String(describing: parser.parserError)) at line \(parser.lineNumber)")
            maths += check.mathCount
            images += check.imageCount
        }
        #expect(maths > 600, "the fixtures' math is in the pages: \(maths)")
        #expect(images > 10, "and their plots and image cells: \(images)")
    }

    @Test func htmlPieces() {
        var text = Cell(kind: .text, input: "bold <and> plain")
        text.textFormats = Array(repeating: TextFormat.bold, count: 4) + Array(repeating: [], count: 12)
        var code = Cell(kind: .code, input: "x^2;")
        code.inputLabel = 1
        code.outputs = [.math(xml: "<math><lbl altCopy=\"%o1\">(%o1) </lbl><e><r><v>x</v></r><r><n>2</n></r></e></math>")]
        let html = WorksheetExport.html(Worksheet(cells: [Cell(kind: .section, input: "Part"), text, code]), title: "t")
        #expect(html.contains("<h2>Part</h2>"))
        #expect(html.contains("<b>bold</b> &lt;and&gt; plain"))
        #expect(html.contains("(%i1)</span><pre class=\"input\">x^2;</pre>"))
        #expect(html.contains("(%o1)</span><div class=\"math\"><math"))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: lualatex)))
    func latexCompiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "macsima-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var failures: [String] = []
        // Four at a time: one LuaLaTeX per document (all at once starved the
        // other tests running alongside).
        var runs: [(name: String, k: Int, tex: String, process: Process)] = []
        for (k, (name, sheet)) in try Self.fixtures().enumerated() {
            let file = WorksheetExport.latex(sheet, imageFolder: "doc\(k)_img")
            let images = dir.appending(path: "doc\(k)_img")
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            for (imageName, data) in file.images { try data.write(to: images.appending(path: imageName)) }
            try file.tex.write(to: dir.appending(path: "doc\(k).tex"), atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(filePath: Self.lualatex)
            p.arguments = ["-interaction=nonstopmode", "-halt-on-error", "doc\(k).tex"]
            p.currentDirectoryURL = dir
            p.standardOutput = FileHandle.nullDevice
            if runs.count >= 4 { runs[runs.count - 4].process.waitUntilExit() }
            try p.run()
            runs.append((name, k, file.tex, p))
        }
        for (name, k, tex, p) in runs {
            p.waitUntilExit()
            guard p.terminationStatus != 0 else { continue }
            if let keep = ProcessInfo.processInfo.environment["MACSIMA_KEEP_LATEX"] {
                try? FileManager.default.createDirectory(atPath: keep, withIntermediateDirectories: true)
                try? tex.write(toFile: keep + "/doc\(k).tex", atomically: true, encoding: .utf8)
            }
            let log = (try? String(contentsOf: dir.appending(path: "doc\(k).log"), encoding: .utf8)) ?? ""
            let errors = log.split(separator: "\n").filter { $0.hasPrefix("!") || $0.hasPrefix("l.") }.prefix(4)
            failures.append("\(name): \(errors.joined(separator: " "))")
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func latexEscapes() {
        #expect(WorksheetExport.texEscape("50% of $x_1 & {y}") == "50\\% of \\$x\\_1 \\& \\{y\\}")
        #expect(WorksheetExport.verbatimSafe("a\\end{verbatim}b") == "a\\end {verbatim}b")
    }
}
