// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import SwiftUI
import WorksheetKit

/// Width of the label gutter, shared with the label column inside math images.
let gutterWidth: CGFloat = 52
let gutterSpacing: CGFloat = 14
/// Where outputs start: past the gutter and the text view's 5 pt line padding.
let outputIndent: CGFloat = gutterWidth + gutterSpacing + 5

/// One cell: its editor with the `(%iN)` gutter, then its outputs.
struct CellView: View {
    let cell: Cell
    /// The cell's position, for accessibility identifiers (`cell-input-N`).
    let index: Int
    @Binding var text: String
    let isFocused: Bool
    let focusRequest: Int
    let caretRequest: CaretRequest?
    let onFocus: () -> Void
    let onEvaluate: () -> Void
    let onLeave: (_ up: Bool, _ x: CGFloat) -> Bool
    let register: (CellTextView) -> Void

    var body: some View {
        switch cell.kind {
        case .pageBreak:
            PlaceholderRow(text: "Page break", systemImage: "rectangle.split.1x2")
        case .raw, .image:
            PlaceholderRow(text: "A cell this app cannot show yet. It is kept and saved back unchanged.",
                           systemImage: "shippingbox")
        default:
            editorCell
        }
    }

    private var editorCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: gutterSpacing) {
                Text(gutterLabel)
                    .font(.system(size: Self.gutterFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: gutterWidth, alignment: .trailing)
                    .padding(.top, Self.gutterOffset(for: cell.kind))
                CellEditor(text: $text, kind: cell.kind, accessibilityID: "cell-input-\(index)",
                           isFocused: isFocused, focusRequest: focusRequest,
                           caretRequest: caretRequest, cellID: cell.id,
                           onFocus: onFocus, onEvaluate: onEvaluate, onLeave: onLeave, register: register)
            }
            .padding(.vertical, 3)
            .padding(.trailing, 6)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFocused ? Color.accentColor : Color.secondary.opacity(cell.kind == .code ? 0.25 : 0))
                    .frame(width: 3)
            }
            ForEach(Array(cell.outputs.enumerated()), id: \.offset) { n, output in
                OutputView(output: output, cellID: cell.id)
                    .accessibilityIdentifier("cell-output-\(index)-\(n)")
            }
            if !cell.preserved.isEmpty {
                PlaceholderRow(text: cell.preserved.contains { $0.hasPrefix("<fold") }
                               ? "Folded cells: kept and saved back, not shown yet."
                               : "Parts of this cell are kept and saved back, not shown.",
                               systemImage: "chevron.right.circle")
            }
        }
    }

    private var gutterLabel: String {
        guard cell.kind == .code else { return "" }
        return cell.inputLabel.map { "(%i\($0))" } ?? "-->"
    }

    static let gutterFontSize: CGFloat = 12

    /// Moves the gutter label onto the baseline of the editor's first line.
    static func gutterOffset(for kind: CellKind) -> CGFloat {
        let label = NSFont.monospacedSystemFont(ofSize: gutterFontSize, weight: .regular)
        return CellTextView.inset.height + CellEditor.font(for: kind).ascender - label.ascender
    }
}

/// A gray line standing for something the editor does not show.
struct PlaceholderRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, outputIndent)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
