// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit
import SwiftUI
import WorksheetKit

/// The editor of one cell: a plain-text NSTextView on TextKit 2, sized to its
/// text. It is not inside a scroll view of its own; the worksheet scrolls.
final class CellTextView: NSTextView {
    /// Shift+Return.
    var onEvaluate: (() -> Void)?
    /// The view became first responder (a click, Tab, or a focus request).
    var onFocus: (() -> Void)?
    /// Set when the controller asked for this cell's focus before the view
    /// was in a window (a lazy cell scrolled into view): taken on arrival.
    var wantsFocus = false
    /// Up on the first line or Down on the last: leave for the neighbouring
    /// cell, keeping the caret's x position (view coordinates).
    /// Returns false when there is no cell that way.
    var onLeave: ((_ up: Bool, _ x: CGFloat) -> Bool)?
    /// Where to put the caret once the focus arrives (a caret request).
    var pendingCaret: CaretPlace?
    /// Every change to the text (typing, undo, Replace, sync): writes the model.
    var onTextChange: ((String) -> Void)?
    /// The document's undo manager, also while the view is off screen.
    var undoSource: (() -> UndoManager?)?
    /// The last focus and caret requests this view acted on.
    var seenFocusRequest: Int?
    var seenCaretRequest: Int?
    /// Colours the text as Maxima code (code cells only).
    var highlightsSyntax = false {
        didSet { if highlightsSyntax != oldValue { rehighlight() } }
    }

    /// Space around the text; the 5 pt line padding comes on top.
    static let inset = NSSize(width: 0, height: 2)

