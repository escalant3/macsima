// SPDX-License-Identifier: GPL-2.0-or-later

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
    @Binding var text: String
    var focus: FocusState<UUID?>.Binding
    let isFocused: Bool
    let onEvaluate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // TextEditor reports no text baseline, so the gutter is top-aligned
            // and nudged down to the editor's first line.
            HStack(alignment: .top, spacing: gutterSpacing) {
                Text(gutterLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: gutterWidth, alignment: .trailing)
                    .padding(.top, Self.gutterOffset(for: cell.kind))
                TextEditor(text: $text)
                    .font(Self.font(for: cell.kind))
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 20)
                    .focused(focus, equals: cell.id)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        onEvaluate()
                        return .handled
                    }
            }
            .padding(.vertical, 3)
            .padding(.trailing, 6)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFocused ? Color.accentColor : Color.secondary.opacity(cell.kind == .code ? 0.25 : 0))
                    .frame(width: 3)
            }
            ForEach(Array(cell.outputs.enumerated()), id: \.offset) { _, output in
                OutputView(output: output, cellID: cell.id)
            }
        }
    }

    private var gutterLabel: String {
        guard cell.kind == .code else { return "" }
        return cell.inputLabel.map { "(%i\($0))" } ?? "-->"
    }

    /// Moves the 12 pt gutter label onto the baseline of the editor's first line.
    static func gutterOffset(for kind: CellKind) -> CGFloat { 2 }

    static func font(for kind: CellKind) -> Font {
        switch kind {
        case .code: .system(size: 14, design: .monospaced)
        case .title: .system(size: 26, weight: .bold)
        case .section: .system(size: 21, weight: .semibold)
        case .subsection: .system(size: 17, weight: .semibold)
        case .subsubsection, .heading5, .heading6: .system(size: 15, weight: .semibold)
        case .text, .image, .pageBreak, .raw: .system(size: 14)
        }
    }
}
