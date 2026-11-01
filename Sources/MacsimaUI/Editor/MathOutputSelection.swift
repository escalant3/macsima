// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WorksheetKit
import WXMLKit

/// A selected output, or a selected part of a math output: which output,
/// and which part of it (MathLayout.select, MathNavigation). The output's
/// content is kept, so a selection whose output changed (the cell ran
/// again) is dropped rather than copied wrong.
public struct MathOutputSelection: Equatable {
    public let cell: UUID
    /// The output's place among the cell's outputs.
    public let output: Int
    /// The math's XML, or a message's text.
    let xml: String
    /// The part of a math output; nil for a whole message (text or error).
    public var part: MathSelection?
}

extension WorksheetController {
    /// The part selected in this output, if any.
    func mathSelection(cell: UUID, output: Int, xml: String) -> MathSelection? {
        guard let s = mathSelection, s.cell == cell, s.output == output, s.xml == xml else { return nil }
        return s.part
    }

    /// Whether this message (text or error) is the selected output.
    func isSelectedMessage(cell: UUID, output: Int, text: String) -> Bool {
        guard let s = mathSelection else { return false }
        return s.cell == cell && s.output == output && s.xml == text && s.part == nil
    }

    /// Selects part of an output (nil: nothing). The selection responder
    /// takes the keyboard, so Copy, Escape and the arrow keys apply to it.
    func selectMath(_ part: MathSelection?, cell: UUID, output: Int, xml: String) {
        guard let part else {
            if mathSelection?.cell == cell, mathSelection?.output == output { clearMathSelection() }
            return
        }
        select(MathOutputSelection(cell: cell, output: output, xml: xml, part: part))
    }

    private func select(_ new: MathOutputSelection, keepAnchor: Bool = false) {
        clearCellSelection()
        if !keepAnchor { outputAnchor = nil }
        if mathSelection != new { mathSelection = new }
        if let window, let responder = selectionResponder, window.firstResponder !== responder {
            window.makeFirstResponder(responder)
        }
    }

