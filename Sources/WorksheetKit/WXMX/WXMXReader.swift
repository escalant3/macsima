// SPDX-License-Identifier: GPL-2.0-or-later
//
// The layout and element names follow wxMaxima's own writer and reader
// (src/WXMXformat.cpp, src/cells/GroupCell.cpp, src/cells/EditorCell.cpp,
// src/MathParser.cpp at commit 13e4aee); wxMaxima is Copyright (C) Andrej
// Vodopivec, Gunter Koenigsmann and the wxMaxima developers, GPL-2.0-or-later.

import Foundation

/// What reading a `.wxmx` produced.
public struct WXMXReadResult: Sendable {
    public var worksheet: Worksheet
    /// Things the app keeps but cannot show or edit; shown when the file opens.
    public var warnings: [String]
}

/// Reads `.wxmx` files: a zip with `mimetype`, `format.txt`, `content.xml`
/// and the images. Nothing is dropped: unknown cells, elements, attributes
/// and files are kept in the model and written back on save.
public enum WXMXReader {
    public static let newestKnownVersion = (major: 1, minor: 5)

    public static func read(_ data: Data, limits: WXMXLimits = WXMXLimits()) throws(WXMXError) -> WXMXReadResult {
        let files = try WXMXFiles.read(data, limits: limits)
        guard let content = files.data["content.xml"] else { throw .missingContent }
        var warnings: [String] = []
        if let mime = files.data["mimetype"], String(decoding: mime, as: UTF8.self) != "text/x-wxmathml" {
            warnings.append("The mimetype entry is \"\(String(decoding: mime, as: UTF8.self))\", not text/x-wxmathml.")
        } else if files.data["mimetype"] == nil {
            warnings.append("The archive has no mimetype entry.")
        }
        let root: XMLTreeNode
        do { root = try XMLTree.parse(content) } catch { throw .badXML(error.description) }
        guard root.name == "wxMaximaDocument" else { throw .notAWorksheet(root.name ?? "?") }

        var reader = Reader(files: files)
        var worksheet = Worksheet()
        var docAttributes = root.attributes
        if let version = docAttributes.removeValue(forKey: "version") {
            let parts = version.split(separator: ".").compactMap { Int($0) }
            if parts.count == 2, (parts[0], parts[1]) > newestKnownVersion {
                warnings.append("The file uses format version \(version); this app knows up to 1.5. Unknown parts are kept.")
            }
        }
        if let zoom = docAttributes.removeValue(forKey: "zoom") { worksheet.zoom = Int(zoom) ?? 100 }
        worksheet.extraAttributes = docAttributes

        for child in root.children {
            switch child.name {
            case "cell":
                worksheet.cells.append(reader.cell(child))
            case nil:
                if !child.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    worksheet.preserved.append(child.xml)
                }
            default:
                worksheet.preserved.append(child.xml)
                reader.warn("an unknown <\(child.name!)> element")
            }
        }
        // Files no output uses (images of kept cells, gnuplot data) are kept as they are.
        for name in files.names where !["mimetype", "format.txt", "content.xml"].contains(name)
            && !reader.usedFiles.contains(name) {
            worksheet.attachments[name] = files.data[name]
        }
        warnings += reader.warnings.sorted { $0.key < $1.key }.map { key, count in
            count == 1 ? "Kept \(key)." : "Kept \(key) (\(count) times)."
        }
        return WXMXReadResult(worksheet: worksheet, warnings: warnings)
    }
}

private struct Reader {
    let files: WXMXFiles
    var usedFiles: Set<String> = []
    /// Warning text → how often.
    var warnings: [String: Int] = [:]

    init(files: WXMXFiles) { self.files = files }

    mutating func warn(_ what: String) { warnings[what, default: 0] += 1 }

    /// Attributes of a cell element this app acts on itself.
    static let cellAttributes: Set<String> = ["uuid", "type", "sectioning_level"]

