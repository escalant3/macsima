// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WorksheetKit
import WXMLKit

/// Whole cells on the pasteboard, in three forms:
/// - a `.wxmx` archive of them (outputs and images included), for Macsima;
/// - `.wxm` text under `text/x-wxmaxima-batch`, the form wxMaxima copies
///   cells in (inputs only);
/// - plain text: labels, inputs and outputs as Maxima input, as wxMaxima's
///   GroupCell::ToString gives them.
/// Pasting reads the archive, else `.wxm` text (from wxMaxima, or typed).
@MainActor
enum CellClipboard {
    static let cellsType = NSPasteboard.PasteboardType("local.macsima.cells")
    static let wxmType = NSPasteboard.PasteboardType("text/x-wxmaxima-batch")

    /// Where copies go: the general pasteboard, or a private one while a
    /// key script or UI test runs, so they leave the user's clipboard alone.
    static var pasteboard = NSPasteboard.general

    static func write(_ cells: [Cell]) {
        pasteboard.clearContents()
        if let archive = try? WXMXWriter.write(Worksheet(cells: cells)) {
            pasteboard.setData(archive, forType: cellsType)
        }
        pasteboard.setString(WXMFormat.cells(cells), forType: wxmType)
        pasteboard.setString(plainText(cells), forType: .string)
    }

    /// True when the pasteboard holds cells (from Macsima or wxMaxima).
    static var hasCells: Bool {
        guard let types = pasteboard.types else { return false }
        if types.contains(cellsType) || types.contains(wxmType) { return true }
        return pasteboard.string(forType: .string).map(WXMFormat.looksLikeWXM) ?? false
    }

    /// The cells on the pasteboard, with new IDs (a cell may be pasted twice).
    static func read() -> [Cell]? {
        var cells: [Cell]?
        if let data = pasteboard.data(forType: cellsType), let result = try? WXMXReader.read(data) {
            cells = result.worksheet.cells
        } else if let text = pasteboard.string(forType: wxmType) ?? pasteboard.string(forType: .string),
                  WXMFormat.looksLikeWXM(text) {
            cells = WXMFormat.read(text).cells
        }
        guard let cells, !cells.isEmpty else { return nil }
        return cells.map { cell in
            var copy = cell
            copy.id = UUID()
            return copy
        }
    }

    static func plainText(_ cells: [Cell]) -> String {
        cells.map { cell -> String in
            var lines: [String] = []
            switch cell.kind {
            case .code:
                lines.append((cell.inputLabel.map { "(%i\($0)) " } ?? "") + cell.input)
                for output in cell.outputs {
                    switch output {
                    case .math(let xml):
                        let out = MathMLTranslator.translate(xml)
                        if !out.plainText.isEmpty { lines.append((out.label.map { "(\($0)) " } ?? "") + out.plainText) }
                    case .text(let t) where !t.isEmpty: lines.append(t)
                    case .error(_, let message): lines.append(message)
                    case .image(_, _, let label, _): lines.append((label.map { "(\($0)) " } ?? "") + "(Graphics)")
                    case .question(let prompt, let answer):
                        lines.append(MathMLTranslator.translate(prompt).plainText + (answer.map { " " + $0 } ?? ""))
                    default: break
                    }
                }
            case .pageBreak, .raw, .image:
                break
            default:
                lines.append(cell.input)
            }
            return lines.joined(separator: "\n")
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
