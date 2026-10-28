// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit
import UniformTypeIdentifiers
import WorksheetKit
import WXMLKit

/// File › Export: the worksheet as HTML or LaTeX, with its outputs. After
/// wxMaxima's WorksheetExport.cpp in what goes where (headings, text, code
/// with labels, outputs, images in `<name>_img/` for LaTeX), but plainer:
/// HTML is one file with native MathML and the images inside it, LaTeX
/// uses Macsima's own translator. `.mac` is `WXMFormat.mac`.
@MainActor
enum WorksheetExport {
    // MARK: - HTML

    static func html(_ worksheet: Worksheet, title: String) -> String {
        var body = ""
        for cell in worksheet.cells {
            switch cell.kind {
            case .title, .section, .subsection, .subsubsection, .heading5, .heading6:
                let level = cell.kind.headingLevel ?? 6
                body += "<h\(level)>\(formatted(cell, html: true))</h\(level)>\n"
            case .text:
                body += "<div class=\"text\">\(formatted(cell, html: true))</div>\n"
            case .pageBreak:
                body += "<hr class=\"pagebreak\"/>\n"
            case .image:
                body += "<figure>"
                if case .image(let data, let format, _, _)? = cell.outputs.first, let src = dataURI(data, format) {
                    body += "<img src=\"\(src)\" alt=\"\(escape(cell.input))\"/>"
                }
                body += "<figcaption>\(escape(cell.input))</figcaption></figure>\n"
            case .code:
                body += "<div class=\"cell\">\n<div class=\"row\"><span class=\"lbl\">"
                    + (cell.inputLabel.map { "(%i\($0))" } ?? "") + "</span><pre class=\"input\">"
                    + escape(cell.input) + "</pre></div>\n"
                for output in cell.outputs { body += htmlOutput(output) }
                body += "</div>\n"
            case .raw:
                continue
            }
        }
        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8"/>
            <meta name="generator" content="Macsima"/>
            <title>\(escape(title))</title>
            <style>
            \(Self.css)
            </style>
            </head>
            <body>
            \(body)</body>
            </html>

            """
    }

    private static func htmlOutput(_ output: Output) -> String {
        switch output {
        case .math(let xml):
            let out = TranslationCache.shared.translate(xml)
            // A plot's own math chunk is empty: its image is an output of its own.
            guard !out.mathML.isEmpty else { return "" }
            return "<div class=\"row\"><span class=\"lbl\">\(escape(out.label.map { "(\($0))" } ?? ""))</span>"
                + "<div class=\"math\">\(out.mathML)</div></div>\n"
        case .text(let text):
            return text.isEmpty ? "" : "<pre class=\"text\">\(escape(text))</pre>\n"
        case .error(_, let message):
            return "<pre class=\"error\">\(escape(message.isEmpty ? "Error" : message))</pre>\n"
        case .image(let data, let format, let label, _):
            guard let src = dataURI(data, format) else { return "" }
            return "<div class=\"row picture\"><span class=\"lbl\">\(escape(label.map { "(\($0))" } ?? ""))</span>"
                + "<img src=\"\(src)\" alt=\"plot\"/></div>\n"
        case .animation(let frames, let format, let label, _):
            // A page has no player: the first frame, as a still.
            guard let first = frames.first, let src = dataURI(first, format) else { return "" }
            return "<div class=\"row picture\"><span class=\"lbl\">\(escape(label.map { "(\($0))" } ?? ""))</span>"
                + "<img src=\"\(src)\" alt=\"animation, first of \(frames.count) frames\"/></div>\n"
        case .question(let prompt, let answer):
            let out = TranslationCache.shared.translate(prompt)
            return "<div class=\"question\"><div class=\"math\">\(out.mathML)</div>"
                + "<pre class=\"answer\">\(escape(answer ?? ""))</pre></div>\n"
        }
    }

    static let css = """
        body { font: 16px/1.5 -apple-system, "Helvetica Neue", sans-serif; max-width: 52em; margin: 2em auto; padding: 0 1em; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; }
        .cell { margin: 1em 0; }
        .row { display: flex; align-items: baseline; gap: 1em; margin: .3em 0; }
        .row.picture { align-items: flex-start; }
        .lbl { flex: 0 0 4.5em; color: #888; font: 13px ui-monospace, Menlo, monospace; text-align: right; }
        pre { margin: 0; font: 14px/1.4 ui-monospace, Menlo, monospace; white-space: pre-wrap; }
        .text pre, pre.text { color: #444; margin-left: 5.5em; }
        pre.error { color: #c00; margin-left: 5.5em; }
        .math { overflow-x: auto; font-size: 18px; }
        .math math { font-size: 18px; }
        .question { display: flex; align-items: baseline; gap: .6em; margin-left: 5.5em; }
        img { max-width: 100%; }
        figure { margin: 1em 0; text-align: center; }
        hr.pagebreak { border: none; border-top: 1px dashed #aaa; page-break-after: always; }
        @media (prefers-color-scheme: dark) {
          body { background: #1e1e1e; color: #ddd; } .text pre, pre.text { color: #bbb; } pre.error { color: #f66; }
        }
        """

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The image as a data URI; formats a browser can't show (svgz) become PNG.
    static func dataURI(_ data: Data, _ format: String) -> String? {
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml"]
        if let type = types[format.lowercased()] { return "data:\(type);base64," + data.base64EncodedString() }
        guard let png = pngData(data, format) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    static func pngData(_ data: Data, _ format: String) -> Data? {
        guard let image = ImageDecoding.image(data, format: format), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// A text cell's or heading's text with its bold, italic, ... as HTML
    /// or LaTeX. Paragraphs in text cells are kept (blank lines).
    static func formatted(_ cell: Cell, html: Bool) -> String {
        var out = ""
        for (piece, format) in runs(cell.input, cell.textFormats) {
            var text = html ? escape(piece) : texEscape(piece)
            if html {
                text = text.replacingOccurrences(of: "\n", with: "<br/>")
                for (flag, tag) in [(TextFormat.bold, "b"), (.italic, "i"), (.underline, "u"), (.strikethrough, "s"),
                                    (.raised, "sup"), (.lowered, "sub")] where format.contains(flag) {
                    text = "<\(tag)>\(text)</\(tag)>"
                }
            } else {
                text = text.replacingOccurrences(of: "\n\n", with: "\n\n\\noindent ")
                for (flag, command) in [(TextFormat.bold, "\\textbf"), (.italic, "\\textit"), (.underline, "\\underline"),
                                        (.strikethrough, "\\sout"), (.raised, "\\textsuperscript"), (.lowered, "\\textsubscript")]
                where format.contains(flag) {
                    text = "\(command){\(text)}"
                }
            }
            out += text
        }
        return out
    }

    /// Runs of text with one format each.
    static func runs(_ text: String, _ formats: TextFormats) -> [(String, TextFormat)] {
        guard !TextFormatting.isPlain(formats) else { return [(text, [])] }
        var runs: [(String, TextFormat)] = []
        for (i, scalar) in text.unicodeScalars.enumerated() {
            let format = i < formats.count ? formats[i] : []
            if let last = runs.last, last.1 == format {
                runs[runs.count - 1].0.unicodeScalars.append(scalar)
            } else {
                runs.append((String(scalar), format))
            }
        }
        return runs
    }

    // MARK: - LaTeX

    struct LaTeXFile {
        var tex: String
        /// Files for the image folder: name and bytes.
        var images: [(name: String, data: Data)]
    }

    /// `imageFolder` is the folder's name next to the `.tex` (`notes_img`).
    static func latex(_ worksheet: Worksheet, imageFolder: String) -> LaTeXFile {
        var images: [(name: String, data: Data)] = []
        func include(_ data: Data, _ format: String) -> String? {
            let lower = format.lowercased()
            let (bytes, ext): (Data?, String) = ["png", "jpg", "jpeg", "pdf"].contains(lower) ? (data, lower) : (pngData(data, format), "png")
            guard let bytes else { return nil }
            let name = "image\(images.count + 1).\(ext)"
            images.append((name, bytes))
            return "\\includeimage{\(imageFolder)/\(name)}"
        }
        var body = ""
        for cell in worksheet.cells {
            switch cell.kind {
            case .title:
                body += "\\begin{center}\n{\\Huge \(formatted(cell, html: false))}\n\\end{center}\n\n"
            case .section, .subsection, .subsubsection, .heading5, .heading6:
                let command = ["section", "subsection", "subsubsection", "paragraph", "subparagraph"][(cell.kind.headingLevel ?? 2) - 2]
                body += "\\\(command){\(formatted(cell, html: false))}\n\n"
            case .text:
                body += "\\noindent \(formatted(cell, html: false))\n\n"
            case .pageBreak:
                body += "\\pagebreak\n\n"
            case .image:
                if case .image(let data, let format, _, _)? = cell.outputs.first, let line = include(data, format) {
                    body += "\\begin{figure}[htb]\n\\centering\n\(line)\n\\caption{\(texEscape(cell.input))}\n\\end{figure}\n\n"
                }
            case .code:
                let label = cell.inputLabel.map { "(\\%i\($0))" } ?? ""
                body += "\\noindent\n\\begin{minipage}[t]{\\textwidth}\n{\\color{labelcolor}\\ttfamily \(label)}\n"
                    + "\\begin{verbatim}\n\(verbatimSafe(cell.input))\n\\end{verbatim}\n\\end{minipage}\n"
                for output in cell.outputs { body += latexOutput(output, include: include) }
                body += "\n"
            case .raw:
                continue
            }
        }
        let tex = """
            \\documentclass{article}

            %% Created with Macsima

            \\setlength{\\parskip}{\\medskipamount}
            \\setlength{\\parindent}{0pt}
            \\usepackage{iftex}
            \\ifPDFTeX
              \\usepackage[utf8]{inputenc}
              \\usepackage[T1]{fontenc}
            \\else
              \\usepackage{fontspec}
            \\fi
            \\usepackage{graphicx}
            \\usepackage{color}
            \\usepackage[normalem]{ulem}
            \\usepackage[leqno]{amsmath}
            \\usepackage{amssymb}
            \\ifPDFTeX\\else
              \\usepackage{unicode-math}
            \\fi
            \\usepackage{ifthen}
            % As wxMaxima's export: an image as large as it is, at most the line's width.
            \\newsavebox{\\picturebox}
            \\newlength{\\pictureboxwidth}
            \\newlength{\\pictureboxheight}
            \\newcommand{\\includeimage}[1]{
                \\savebox{\\picturebox}{\\includegraphics{#1}}
                \\settoheight{\\pictureboxheight}{\\usebox{\\picturebox}}
                \\settowidth{\\pictureboxwidth}{\\usebox{\\picturebox}}
                \\ifthenelse{\\lengthtest{\\pictureboxwidth > .95\\linewidth}}
                {\\includegraphics[width=.95\\linewidth,height=.80\\textheight,keepaspectratio]{#1}}
                {\\ifthenelse{\\lengthtest{\\pictureboxheight>.80\\textheight}}
                 {\\includegraphics[width=.95\\linewidth,height=.80\\textheight,keepaspectratio]{#1}}
                 {\\includegraphics{#1}}}
            }
            \\DeclareMathOperator{\\abs}{abs}
            \\definecolor{labelcolor}{RGB}{100,0,0}

            \\begin{document}

            \(body)\\end{document}

            """
        return LaTeXFile(tex: tex, images: images)
    }

    private static func latexOutput(_ output: Output, include: (Data, String) -> String?) -> String {
        switch output {
        case .math(let xml):
            let out = TranslationCache.shared.translate(xml)
            guard !out.mathML.isEmpty else { return "" }
            // The label on the left, as Maxima shows it (amsmath's leqno).
            let tag = out.label.map { "\\tag*{\\color{labelcolor}\\ttfamily (\(texEscape($0)))}" } ?? ""
            if let tex = LaTeXTranslator.translate(xml) {
                guard !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
                // No empty line inside: it would end a paragraph in math mode.
                return "\\begin{equation*}\n\(tex)" + (tag.isEmpty ? "" : "\n" + tag) + "\n\\end{equation*}\n"
            }
            return "\\begin{verbatim}\n\(verbatimSafe(out.plainText))\n\\end{verbatim}\n"
        case .text(let text):
            return text.isEmpty ? "" : "\\begin{verbatim}\n\(verbatimSafe(text))\n\\end{verbatim}\n"
        case .error(_, let message):
            return "{\\color{red}\\begin{verbatim}\n\(verbatimSafe(message.isEmpty ? "Error" : message))\n\\end{verbatim}}\n"
        case .image(let data, let format, _, _):
            return include(data, format).map { "\($0)\n\n" } ?? ""
        case .animation(let frames, let format, _, _):
            return frames.first.flatMap { include($0, format) }.map { "\($0)\n\n" } ?? ""
        case .question(let prompt, let answer):
            let text = TranslationCache.shared.translate(prompt).plainText
            return "\\begin{verbatim}\n\(verbatimSafe(text + " " + (answer ?? "")))\n\\end{verbatim}\n"
        }
    }

    static func texEscape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\textbackslash{}"
            case "{", "}", "%", "$", "&", "#", "_": out += "\\\(c)"
            case "^": out += "\\textasciicircum{}"
            case "~": out += "\\textasciitilde{}"
            default: out.append(c)
            }
        }
        return out
    }

    /// verbatim ends at the first `\end{verbatim}`; one inside is broken up.
    static func verbatimSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\\end{verbatim}", with: "\\end {verbatim}")
    }
}

/// What File › Export writes.
public enum ExportKind: String, CaseIterable, Sendable {
    case html, latex, mac

    var title: String {
        switch self {
        case .html: String(localized: "HTML…", comment: "File › Export menu item")
        case .latex: String(localized: "LaTeX…", comment: "File › Export menu item")
        case .mac: String(localized: "Maxima Batch File…", comment: "File › Export menu item")
        }
    }

    var fileExtension: String {
        switch self {
        case .html: "html"
        case .latex: "tex"
        case .mac: "mac"
        }
    }
}

extension WorksheetController {
    /// File › Export: asks where, then writes.
    public func export(_ kind: ExportKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .html ? .html : kind == .mac ? .maximaBatch : UTType(filenameExtension: "tex") ?? .plainText]
        panel.nameFieldStringValue = documentName + "." + kind.fileExtension
        panel.canCreateDirectories = true
        let write = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url, let self else { return }
            self.write(kind, to: url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }

    /// The document's name without extension, for export file names and titles.
    var documentName: String {
        let name = (window?.windowController?.document as? NSDocument)?.displayName ?? String(localized: "Untitled", comment: "Title of an exported worksheet that has no file name")
        return (name as NSString).deletingPathExtension
    }

    func write(_ kind: ExportKind, to url: URL) {
        do {
            switch kind {
            case .html:
                try Data(WorksheetExport.html(document.worksheet, title: url.deletingPathExtension().lastPathComponent).utf8)
                    .write(to: url, options: .atomic)
            case .mac:
                try Data(WXMFormat.mac(document.worksheet).utf8).write(to: url, options: .atomic)
            case .latex:
                // The images go into <name>_img next to the .tex, as wxMaxima does.
                let folderName = url.deletingPathExtension().lastPathComponent + "_img"
                let file = WorksheetExport.latex(document.worksheet, imageFolder: folderName)
                if !file.images.isEmpty {
                    let folder = url.deletingLastPathComponent().appending(path: folderName)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for (name, data) in file.images { try data.write(to: folder.appending(path: name), options: .atomic) }
                }
                try Data(file.tex.utf8).write(to: url, options: .atomic)
            }
            statusMessage = String(localized: "Exported to \(url.lastPathComponent).")
        } catch {
            statusMessage = String(localized: "Could not export: \(error.localizedDescription)")
        }
    }

    /// `wxworksheettohtml("file.html")` in a cell: Maxima asks the front end
    /// to export (the glue's <worksheetexport>). Only HTML is defined; the
    /// options (flavor, wxmx) are not applied: the page is always MathML.
    func handleExportRequest(_ content: String) {
        func field(_ tag: String) -> String? {
            guard let a = content.range(of: "<\(tag)>"), let b = content.range(of: "</\(tag)>", range: a.upperBound..<content.endIndex)
            else { return nil }
            return MaximaHelp.unescape(String(content[a.upperBound..<b.lowerBound]))
        }
        guard let type = field("type"), let path = field("file"), path.hasPrefix("/") else {
            statusMessage = String(localized: "Maxima asked for an export Macsima did not understand.")
            return
        }
        switch type {
        case "html": write(.html, to: URL(filePath: path))
        case "tex": write(.latex, to: URL(filePath: path))
        default: statusMessage = String(localized: "Macsima can't export \(type) yet.")
        }
    }
}