    mutating func cell(_ node: XMLTreeNode) -> Cell {
        var attributes = node.attributes
        let type = attributes["type"] ?? ""
        let level = attributes["sectioning_level"]
        var id = UUID()
        if let uuid = attributes["uuid"], let parsed = UUID(uuidString: uuid), parsed.uuidString.lowercased() == uuid.lowercased() {
            id = parsed
            // wxMaxima writes lowercase; keep the exact spelling if it differs.
            if uuid != parsed.uuidString.lowercased() { attributes["uuid"] = uuid } else { attributes["uuid"] = nil }
        }
        let kind: CellKind?
        switch type {
        case "code": kind = .code
        case "text": kind = .text
        case "title": kind = .title
        case "section": kind = .section
        case "subsection", "subsubsection":
            switch level {
            case "4": kind = .subsubsection
            case "5": kind = .heading5
            case "6": kind = .heading6
            default: kind = type == "subsubsection" ? .subsubsection : .subsection
            }
        case "pagebreak": kind = .pageBreak
        default: kind = nil
        }
        guard let kind, kind != .image else { return raw(node, id: id, why: "a cell of type \"\(type)\" this app cannot show") }

        // sectioning_level is implied by the kind; other attributes are kept.
        attributes["type"] = nil
        attributes["sectioning_level"] = nil
        var cell = Cell(id: id, kind: kind)
        for key in attributes.keys where key != "uuid" {
            if key.hasPrefix("question") || key.hasPrefix("answer") { continue }
            warn("the cell attribute \"\(key)\" (written back, not used)")
        }

        for child in node.children {
            switch child.name {
            case "input":
                for editor in child.elementChildren where editor.name == "editor" { readEditor(editor, into: &cell) }
            case "editor":
                readEditor(child, into: &cell)
            case "output":
                cell.outputs += outputs(child, attributes: &attributes)
            case nil:
                break
            case "fold":
                cell.preserved.append(child.xml)
                warn("folded cells (not shown, written back)")
            default:
                cell.preserved.append(child.xml)
                warn("an unknown <\(child.name!)> element in a cell")
            }
        }
        cell.extraAttributes = attributes
        return cell
    }

    mutating func raw(_ node: XMLTreeNode, id: UUID, why: String) -> Cell {
        warn(why)
        return Cell(id: id, kind: .raw, preserved: [node.xml])
    }

    mutating func readEditor(_ editor: XMLTreeNode, into cell: inout Cell) {
        let lines = editor.elementChildren.filter { $0.name == "line" }
        let text = lines.map(\.textContent).joined(separator: "\n")
        cell.input = text
        let formatted = lines.contains { !$0.attributes.isEmpty }
            || editor.elementChildren.contains { $0.name != "line" }
        if formatted {
            cell.preservedEditor = PreservedEditor(text: text, xml: editor.xml)
            warn("text formatting (kept while the cell's text is unchanged)")
        }
    }

    /// Splits `<output><mth>…</mth></output>` into outputs: a new output
    /// starts at every element marked `breakline="true"`, at every label
    /// (older files mark no line starts), and after a question's answer.
    mutating func outputs(_ output: XMLTreeNode, attributes: inout [String: String]) -> [Output] {
        var result: [Output] = []
        for mth in output.elementChildren {
            guard mth.name == "mth" || mth.name == "math" else {
                result.append(.math(xml: mth.xml))
                warn("an unknown <\(mth.name ?? "?")> element in an output")
                continue
            }
            var chunk: [XMLTreeNode] = []
            for node in mth.children {
                if case .text(let t) = node, t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                if node.attributes["breakline"] == "true" || node.name == "lbl", !chunk.isEmpty {
                    result += outputs(fromChunk: chunk, attributes: &attributes)
                    chunk = []
                }
                chunk.append(node)
                if node.name == "editor" {
                    result += outputs(fromChunk: chunk, attributes: &attributes)
                    chunk = []
                }
            }
            if !chunk.isEmpty { result += outputs(fromChunk: chunk, attributes: &attributes) }
        }
        return result
    }