    /// VoiceOver says what the keyboard selected, as Maxima input.
    private func announce(_ s: MathOutputSelection) {
        let text: String
        if let part = s.part, let tree = TranslationCache.shared.translate(s.xml).tree {
            text = MaximaInputText.of(tree.node(of: part)).trimmingCharacters(in: .whitespaces)
        } else {
            text = s.xml
        }
        guard let window, !text.isEmpty else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func clearMathSelection() {
        outputAnchor = nil
        if mathSelection != nil { mathSelection = nil }
    }

    /// Back to editing the cell the output belongs to.
    func endMathSelection(caret: CaretPlace = .end) {
        let cell = mathSelection?.cell
        clearMathSelection()
        if let cell, document.worksheet[cell]?.hasEditor == true { focus(cell, caret: caret) }
    }

    func copyMathSelection(as kind: OutputCopy.Kind) {
        guard let s = mathSelection, current(s) else { return }
        if s.part == nil {
            OutputCopy.copy(s.xml)
        } else {
            OutputCopy.copy(s.xml, part: s.part, as: kind, scale: scale)
        }
    }

    /// Whether the selected output is still there, unchanged.
    private func current(_ s: MathOutputSelection) -> Bool {
        guard let outputs = document.worksheet[s.cell]?.outputs, outputs.indices.contains(s.output) else { return false }
        return Self.stop(outputs[s.output])?.content == s.xml
    }

    // MARK: - The keyboard

    /// What the arrow keys stop on: math outputs, printed text and error
    /// messages, as wxMaxima's results. Plots and questions are passed over.
    /// The content a selection keeps, and whether it is math.
    static func stop(_ output: Output) -> (content: String, isMath: Bool)? {
        switch output {
        case .math(let xml):
            let out = TranslationCache.shared.translate(xml)
            return out.tree != nil && !out.mathML.isEmpty ? (xml, true) : nil
        case .text(let text): return text.isEmpty ? nil : (text, false)
        case .error(_, let message): return message.isEmpty ? nil : (message, false)
        default: return nil
        }
    }

    /// The outputs of a cell the arrow keys stop on, by place.
    func stops(in id: UUID) -> [Int] {
        guard let cell = document.worksheet[id], !cell.isHidden, isVisible(id) else { return [] }
        return cell.outputs.indices.filter { Self.stop(cell.outputs[$0]) != nil }
    }

    /// Selects a whole output: a math output's whole expression, or a message.
    @discardableResult
    func selectStop(cell: UUID, output: Int) -> Bool {
        guard let outputs = document.worksheet[cell]?.outputs, outputs.indices.contains(output),
              let (content, isMath) = Self.stop(outputs[output]) else { return false }
        let part = isMath ? MathNavigation(TranslationCache.shared.translate(content))?.whole : nil
        if isMath, part == nil { return false }
        let new = MathOutputSelection(cell: cell, output: output, xml: content, part: part)
        select(new)
        outputScrollRequest &+= 1
        announce(new)
        return true
    }

    /// Down on an input's last line goes into the cell's first output; Up on
    /// its first line into the last output of the cell above. False: no
    /// output there, or Settings say the arrow keys skip outputs.
    func enterOutputs(from id: UUID, up: Bool) -> Bool {
        guard !AppSettings.arrowKeysSkipOutput else { return false }
        if !up {
            guard let first = stops(in: id).first else { return false }
            return selectStop(cell: id, output: first)
        }
        let cells = document.worksheet.cells
        guard let i = cells.firstIndex(where: { $0.id == id }),
              let previous = cells[..<i].last(where: { isVisible($0.id) }),
              let last = stops(in: previous.id).last else { return false }
        return selectStop(cell: previous.id, output: last)
    }

    /// Up and Down from a selected output: the cell's next or previous
    /// output, else on to the next cell's input or back to this cell's.
    func stepOutput(up: Bool) {
        guard let s = mathSelection else { return }
        let here = stops(in: s.cell)
        if let i = here.firstIndex(of: s.output) {
            let j = up ? i - 1 : i + 1
            if here.indices.contains(j) { selectStop(cell: s.cell, output: here[j]); return }
        }
        if up {
            if document.worksheet[s.cell]?.hasEditor == true {
                endMathSelection(caret: .end)
            } else if !enterOutputs(from: s.cell, up: true) {
                clearMathSelection()
                _ = leave(s.cell, up: true, x: 0)
            }
        } else {
            let cells = document.worksheet.cells
            guard let i = cells.firstIndex(where: { $0.id == s.cell }),
                  let next = cells[(i + 1)...].first(where: { isVisible($0.id) && ($0.hasEditor || !stops(in: $0.id).isEmpty) })
            else { return }
            if next.hasEditor {
                clearMathSelection()
                focus(next.id, caret: .start)
            } else if let first = stops(in: next.id).first {
                selectStop(cell: next.id, output: first)
            }
        }
    }

    /// A key while an output is selected; false leaves it to the responder.
    func handleOutputKey(keyCode: UInt16, shift: Bool) -> Bool {
        guard let s = mathSelection else { return false }
        let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        let escape: UInt16 = 53, returnKey: UInt16 = 36, enter: UInt16 = 76
        guard let part = s.part, let nav = MathNavigation(TranslationCache.shared.translate(s.xml)) else {
            // A message: Up and Down move on, Escape goes back to the input.
            switch keyCode {
            case up, down: stepOutput(up: keyCode == up)
            case escape: endMathSelection()
            default: return keyCode == left || keyCode == right || keyCode == returnKey || keyCode == enter
            }
            return true
        }
        func move(to new: MathSelection, keepAnchor: Bool = false) {
            var next = s
            next.part = new
            select(next, keepAnchor: keepAnchor)
            outputScrollRequest &+= 1
            announce(next)
        }
        let horizontal = keyCode == left || keyCode == right
        let vertical = keyCode == up || keyCode == down
        // In a matrix the arrows go from entry to entry, and Shift grows a block.
        if case .block(_, let rows, let columns) = part, horizontal || vertical, nav.isEntry(part) || shift {
            let dr = keyCode == up ? -1 : keyCode == down ? 1 : 0
            let dc = keyCode == left ? -1 : keyCode == right ? 1 : 0
            if shift {
                if case .entry? = outputAnchor {} else { outputAnchor = .entry(rows.lowerBound, columns.lowerBound) }
                guard case .entry(let r, let c)? = outputAnchor,
                      let new = nav.step(part, rows: dr, columns: dc, anchor: (r, c)) else { return true }
                move(to: new, keepAnchor: true)
            } else if let new = nav.step(part, rows: dr, columns: dc) {
                move(to: new)
            }
            return true
        }
        switch keyCode {
        case escape:
            if let parent = nav.parent(of: part) { move(to: parent) } else { endMathSelection() }
        case returnKey, enter:
            if let first = nav.children(of: part).first { move(to: first) }
        case up, down:
            stepOutput(up: keyCode == up)
        case left, right:
            guard part != nav.whole else { return true }
            if shift {
                if case .part(let a)? = outputAnchor, nav.level(of: part)?.siblings.contains(a) == true {} else {
                    let start: MathSelection = if case .run(_, let first, _) = part { .node(first) } else { part }
                    outputAnchor = .part(start)
                }
                guard case .part(let a)? = outputAnchor else { return true }
                move(to: nav.extend(part, anchor: a, right: keyCode == right), keepAnchor: true)
            } else {
                move(to: nav.neighbour(of: part, right: keyCode == right))
            }
        default:
            return false
        }
        return true
    }
}

/// Where Shift+arrows started growing a selection: a part of a level, or
/// a matrix entry.
enum OutputAnchor {
    case part(MathSelection)
    case entry(Int, Int)
}
