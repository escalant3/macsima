// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WXMLKit

/// A selected part of one math output: which output, and which part of it
/// (MathLayout.select). The output's XML is kept, so a selection whose
/// output changed (the cell ran again) is dropped rather than copied wrong.
public struct MathOutputSelection: Equatable {
    public let cell: UUID
    /// The output's place among the cell's outputs.
    public let output: Int
    let xml: String
    public var part: MathSelection
}

extension WorksheetController {
    /// The part selected in this output, if any.
    func mathSelection(cell: UUID, output: Int, xml: String) -> MathSelection? {
        guard let s = mathSelection, s.cell == cell, s.output == output, s.xml == xml else { return nil }
        return s.part
    }

    /// Selects part of an output (nil: nothing). The selection responder
    /// takes the keyboard, so Copy and Escape apply to it.
    func selectMath(_ part: MathSelection?, cell: UUID, output: Int, xml: String) {
        guard let part else {
            if mathSelection?.cell == cell, mathSelection?.output == output { clearMathSelection() }
            return
        }
        clearCellSelection()
        let new = MathOutputSelection(cell: cell, output: output, xml: xml, part: part)
        if mathSelection != new { mathSelection = new }
        if let window, let responder = selectionResponder, window.firstResponder !== responder {
            window.makeFirstResponder(responder)
        }
    }

    func clearMathSelection() {
        if mathSelection != nil { mathSelection = nil }
    }

    /// Escape: back to editing the cell the output belongs to.
    func endMathSelection() {
        let cell = mathSelection?.cell
        clearMathSelection()
        if let cell, document.worksheet[cell]?.hasEditor == true { focus(cell, caret: .end) }
    }

    func copyMathSelection(as kind: OutputCopy.Kind) {
        guard let s = mathSelection, current(s) else { return }
        OutputCopy.copy(s.xml, part: s.part, as: kind, scale: scale)
    }

    /// Whether the selected output is still there, unchanged.
    private func current(_ s: MathOutputSelection) -> Bool {
        guard let outputs = document.worksheet[s.cell]?.outputs, outputs.indices.contains(s.output) else { return false }
        switch outputs[s.output] {
        case .math(let xml): return xml == s.xml
        case .question(let prompt, _): return prompt == s.xml
        default: return false
        }
    }
}
