// SPDX-License-Identifier: GPL-2.0-or-later
//
// Writes what wxMaxima's Format::ExportToWXMX and GroupCell::ToXML write
// (src/WXMXformat.cpp, src/cells/GroupCell.cpp, src/cells/EditorCell.cpp at
// commit 13e4aee); wxMaxima is Copyright (C) Andrej Vodopivec, Gunter
// Koenigsmann and the wxMaxima developers, GPL-2.0-or-later.

import Foundation

/// Writes `.wxmx` files wxMaxima can open: an uncompressed zip with
/// `mimetype`, `format.txt`, `content.xml`, then the images, in that order.
public enum WXMXWriter {
    public static let mimetype = "text/x-wxmathml"
    public static let version = "1.5"

    public static func write(_ worksheet: Worksheet, generator: String = "Macsima") throws -> Data {
        var state = State(attachmentNames: Set(worksheet.attachments.keys))
        let xml = state.document(worksheet, generator: generator)
        var files: [(name: String, data: Data)] = [
            ("mimetype", Data(mimetype.utf8)),
            ("format.txt", Data(formatText.utf8)),
            ("content.xml", Data(xml.utf8)),
        ]
        files += state.images
        files += worksheet.attachments.keys.sorted().map { ($0, worksheet.attachments[$0]!) }
        return try WXMXFiles.write(files)
    }

    /// content.xml alone (tests and comparisons).
    public static func contentXML(_ worksheet: Worksheet, generator: String = "Macsima") -> String {
        var state = State(attachmentNames: Set(worksheet.attachments.keys))
        return state.document(worksheet, generator: generator)
    }

    static let formatText = """


    This file contains a wxMaxima session in the .wxmx format, written by
    Macsima, a macOS front end for Maxima.
    .wxmx files are .xml-based files contained in a .zip container like .odt
    or .docx files. After changing their name to end in .zip the .xml and the
    bitmap files inside them can be extracted using any .zip file viewer.
    The text in a .wxmx file is not compressed, so version control can track it.

    wxMaxima can be downloaded from https://github.com/wxMaxima-developers/wxmaxima.


    """

    private struct State {
        var images: [(name: String, data: Data)] = []
        let attachmentNames: Set<String>
        var counter = 0

        init(attachmentNames: Set<String>) { self.attachmentNames = attachmentNames }

        mutating func imageName(_ format: String) -> String {
            while true {
                counter += 1
                let name = "image\(counter).\(format)"
                if !attachmentNames.contains(name) { return name }
            }
        }

        mutating func document(_ worksheet: Worksheet, generator: String) -> String {
            var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n<!--   Created using \(generator)   -->\n"
            var attributes = worksheet.extraAttributes
            attributes["version"] = WXMXWriter.version
            attributes["zoom"] = String(worksheet.zoom)
            // wxMaxima writes version and zoom first; the rest in a fixed order.
            out += "\n<wxMaximaDocument version=\"\(WXMXWriter.version)\" zoom=\"\(worksheet.zoom)\""
            for key in attributes.keys.sorted() where key != "version" && key != "zoom" {
                out += " \(key)=\"\(XMLTreeNode.escapeAttribute(attributes[key]!))\""
            }
            out += ">\n"
            out += cells(worksheet, 0..<worksheet.cells.count)
            for xml in worksheet.preserved { out += "\n" + xml + "\n" }
            out += "\n</wxMaximaDocument>"
            return out
        }

        /// The cells in `range`; a folded heading takes its section into a
        /// `<fold>` inside it, as wxMaxima writes it (nested folds included).
        mutating func cells(_ worksheet: Worksheet, _ range: Range<Int>) -> String {
            var out = ""
            var i = range.lowerBound
            while i < range.upperBound {
                let cell = worksheet.cells[i]
                let section = worksheet.foldRange(of: i).clamped(to: range)
                if cell.isFolded, cell.kind.isHeading, !section.isEmpty {
                    out += self.cell(cell, fold: cells(worksheet, section))
                    i = section.upperBound
                } else {
                    out += self.cell(cell)
                    i += 1
                }
            }
            return out
        }

        mutating func cell(_ cell: Cell, fold: String? = nil) -> String {
            if cell.kind == .raw { return "\n" + cell.preserved.joined(separator: "\n") + "\n" }
            var attributes = cell.extraAttributes
            if attributes["uuid"] == nil { attributes["uuid"] = cell.id.uuidString.lowercased() }
            let (type, level) = Self.typeAttributes(cell.kind)
            let outputXML = cell.outputs.map { self.output($0) }.joined()

            var out = "\n<cell uuid=\"\(XMLTreeNode.escapeAttribute(attributes.removeValue(forKey: "uuid")!))\" type=\"\(type)\""
            if let level { out += " sectioning_level=\"\(level)\"" }
            for key in attributes.keys.sorted() {
                out += " \(key)=\"\(XMLTreeNode.escapeAttribute(attributes[key]!))\""
            }
            if cell.kind == .pageBreak { return out + "/>\n" }
            out += ">\n"
            switch cell.kind {
            case .code:
                out += "<input>\n" + editor(cell, type: "input", level: nil) + "</input>"
                if !outputXML.isEmpty { out += "\n<output>\n<mth>" + outputXML + "\n</mth></output>" }
            case .image:
                // The caption, then the image (wxMaxima's ImgCell, breakline first).
                out += editor(cell, type: "input", level: nil) + outputXML
            default:
                out += editor(cell, type: type, level: level)
                if let fold { out += "<fold>" + fold + "</fold>" }
            }
            for xml in cell.preserved { out += xml }
            out += "\n</cell>\n"
            return out
        }