    init() {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.textContainer = container
        storage.addTextLayoutManager(layout)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 20), textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainerInset = Self.inset
        textColor = .textColor
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        smartInsertDeleteEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(symbolsChanged),
                                               name: MaximaSymbols.didChange, object: nil)
        // Every change to the characters, typing or not: undo and redo
        // change the storage without calling didChangeText.
        NotificationCenter.default.addObserver(self, selector: #selector(storageEdited(_:)),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    @objc private func storageEdited(_ notification: Notification) {
        guard let storage = textStorage, storage.editedMask.contains(.editedCharacters) else { return }
        onTextChange?(storage.string)
        // After the edit is done: the layout follows the storage.
        DispatchQueue.main.async { [weak self] in
            self?.rehighlight()
            self?.invalidateIntrinsicContentSize()
        }
    }

    @objc private func symbolsChanged() { rehighlight() }

    func rehighlight() {
        SyntaxHighlighter.apply(to: self, enabled: highlightsSyntax)
        updateBracketMatch()
    }

    /// Find's matches in this cell, shown with a background.
    var findMarks: [NSRange] = [] {
        didSet { if findMarks != oldValue { updateBracketMatch() } }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateBracketMatch()
    }

    /// Redraws the backgrounds: Find's matches, then the bracket next to the
    /// caret and its partner (code cells, no selection).
    private func updateBracketMatch() {
        guard let layout = textLayoutManager else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        let length = (string as NSString).length
        for mark in findMarks where NSMaxRange(mark) <= length {
            if let range = textRange(mark) {
                layout.addRenderingAttribute(.backgroundColor, value: Self.findColor, for: range)
            }
        }
        let selection = selectedRange()
        guard highlightsSyntax, selection.length == 0,
              let (a, b) = MaximaTokenizer.matchingBracket(in: string, caret: selection.location) else { return }
        for offset in [a, b] {
            if let range = textRange(NSRange(location: offset, length: 1)) {
                layout.addRenderingAttribute(.backgroundColor, value: Self.bracketColor, for: range)
            }
        }
    }

    static let findColor = NSColor(name: "MacsimaFindMatch") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemOrange.withAlphaComponent(0.35) : NSColor.systemOrange.withAlphaComponent(0.3)
    }

    static let bracketColor = NSColor(name: "MacsimaBracketMatch") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemYellow.withAlphaComponent(0.35) : NSColor.systemYellow.withAlphaComponent(0.45)
    }

    /// The TextKit 2 range for UTF-16 offsets.
    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let from = content.location(layout.documentRange.location, offsetBy: range.location),
              let to = content.location(from, offsetBy: range.length) else { return nil }
        return NSTextRange(location: from, end: to)
    }

    override func didChangeText() {
        super.didChangeText()
        rehighlight()
        invalidateIntrinsicContentSize()
    }

    override var undoManager: UndoManager? { undoSource?() ?? super.undoManager }

    /// Takes the model's text when it changed without this view (a file
    /// revert, say). The view's own undo actions no longer fit the text, so
    /// they go: undoing them would garble it.
    func sync(_ text: String) {
        guard string != text, !hasMarkedText() else { return }
        if let storage = textStorage { undoManager?.removeAllActions(withTarget: storage) }
        string = text
        rehighlight()
        invalidateIntrinsicContentSize()
    }

    /// Replaces `range` the way typing does, so it is undone the same way.
    func replace(_ range: NSRange, with text: String) {
        guard NSMaxRange(range) <= (string as NSString).length,
              shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    /// The height the text needs at `width`.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let layout = textLayoutManager, let container = textContainer else { return 20 }
        let textWidth = max(1, width - 2 * textContainerInset.width)
        if container.size.width != textWidth {
            container.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: layout.documentRange)
        var height = layout.usageBoundsForTextContainer.height
        // An empty editor, or one ending in a newline, still shows a line there.
        let font = font ?? .systemFont(ofSize: 14)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        if string.isEmpty { height = lineHeight }
        return ceil(max(height, lineHeight) + 2 * textContainerInset.height)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfWanted()
    }

    func takeFocusIfWanted() {
        guard wantsFocus, let window else { return }
        wantsFocus = false
        if window.firstResponder !== self { window.makeFirstResponder(self) }
        applyPendingCaret()
    }

    func applyPendingCaret() {
        guard let place = pendingCaret, window != nil else { return }
        pendingCaret = nil
        let length = (string as NSString).length
        let range: NSRange
        switch place {
        case .start: range = NSRange(location: 0, length: 0)
        case .end: range = NSRange(location: length, length: 0)
        case .firstLine(let x): range = NSRange(location: offset(atX: x, firstLine: true), length: 0)
        case .lastLine(let x): range = NSRange(location: offset(atX: x, firstLine: false), length: 0)
        case .range(let r): range = NSMaxRange(r) <= length ? r : NSRange(location: length, length: 0)
        }
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    // MARK: - Moving between cells

    /// The caret's rectangle at `offset`, in view coordinates.
    func caretRect(at offset: Int) -> CGRect? {
        guard let layout = textLayoutManager, let range = textRange(NSRange(location: offset, length: 0)) else { return nil }
        layout.ensureLayout(for: layout.documentRange)
        var rect: CGRect?
        layout.enumerateTextSegments(in: range, type: .selection, options: .rangeNotRequired) { _, segment, _, _ in
            rect = segment
            return false
        }
        return rect.map { $0.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y) }
    }

    /// The insertion offset nearest `x` on the first or the last line.
    private func offset(atX x: CGFloat, firstLine: Bool) -> Int {
        let length = (string as NSString).length
        guard let line = caretRect(at: firstLine ? 0 : length) else { return firstLine ? 0 : length }
        return characterIndexForInsertion(at: NSPoint(x: x, y: line.midY))
    }

    override func moveUp(_ sender: Any?) {
        if !leaveIfAtEdge(up: true) { super.moveUp(sender) }
    }

    override func moveDown(_ sender: Any?) {
        if !leaveIfAtEdge(up: false) { super.moveDown(sender) }
    }

    /// With the caret on the first line (up) or the last line (down), hands
    /// the move to the worksheet. Not while a selection is being extended.
    private func leaveIfAtEdge(up: Bool) -> Bool {
        let selection = selectedRange()
        guard let onLeave, selection.length == 0,
              let caret = caretRect(at: selection.location),
              let edge = caretRect(at: up ? 0 : (string as NSString).length) else { return false }
        guard abs(caret.midY - edge.midY) < 1 else { return false }
        return onLeave(up, caret.minX)
    }

    // MARK: - Indentation and comments (code cells)

    /// The current line from its start up to the caret.
    private var lineBeforeCaret: (range: NSRange, text: String) {
        let ns = string as NSString
        let caret = selectedRange().location
        let start = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let range = NSRange(location: start, length: caret - start)
        return (range, ns.substring(with: range))
    }

    /// Return keeps the line's indentation, one level deeper after an open bracket.
    override func insertNewline(_ sender: Any?) {
        guard highlightsSyntax else { return super.insertNewline(sender) }
        let indent = MaximaEditing.indentAfterNewline(line: lineBeforeCaret.text)
        insertText("\n" + indent, replacementRange: selectedRange())
    }

    /// A closing bracket typed on a line of only indentation takes one level off.
    override func insertText(_ text: Any, replacementRange: NSRange) {
        if highlightsSyntax, let typed = text as? String, [")", "]", "}"].contains(typed),
           selectedRange().length == 0, replacementRange.location == NSNotFound {
            let line = lineBeforeCaret
            if let indent = MaximaEditing.indentBeforeClosing(line: line.text) {
                return super.insertText(indent + typed, replacementRange: line.range)
            }
        }
        super.insertText(text, replacementRange: replacementRange)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags == .shift {   // Return, keypad Enter
            onEvaluate?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Hosts a cell's CellTextView in SwiftUI. The view itself comes from the
/// controller, which keeps one per cell for the document's lifetime (see
/// `WorksheetController.editor(for:)`), and writes typing into the model.
struct CellEditor: NSViewRepresentable {
    /// The cell's input in the model, to catch changes made elsewhere.
    let text: String
    let kind: CellKind
    let accessibilityID: String
    /// This cell is the controller's focused cell.
    let isFocused: Bool
    /// Changes with every focus request (`WorksheetController.focusRequest`).
    let focusRequest: Int
    /// The controller's latest caret request, applied once if it is for this cell.
    let caretRequest: CaretRequest?
    let cellID: UUID
    /// The cell's editor, kept by the controller.
    let makeView: () -> CellTextView

    func makeNSView(context: Context) -> CellTextView {
        let view = makeView()
        update(view)
        return view
    }

    func updateNSView(_ view: CellTextView, context: Context) {
        update(view)
    }

    private func update(_ view: CellTextView) {
        view.sync(text)
        let font = Self.font(for: kind)
        if view.font != font { view.font = font }
        view.highlightsSyntax = kind == .code
        view.setAccessibilityIdentifier(accessibilityID)
        // The view outlives this representable, so it remembers which
        // requests it has seen: a cell scrolled back into view doesn't redo them.
        if let request = caretRequest, request.cell == cellID, view.seenCaretRequest != request.serial {
            view.seenCaretRequest = request.serial
            view.pendingCaret = request.place
            if view.window?.firstResponder === view { DispatchQueue.main.async { view.applyPendingCaret() } }
        }
        if view.seenFocusRequest != focusRequest {
            view.seenFocusRequest = focusRequest
            if isFocused {
                view.wantsFocus = true
                // After this update: SwiftUI may still be moving views about.
                DispatchQueue.main.async { view.takeFocusIfWanted() }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CellTextView, context: Context) -> CGSize? {
        var width = proposal.width ?? nsView.frame.width
        if !width.isFinite || width <= 0 { width = 400 }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    static func font(for kind: CellKind) -> NSFont {
        switch kind {
        case .code: .monospacedSystemFont(ofSize: 14, weight: .regular)
        case .title: .systemFont(ofSize: 26, weight: .bold)
        case .section: .systemFont(ofSize: 21, weight: .semibold)
        case .subsection: .systemFont(ofSize: 17, weight: .semibold)
        case .subsubsection, .heading5, .heading6: .systemFont(ofSize: 15, weight: .semibold)
        case .text, .image, .pageBreak, .raw: .systemFont(ofSize: 14)
        }
    }
}

/// Where the caret goes when a cell gets the focus.
public enum CaretPlace: Equatable, Sendable {
    case start, end
    /// On the first or last line, nearest this x (view coordinates).
    case firstLine(x: CGFloat), lastLine(x: CGFloat)
    /// A selection (UTF-16), for Find.
    case range(NSRange)
}

/// A request to place the caret in a cell; `serial` tells repeats apart.
public struct CaretRequest: Equatable, Sendable {
    public var cell: UUID
    public var place: CaretPlace
    public var serial: Int
}
