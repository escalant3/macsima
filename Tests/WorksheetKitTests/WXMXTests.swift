// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import ZIPFoundation
@testable import WorksheetKit

enum WXMXFixtures {
    static let dir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/wxmx")
    static func data(_ path: String) throws -> Data { try Data(contentsOf: dir.appending(path: path)) }
}

/// A worksheet with every cell kind and output kind the model has.
func richWorksheet() -> Worksheet {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 7, count: 300))
    return Worksheet(cells: [
        Cell(kind: .title, input: "Title & <stuff>"),
        Cell(kind: .section, input: "Section"),
        Cell(kind: .subsection, input: "Subsection"),
        Cell(kind: .subsubsection, input: "Subsubsection"),
        Cell(kind: .heading5, input: "Heading 5"),
        Cell(kind: .heading6, input: "Heading 6"),
        Cell(kind: .text, input: "Two lines\nof \"text\" with 'quotes'.", extraAttributes: ["hide": "true"]),
        Cell(kind: .code, input: "integrate(sin(x), x);\na: 3$ a^2;", outputs: [
            .math(xml: XMLTree.canonical(#"<math><lbl altCopy="%o1">(%o1) </lbl><mo>-</mo><fn lisp="wxxml-function"><fnm>cos</fnm><mrow><p><mi>x</mi></p></mrow></fn></math>"#)),
            .math(xml: XMLTree.canonical(#"<math>value is <msup><mi>x</mi><mn>2</mn></msup></math>"#)),
            .text("hello\nworld"),
            .error(kind: "maxima", message: "expt: undefined: 0 to a negative exponent.\n -- an error."),
            .error(kind: nil, message: ""),
            .image(data: png, format: "png", label: "%t2", attributes: ["ppi": "144"]),
            .image(data: png + png, format: "png", label: nil),
            .question(prompt: XMLTree.canonical("<math><st>Is </st><mi>y</mi><st> positive?</st></math>"), answer: "pos;"),
            .question(prompt: XMLTree.canonical("<math><st>Is </st><mi>z</mi><st> zero?</st></math>"), answer: nil),
            .math(xml: XMLTree.canonical(#"<math><lbl altCopy="%o4">(%o4) </lbl><tb bracketParens="true"><mtr><mtd><mn>1</mn></mtd></mtr></tb></math>"#)),
        ], inputLabel: 1),
        Cell(kind: .code, input: ""),
        Cell(kind: .pageBreak),
        Cell(kind: .raw, preserved: [#"<cell type="image"><editor type="text"><line>caption</line></editor><img>kept.png</img></cell>"#]),
        Cell(kind: .section, input: "Folded", preserved: [#"<fold><cell type="text"><editor type="text"><line>hidden</line></editor></cell></fold>"#]),
        Cell(kind: .text, input: "bold text", preservedEditor: PreservedEditor(text: "bold text",
             xml: #"<editor type="text"><line bold="1:4">bold text</line></editor>"#)),
    ], preserved: [#"<watchlist><v>x</v></watchlist>"#], zoom: 120,
       extraAttributes: ["activecell": "3", "variables_num": "1", "variables_0": "x"],
       attachments: ["kept.png": png, "data.gnuplot.gz": Data([1, 2, 3])])
}

struct WXMXRoundTripTests {
    @Test func modelFileModelIsIdentical() throws {
        let original = richWorksheet()
        let data = try WXMXWriter.write(original)
        let back = try WXMXReader.read(data)
        #expect(back.worksheet.cells.count == original.cells.count)
        // A kept raw cell without a uuid gets a new ID; everything else is identical.
        var got = back.worksheet
        for (i, cell) in original.cells.enumerated() where cell.kind == .raw { got.cells[i].id = cell.id }
        for (a, b) in zip(original.cells, got.cells) {
            #expect(a == b, "cell \(a.kind) differs:\n\(a)\nvs\n\(b)")
        }
        #expect(got == original)
    }

    @Test func writingTwiceGivesTheSameContent() throws {
        let once = try WXMXReader.read(try WXMXWriter.write(richWorksheet())).worksheet
        #expect(WXMXWriter.contentXML(once) == WXMXWriter.contentXML(try WXMXReader.read(try WXMXWriter.write(once)).worksheet))
    }

    @Test func archiveLayoutMatchesWxMaxima() throws {
        let data = try WXMXWriter.write(richWorksheet())
        let archive = try Archive(data: data, accessMode: .read)
        let entries = Array(archive)
        #expect(entries.prefix(3).map(\.path) == ["mimetype", "format.txt", "content.xml"])
        #expect(entries.allSatisfy { $0.compressedSize == $0.uncompressedSize }, "everything stored")
        #expect(Set(entries.map(\.path)).isSuperset(of: ["image1.png", "image2.png", "kept.png", "data.gnuplot.gz"]))
        var mime = Data()
        _ = try archive.extract(entries[0]) { mime.append($0) }
        #expect(String(decoding: mime, as: UTF8.self) == "text/x-wxmathml")
        let xml = WXMXWriter.contentXML(richWorksheet())
        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<wxMaximaDocument version=\"1.5\" zoom=\"120\" activecell=\"3\""))
        #expect(xml.contains("type=\"subsection\" sectioning_level=\"4\""))
        #expect(xml.contains("<line>integrate(sin(x), x);&#x0A;a: 3$ a^2;</line>"))
        #expect(xml.contains("<st breakline=\"true\">Is </st><mi>y</mi><st> positive?</st><editor type=\"input\">\n<line>pos;</line>"))
    }

    @Test func imageNamesAvoidAttachments() throws {
        var w = Worksheet(cells: [Cell(kind: .code, outputs: [.image(data: Data([1]), format: "png", label: nil)])])
        w.attachments["image1.png"] = Data([9])
        let back = try WXMXReader.read(try WXMXWriter.write(w)).worksheet
        #expect(back.attachments["image1.png"] == Data([9]))
        #expect(back.cells[0].outputs == [.image(data: Data([1]), format: "png", label: nil)])
    }
}

struct WXMXReadingTests {
    /// A file the installed wxMaxima 26.09.0 wrote in batch mode.
    @Test func readsWxMaximaWrittenFile() throws {
        let result = try WXMXReader.read(try WXMXFixtures.data("wxmaxima-written/basics.wxmx"))
        let cells = result.worksheet.cells
        #expect(cells.map(\.kind) == [.title, .section, .subsection, .subsubsection, .text,
                                       .code, .code, .code, .code, .code, .code, .code, .pageBreak])
        #expect(cells[0].input == "Reference title")
        #expect(cells[6].input == "a: 3$\na^2;")
        guard case .math(let first) = cells[5].outputs.first else { Issue.record("no math"); return }
        #expect(first.contains("cos"))
        // The plot: a labelled image from the archive, plus the empty %o7.
        guard case .image(let data, let format, let label, let attributes) = cells[10].outputs.first else {
            Issue.record("no image: \(cells[10].outputs)"); return
        }
        #expect(data.count == 31592 && format == "png" && label == "%t7" && attributes["ppi"] == "144")
        #expect(result.worksheet.attachments.isEmpty, "the image is used by the output, not an attachment")
        #expect(cells.allSatisfy { $0.extraAttributes.isEmpty }, "\(cells.map(\.extraAttributes))")
        #expect(Array(result.worksheet.extraAttributes.keys) == ["activecell"])
        #expect(cells[5].inputLabel == 1 && cells[6].inputLabel == 3, "input labels come from the output labels")
        // Saving and reading again keeps everything.
        let again = try WXMXReader.read(try WXMXWriter.write(result.worksheet)).worksheet
        #expect(again == result.worksheet)
    }

    @Test func keepsWhatItDoesNotKnowAndWarns() throws {
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <wxMaximaDocument version="1.9" zoom="100" future="yes">
        <cell type="code" hide="true" newthing="1"><input><editor type="input"><line>1;</line></editor></input><gizmo a="b"/></cell>
        <cell type="hologram"><x/></cell>
        <sidebar>notes</sidebar>
        </wxMaximaDocument>
        """
        let data = try zip(["mimetype": "text/x-wxmathml", "content.xml": content])
        let result = try WXMXReader.read(data)
        let w = result.worksheet
        #expect(w.extraAttributes == ["future": "yes"])
        #expect(w.cells[0].extraAttributes == ["hide": "true", "newthing": "1"])
        #expect(w.cells[0].preserved == [#"<gizmo a="b"/>"#])
        #expect(w.cells[1].kind == .raw)
        #expect(w.preserved == ["<sidebar>notes</sidebar>"])
        #expect(result.warnings.contains { $0.contains("version 1.9") })
        #expect(result.warnings.contains { $0.contains("hologram") })
        let xml = WXMXWriter.contentXML(w)
        for kept in ["future=\"yes\"", "hide=\"true\"", "newthing=\"1\"", #"<gizmo a="b"/>"#, "hologram", "<sidebar>notes</sidebar>"] {
            #expect(xml.contains(kept), "\(kept) written back")
        }
    }

    @Test func untrustedInputIsRejected() throws {
        #expect(throws: WXMXError.notAZipArchive) { try WXMXReader.read(Data("not a zip".utf8)) }
        #expect(throws: WXMXError.missingContent) { try WXMXReader.read(try zip(["mimetype": "text/x-wxmathml"])) }
        #expect(throws: WXMXError.unsafePath("../evil.txt")) {
            try WXMXReader.read(try zip(["content.xml": "<wxMaximaDocument/>", "../evil.txt": "x"]))
        }
        #expect(throws: WXMXError.notAWorksheet("html")) { try WXMXReader.read(try zip(["content.xml": "<html/>"])) }
        #expect(throws: (any Error).self) { try WXMXReader.read(try zip(["content.xml": "<wxMaximaDocument>"])) }

        // A zip bomb: 20 MB of zeros, deflated to a few KB, against a 1 MB cap.
        let zeros = String(repeating: "\0", count: 20 << 20)
        let bomb = try zip(["content.xml": "<wxMaximaDocument/>", "big.bin": zeros], compressed: true)
        #expect(bomb.count < 200_000)
        var limits = WXMXLimits()
        limits.maxEntryBytes = 1 << 20
        #expect(throws: WXMXError.entryTooLarge("big.bin")) { try WXMXReader.read(bomb, limits: limits) }
        limits = WXMXLimits()
        limits.maxTotalBytes = 1 << 20
        #expect(throws: WXMXError.archiveTooLarge) { try WXMXReader.read(bomb, limits: limits) }
        limits = WXMXLimits()
        limits.maxEntries = 1
        #expect(throws: WXMXError.tooManyEntries(2)) { try WXMXReader.read(bomb, limits: limits) }
    }

    func zip(_ files: KeyValuePairs<String, String>, compressed: Bool = false) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        for (name, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: compressed ? .deflate : .none) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return archive.data!
    }
}

/// The sample files from wxMaxima's repository (README in the folder).
struct WXMXSampleTests {
    static let dir = WXMXFixtures.dir.appending(path: "wxmaxima-samples")
    static let readable = ["500", "all-celltypes", "cell-example", "corrupt_hugevars", "image-test", "intervals",
                           "sampleWorksheet", "testbench_errormessages", "testbench_simple", "testbench_simple2",
                           "wxMaximaWindow"]

    @Test(arguments: readable)
    func sampleSurvivesARoundTrip(_ name: String) throws {
        let first = try WXMXReader.read(try Data(contentsOf: Self.dir.appending(path: "\(name).wxmx"))).worksheet
        var second = try WXMXReader.read(try WXMXWriter.write(first)).worksheet
        for (i, cell) in first.cells.enumerated() where cell.kind == .raw { second.cells[i].id = cell.id }
        #expect(second == first)
    }

    @Test(arguments: ["corrupt_garbage", "corrupt_truncated"])
    func corruptSampleIsRejected(_ name: String) throws {
        #expect(throws: WXMXError.notAZipArchive) {
            try WXMXReader.read(try Data(contentsOf: Self.dir.appending(path: "\(name).wxmx")))
        }
    }

    /// wxMaxima keeps an answered question in the output: prompt, then the answer's editor.
    @Test func questionsFromWxMaxima() throws {
        let r = try WXMXReader.read(try Data(contentsOf: Self.dir.appending(path: "all-celltypes.wxmx")))
        let questions = r.worksheet.cells.flatMap(\.outputs).compactMap { o -> String? in
            if case .question(_, let answer) = o { answer } else { nil }
        }
        #expect(questions.contains("y;") && questions.contains("n;"))
    }

    @Test func allCellTypes() throws {
        let r = try WXMXReader.read(try Data(contentsOf: Self.dir.appending(path: "all-celltypes.wxmx")))
        let kinds = Set(r.worksheet.cells.map(\.kind))
        #expect(kinds.isSuperset(of: [.code, .text, .section, .subsection, .subsubsection, .heading5, .heading6, .pageBreak, .raw]))
        #expect(r.warnings.contains { $0.contains("image") })
    }
}