        static func typeAttributes(_ kind: CellKind) -> (String, String?) {
            switch kind {
            case .code: ("code", nil)
            case .text: ("text", nil)
            case .title: ("title", "1")
            case .section: ("section", "2")
            case .subsection: ("subsection", "3")
            // wxMaxima writes the deeper levels as subsections, for older versions.
            case .subsubsection: ("subsection", "4")
            case .heading5: ("subsection", "5")
            case .heading6: ("subsection", "6")
            case .image: ("image", nil)
            case .pageBreak: ("pagebreak", nil)
            case .raw: ("unknown", nil)
            }
        }

        func editor(_ cell: Cell, type: String, level: String?) -> String {
            if let kept = cell.preservedEditor, kept.text == cell.input { return kept.xml + "\n" }
            var head = "<editor type=\"\(type)\""
            if let level { head += " sectioning_level=\"\(level)\"" }
            // One <line>, with newlines as character references (as wxMaxima writes it).
            let text = XMLTreeNode.escapeText(cell.input).replacingOccurrences(of: "\n", with: "&#x0A;")
            return head + ">\n<line>" + text + "</line>\n</editor>\n"
        }

        mutating func output(_ output: Output) -> String {
            switch output {
            case .math(let xml):
                return Self.startLine(xml)
            case .question(let prompt, let answer):
                // As wxMaxima keeps them: the prompt, then the answer in an input editor.
                let text = XMLTreeNode.escapeText(answer ?? "").replacingOccurrences(of: "\n", with: "&#x0A;")
                return Self.startLine(prompt) + "<editor type=\"input\">\n<line>" + text + "</line>\n</editor>\n"
            case .text(let text):
                guard !text.isEmpty else { return "" }
                // wxMaxima's style for Maxima's plain-text output (monospaced).
                return "<t breakline=\"true\" type=\"ASCII-Art\">" + XMLTreeNode.escapeText(text).replacingOccurrences(of: "\n", with: "&#x0A;") + "</t>"
            case .error(let kind, let message):
                var a = "breakline=\"true\""
                if let kind { a += " errorkind=\"\(XMLTreeNode.escapeAttribute(kind))\"" }
                return "<t \(a) type=\"error\">" + XMLTreeNode.escapeText(message).replacingOccurrences(of: "\n", with: "&#x0A;") + "</t>"
            case .image(let data, let format, let label, let attributes):
                let name = imageName(format)
                images.append((name, data))
                var out = ""
                if let label {
                    out += "<lbl altCopy=\"(\(XMLTreeNode.escapeAttribute(label)))&#x09;\" breakline=\"true\">(\(XMLTreeNode.escapeText(label))) </lbl>"
                }
                var a = attributes
                if label == nil { a["breakline"] = "true" }
                out += XMLTreeNode.element(name: "img", attributes: a, children: [.text(name)]).xml
                return out
            case .animation(let frames, let format, let label, let attributes):
                var names = ""
                for frame in frames {
                    let name = imageName(format)
                    images.append((name, frame))
                    names += name + ";"
                }
                var a = attributes
                if label == nil { a["breakline"] = "true" }
                return (label.map(Self.labelXML) ?? "") + XMLTreeNode.element(name: "slide", attributes: a, children: [.text(names)]).xml
            }
        }

        /// The label of an image or animation, as wxMaxima writes it.
        static func labelXML(_ label: String) -> String {
            "<lbl altCopy=\"(\(XMLTreeNode.escapeAttribute(label)))&#x09;\" breakline=\"true\">(\(XMLTreeNode.escapeText(label))) </lbl>"
        }

        /// The math chunk's content with `breakline="true"` on its first
        /// element, so wxMaxima starts a new line there.
        static func startLine(_ xml: String) -> String {
            guard let nodes = try? XMLTree.parseFragment(xml) else { return xml }
            var content = nodes
            if content.count == 1, let name = content[0].name, name == "math" || name == "mth" {
                content = content[0].children
            }
            content = content.filter {
                if case .text(let t) = $0 { !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { true }
            }
            // Text first: no element to mark, so the chunk goes in a nested <mth>.
            if content.first?.name == nil {
                return XMLTreeNode.element(name: "mth", attributes: ["breakline": "true"], children: content).xml
            }
            var a = content[0].attributes
            a["breakline"] = "true"
            content[0] = content[0].with(attributes: a)
            return content.map(\.xml).joined()
        }
    }
}