    mutating func outputs(fromChunk raw: [XMLTreeNode], attributes: inout [String: String]) -> [Output] {
        // The line-start marker belongs to the layout, not to the output.
        var chunk = raw
        if var first = chunk.first?.attributes, first["breakline"] == "true" {
            first["breakline"] = nil
            chunk[0] = chunk[0].with(attributes: first)
        }
        // A chunk that starts with text is written as a nested <mth>.
        if chunk.count == 1, chunk[0].name == "mth", chunk[0].attributes.isEmpty {
            chunk = chunk[0].children
        }
        // Text and errors: a single <t>.
        if chunk.count == 1, chunk[0].name == "t" {
            var a = chunk[0].attributes
            if a["type"] == "error" {
                a["type"] = nil
                let kind = a.removeValue(forKey: "errorkind")
                if a.isEmpty { return [.error(kind: kind, message: chunk[0].textContent)] }
            } else if a == ["type": "ASCII-Art"] {
                // Maxima's plain-text output (display2d:false, tex(), print in 1D), monospaced.
                return [.text(chunk[0].textContent)]
            }
        }
        // Images: <lbl>(%tN) </lbl><img>imageN.png</img>.
        if let imgIndex = chunk.firstIndex(where: { $0.name == "img" }) {
            let img = chunk[imgIndex]
            let file = img.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let others = chunk.enumerated().filter { $0.offset != imgIndex && $0.element.name != "lbl" }
            if others.isEmpty, let data = files.data[file] {
                usedFiles.insert(file)
                let label = chunk.first { $0.name == "lbl" }.map(Self.label)
                var imgAttributes = img.attributes
                imgAttributes["lisp"] = nil
                let format = URL(filePath: file).pathExtension.lowercased()
                return [.image(data: data, format: format.isEmpty ? "png" : format, label: label, attributes: imgAttributes)]
            }
        }
        // Animations: <lbl>(%tN) </lbl><slide>image2.png;image3.png;</slide>.
        if let slideIndex = chunk.firstIndex(where: { $0.name == "slide" }),
           chunk.enumerated().allSatisfy({ $0.offset == slideIndex || $0.element.name == "lbl" }) {
            let slide = chunk[slideIndex]
            let names = slide.textContent.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty, names.allSatisfy({ files.data[$0] != nil }) {
                names.forEach { usedFiles.insert($0) }
                let label = chunk.first { $0.name == "lbl" }.map(Self.label)
                var a = slide.attributes
                a["lisp"] = nil
                let format = URL(filePath: names[0]).pathExtension.lowercased()
                return [.animation(frames: names.map { files.data[$0]! }, format: format.isEmpty ? "png" : format,
                                   label: label, attributes: a)]
            }
        }
        // A question and its answer: the prompt, then <editor type="input">.
        // (Not when a label is in the chunk: then the editor belongs to some
        // other layout, as in wxMaxima's hand-made test benches; kept as math.)
        if let last = chunk.last, last.name == "editor", chunk.count > 1, !chunk.contains(where: { $0.name == "lbl" }) {
            let answer = last.elementChildren.filter { $0.name == "line" }.map(\.textContent).joined(separator: "\n")
            let prompt = "<math>" + chunk.dropLast().map(\.xml).joined() + "</math>"
            return [.question(prompt: prompt, answer: answer.isEmpty ? nil : answer)]
        }
        return [.math(xml: "<math>" + chunk.map(\.xml).joined() + "</math>")]
    }

    /// `(%o3)\t` or `(%o3) ` → `%o3`.
    static func label(_ lbl: XMLTreeNode) -> String {
        let raw = lbl.attributes["altCopy"] ?? lbl.textContent
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "()\t "))
    }
}
