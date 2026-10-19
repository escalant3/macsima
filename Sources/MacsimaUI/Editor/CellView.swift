// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import SwiftUI
import WorksheetKit

/// The worksheet's sizes at its zoom (`scale` 1 = 100%), shared with the
/// math page (`MathHTML`): the label gutter, fonts, and where outputs start.
struct WorksheetMetrics {
    var scale: CGFloat

    /// Width of the label gutter, shared with the label column inside math images.
    var gutterWidth: CGFloat { 52 * scale }
    var gutterSpacing: CGFloat { 14 * scale }
    var gutterFontSize: CGFloat { 12 * scale }
    /// The text view's line padding: fixed, it doesn't zoom.
    static let linePadding: CGFloat = 5
    /// Where outputs start: past the gutter and the text view's line padding.
    var outputIndent: CGFloat { gutterWidth + gutterSpacing + Self.linePadding }
    /// Between a label and its math or image, so they line up with the input.
    var mathGap: CGFloat { gutterSpacing + Self.linePadding }
    var outputFontSize: CGFloat { 13 * scale }
    var answerFontSize: CGFloat { 14 * scale }
}

extension EnvironmentValues {
    /// The worksheet's zoom as a factor (1 = 100%).
    @Entry var worksheetScale: CGFloat = 1
}

/// One cell: its editor with the `(%iN)` gutter, then its outputs.
struct CellView: View {
    let cell: Cell
    /// The cell's position, for accessibility identifiers (`cell-input-N`).
    let index: Int
    let isFocused: Bool
    /// Selected as a whole cell (CellSelection.swift).
    var isSelected = false
    /// A click on the cell's bar or gutter; `extend` when Shift was held.
    var onBarClick: (_ extend: Bool) -> Void = { _ in }
    let focusRequest: Int
    let caretRequest: CaretRequest?
    let makeEditor: () -> CellTextView

    @Environment(\.worksheetScale) private var scale

    var body: some View {
        Group {
            switch cell.kind {
            case .pageBreak:
                PageBreakRow()
                    .contentShape(Rectangle())
                    .onTapGesture { onBarClick(NSEvent.modifierFlags.contains(.shift)) }
            case .raw:
                PlaceholderRow(text: "A cell this app cannot show yet. It is kept and saved back unchanged.",
                               systemImage: "shippingbox")
                    .contentShape(Rectangle())
                    .onTapGesture { onBarClick(NSEvent.modifierFlags.contains(.shift)) }
            default:
                editorCell
            }
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.14))
            }
        }
    }

    private var editorCell: some View {
        let metrics = WorksheetMetrics(scale: scale)
        return VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .top, spacing: metrics.gutterSpacing) {
                Text(gutterLabel)
                    .font(.system(size: metrics.gutterFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.gutterWidth, alignment: .trailing)
                    .padding(.top, Self.gutterOffset(for: cell.kind, scale: scale))
                    // The gutter selects the whole cell, as wxMaxima's bracket does.
                    .frame(maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { onBarClick(NSEvent.modifierFlags.contains(.shift)) }
                    .accessibilityElement()
                    .accessibilityLabel("Select cell")
                    .accessibilityValue(isSelected ? "selected" : "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("cell-bar-\(index)")
                CellEditor(text: cell.input, kind: cell.kind, scale: scale, accessibilityID: "cell-input-\(index)",
                           isFocused: isFocused, focusRequest: focusRequest,
                           caretRequest: caretRequest, cellID: cell.id, makeView: makeEditor)
            }
            .padding(.vertical, 3)
            .padding(.trailing, 6)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFocused || isSelected ? Color.accentColor : failed ? Color.red.opacity(0.7)
                          : Color.secondary.opacity(cell.kind == .code ? 0.25 : 0))
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

    /// The last evaluation ended in an error (wxMaxima draws the cell's bracket red).
    private var failed: Bool {
        cell.outputs.contains { if case .error(let kind, _) = $0 { kind != "interrupted" } else { false } }
    }

    private var gutterLabel: String {
        guard cell.kind == .code else { return "" }
        return cell.inputLabel.map { "(%i\($0))" } ?? "-->"
    }

    /// Moves the gutter label onto the baseline of the editor's first line.
    static func gutterOffset(for kind: CellKind, scale: CGFloat) -> CGFloat {
        let label = NSFont.monospacedSystemFont(ofSize: WorksheetMetrics(scale: scale).gutterFontSize, weight: .regular)
        return CellTextView.inset.height + CellEditor.font(for: kind, scale: scale).ascender - label.ascender
    }
}

/// A page break: a dashed rule across the worksheet, as wxMaxima draws it.
struct PageBreakRow: View {
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        HStack(spacing: 8) {
            rule
            Text("Page break").font(.caption).foregroundStyle(.secondary)
            rule
        }
        .padding(.leading, WorksheetMetrics(scale: scale).outputIndent)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Line().stroke(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// A gray line standing for something the editor does not show.
struct PlaceholderRow: View {
    let text: String
    let systemImage: String
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, WorksheetMetrics(scale: scale).outputIndent)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
