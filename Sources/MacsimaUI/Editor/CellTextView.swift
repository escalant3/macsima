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
    /// Shift+Up with the selection already at the start (or Shift+Down at
    /// the end): select whole cells from here.
    var onSelectCells: ((_ up: Bool) -> Void)?
    private var hadFocusWhenRemoved = false
    /// The editor left the window while it had the keyboard.
    var onRemovedWhileFocused: (() -> Void)?
    /// A text cell: bold, italic, ... (TextCellFormatting.swift).
    var formatsText = false {
        didSet {
            guard formatsText != oldValue else { return }
            // Rich text keeps per-character formats; paste stays plain (readablePasteboardTypes).
            isRichText = formatsText
        }
    }
    /// A text cell's font without formats, at the worksheet's zoom.
    var baseFont: NSFont?
    /// The formats the storage shows changed (typing, undo, Format menu).
    var onFormatsChange: ((TextFormats) -> Void)?
    /// Set while the model's formats are being applied, which is no change to report.
    var applyingFormats = false
    /// True while this editor's cell is the worksheet's focused cell.
    var isFocusedCell: (() -> Bool)?
    /// Paste when the pasteboard holds cells: inserts them after this cell.
    var onPasteCells: (() -> Bool)?
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
        guard let storage = textStorage else { return }
        // Formats changed by typing, undo or Format › Bold go to the model.
        if formatsText, !applyingFormats { onFormatsChange?(storageFormats()) }
        guard storage.editedMask.contains(.editedCharacters) else { return }
        if window?.firstResponder === self { revealCaretOnGrowth = true }
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

    /// Where the last evaluation failed, shown while the text is unchanged.
    var errorMarks: ErrorMarks? {
        didSet { if errorMarks != oldValue { updateBracketMatch() } }
    }

    /// Find's matches in this cell, shown with a background.
    var findMarks: [NSRange] = [] {
        didSet { if findMarks != oldValue { updateBracketMatch() } }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateBracketMatch()
        // The caret left the word (a click, an arrow key): after typing has
        // settled, the list follows or closes.
        if completion != nil { DispatchQueue.main.async { [weak self] in self?.updateCompletion() } }
    }

    /// Redraws the backgrounds: Find's matches, then the bracket next to the
    /// caret and its partner (code cells, no selection).
    private func updateBracketMatch() {
        guard let layout = textLayoutManager else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        let length = (string as NSString).length
        if let marks = errorMarks, marks.text == string {
            for (ranges, color) in [(marks.statements, Self.errorStatementColor), (marks.spots, Self.errorSpotColor)] {
                for mark in ranges where NSMaxRange(mark) <= length {
                    // An empty range (a bracket missing at the very end) marks the last character.
                    let shown = mark.length > 0 ? mark : NSRange(location: max(0, mark.location - 1), length: min(1, length))
                    if let range = textRange(shown) {
                        layout.addRenderingAttribute(.backgroundColor, value: color, for: range)
                    }
                }
            }
        }
        if highlightsSyntax {
            for mark in MaximaCompletion.placeholders(in: string) {
                if let range = textRange(mark) {
                    layout.addRenderingAttribute(.backgroundColor, value: Self.placeholderColor, for: range)
                }
            }
        }
        for mark in findMarks where NSMaxRange(mark) <= length {
            if let range = textRange(mark) {
                layout.addRenderingAttribute(.backgroundColor, value: Self.findColor, for: range)
            }
        }
        defer { redrawFragments() }
        let selection = selectedRange()
        guard highlightsSyntax, selection.length == 0,
              let (a, b) = MaximaTokenizer.matchingBracket(in: string, caret: selection.location) else { return }
        for offset in [a, b] {
            if let range = textRange(NSRange(location: offset, length: 1)) {
                layout.addRenderingAttribute(.backgroundColor, value: Self.bracketColor, for: range)
            }
        }
    }

    /// wxMaxima's TS_ERROR_STATEMENT and TS_ERROR_SPOT colours (Styles.cpp, 13e4aee).
    static let errorStatementColor = NSColor(name: "MacsimaErrorStatement") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 75 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)
            : NSColor(srgbRed: 1, green: 228 / 255, blue: 228 / 255, alpha: 1)
    }
    static let errorSpotColor = NSColor(name: "MacsimaErrorSpot") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 140 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1)
            : NSColor(srgbRed: 1, green: 170 / 255, blue: 170 / 255, alpha: 1)
    }

    static let findColor = NSColor(name: "MacsimaFindMatch") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemOrange.withAlphaComponent(0.35) : NSColor.systemOrange.withAlphaComponent(0.3)
    }

    /// A template's `<argument>`, which Tab selects.
    static let placeholderColor = NSColor(name: "MacsimaPlaceholder") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemBlue.withAlphaComponent(0.35) : NSColor.systemBlue.withAlphaComponent(0.18)
    }

    static let bracketColor = NSColor(name: "MacsimaBracketMatch") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemYellow.withAlphaComponent(0.35) : NSColor.systemYellow.withAlphaComponent(0.45)
    }

    /// Redraws the text after its rendering attributes changed. TextKit 2
    /// draws the text in subviews of the text view and doesn't redraw them
    /// for rendering attributes alone; the text view's own needsDisplay
    /// doesn't reach them (Find's marks showed only in the cell whose
    /// selection changed).
    func redrawFragments() {
        func mark(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(mark)
        }
        mark(self)
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
        updateCompletion()
    }

    override var undoManager: UndoManager? { undoSource?() ?? super.undoManager }

    /// Plain text only, also in rich text cells: formats come from the Format menu.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

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

    /// Set by an edit while this view has the keyboard. SwiftUI gives the
    /// view its new height only after the edit, when NSTextView has already
    /// scrolled to the caret: a new or wrapped line in a cell at the bottom
    /// of the worksheet stayed below the window. Once grown, scroll again.
    private var revealCaretOnGrowth = false

    override func setFrameSize(_ newSize: NSSize) {
        let grew = newSize.height > frame.height
        super.setFrameSize(newSize)
        guard grew, revealCaretOnGrowth else { return }
        revealCaretOnGrowth = false
        // After this layout pass, when the worksheet has grown too.
        DispatchQueue.main.async { [weak self] in
            guard let self, window?.firstResponder === self else { return }
            revealCaret()
        }
    }

    /// Scrolls the worksheet so the caret's line is above its bottom edge.
    /// NSView's scrollRectToVisible counts the area under the status bar
    /// (the scroll view's bottom inset) as visible, so it can't do this.
    private func revealCaret() {
        guard let scroll = enclosingScrollView, let caret = caretRect(at: selectedRange().location) else { return }
        let clip = scroll.contentView
        let line = clip.convert(caret, from: self).insetBy(dx: 0, dy: -textContainerInset.height)
        let bottom = clip.bounds.maxY - scroll.contentInsets.bottom
        guard line.maxY > bottom else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + line.maxY - bottom))
        scroll.reflectScrolledClipView(clip)
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            closeCompletion()
            revealCaretOnGrowth = false
        }
        return ok
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { closeCompletion() }
        if newWindow == nil, let window, window.firstResponder === self { hadFocusWhenRemoved = true }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfWanted()
        // SwiftUI may move a cached editor to a new host view when the cells
        // above it change (a plot arrives). Leaving the window took the
        // focus away and gave it to the window; take it back, or the next
        // keystrokes go nowhere.
        if let window, window.firstResponder === window, isFocusedCell?() == true {
            window.makeFirstResponder(self)
        }
        // Removed while it had the keyboard (the lazy stack drops cells
        // pushed out of view): the worksheet may bring it back.
        if window == nil, hadFocusWhenRemoved {
            hadFocusWhenRemoved = false
            onRemovedWhileFocused?()
        }
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

    override func moveUpAndModifySelection(_ sender: Any?) {
        if selectedRange().location == 0, let onSelectCells { onSelectCells(true) } else { super.moveUpAndModifySelection(sender) }
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        if NSMaxRange(selectedRange()) == (string as NSString).length, let onSelectCells {
            onSelectCells(false)
        } else {
            super.moveDownAndModifySelection(sender)
        }
    }

    override func paste(_ sender: Any?) {
        if CellClipboard.hasCells, onPasteCells?() == true { return }
        super.paste(sender)
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

    /// Cmd+/: comments out the selected lines, or uncomments them.
    func toggleComment() {
        guard highlightsSyntax else { return }
        let edit = MaximaEditing.toggleComment(in: string, selection: selectedRange())
        breakUndoCoalescing()
        replace(edit.range, with: edit.text)
        undoManager?.setActionName(String(localized: "Comment", comment: "Undo action name"))
        setSelectedRange(edit.selection)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if handleCompletionKey(event) { return }
        if event.keyCode == 53, flags.isEmpty, highlightsSyntax {   // Esc
            return showCompletions(templatesOnly: false)
        }
        if event.keyCode == 36 || event.keyCode == 76, flags == .shift {   // Return, keypad Enter
            closeCompletion()
            onEvaluate?()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Help (code cells)

    /// Look Up in Maxima Manual, from the context menu.
    var onLookUp: ((String) -> Void)?

    /// What F1 looks up: the selection when it is one line, else the name
    /// or operator at the caret.
    var helpTopic: String? {
        let selection = selectedRange()
        if selection.length > 0 {
            let text = (string as NSString).substring(with: selection).trimmingCharacters(in: .whitespaces)
            return text.isEmpty || text.contains("\n") ? nil : text
        }
        return MaximaHelp.topic(in: string, caret: selection.location)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard highlightsSyntax, let menu else { return menu }
        // The click's spot, not the caret, as Look Up does.
        let at = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let selection = selectedRange()
        let topic = selection.length > 0 && NSLocationInRange(at, selection) ? helpTopic : MaximaHelp.topic(in: string, caret: at)
        guard let topic else { return menu }
        let item = NSMenuItem(title: String(localized: "Look Up “\(topic)” in Maxima Manual"), action: #selector(lookUpFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = topic
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func lookUpFromMenu(_ sender: NSMenuItem) {
        if let topic = sender.representedObject as? String { onLookUp?(topic) }
    }

    // MARK: - Completion (code cells)

    /// The names the worksheet's code cells use and the functions they
    /// define, leaving out the word being completed (its range here).
    var completionSymbols: ((NSRange) -> CompletionIndex)?
    private var completion: CompletionPopup?

    var isCompleting: Bool { completion != nil }

    /// NSTextView's own completion keys (Option+Esc, F5); Esc is caught in keyDown.
    override func complete(_ sender: Any?) { showCompletions(templatesOnly: false) }

    /// Cell › Complete Word (Esc, Ctrl+Space) and Show Template
    /// (Ctrl+Shift+Space). One entry is inserted at once, as in wxMaxima;
    /// several open the list.
    func showCompletions(templatesOnly: Bool) {
        let caret = selectedRange()
        guard highlightsSyntax, caret.length == 0,
              let word = MaximaCompletion.word(in: string, caret: caret.location) else { return NSSound.beep() }
        let sheet = completionSymbols?(word.range) ?? MaximaCompletion.symbols(in: string, skipping: word.range)
        let items = MaximaCompletion.completions(of: word.prefix, maxima: MaximaSymbols.shared.completionIndex,
                                                 worksheet: sheet, templatesOnly: templatesOnly)
        guard !items.isEmpty else { return NSSound.beep() }
        if items.count == 1 { return accept(items[0]) }
        let popup = CompletionPopup(worksheet: sheet, templatesOnly: templatesOnly,
                                    font: font ?? .monospacedSystemFont(ofSize: 14, weight: .regular))
        popup.onAccept = { [weak self] item in self?.accept(item) }
        completion = popup
        present(items)
    }

    private func present(_ items: [CompletionItem]) {
        guard let completion, let window, let word = MaximaCompletion.word(in: string, caret: selectedRange().location),
              let rect = caretRect(at: word.range.location) else { return closeCompletion() }
        let screen = window.convertToScreen(convert(rect, to: nil))
        completion.show(items, at: screen, in: window)
    }

    /// After typing or a caret move: narrows the list, or closes it when the
    /// caret is no longer in a name or nothing matches.
    private func updateCompletion() {
        guard let completion else { return }
        let caret = selectedRange()
        guard caret.length == 0, let word = MaximaCompletion.word(in: string, caret: caret.location) else { return closeCompletion() }
        let items = MaximaCompletion.completions(of: word.prefix, maxima: MaximaSymbols.shared.completionIndex,
                                                 worksheet: completion.worksheet, templatesOnly: completion.templatesOnly)
        if items.isEmpty { closeCompletion() } else if items != completion.items { present(items) }
    }

    func closeCompletion() {
        completion?.close()
        completion = nil
    }

    /// Replaces the word at the caret with `item`, as one undo step; a
    /// template's first placeholder is selected, ready to type over.
    private func accept(_ item: CompletionItem) {
        closeCompletion()
        guard let word = MaximaCompletion.word(in: string, caret: selectedRange().location) else { return }
        breakUndoCoalescing()
        replace(word.range, with: item.insertion)
        undoManager?.setActionName(String(localized: "Completion", comment: "Undo action name"))
        breakUndoCoalescing()
        let inserted = NSRange(location: word.range.location, length: (item.insertion as NSString).length)
        if let first = MaximaCompletion.placeholders(in: string).first(where: { NSLocationInRange($0.location, inserted) }) {
            setSelectedRange(first)
        } else {
            setSelectedRange(NSRange(location: NSMaxRange(inserted), length: 0))
        }
        scrollRangeToVisible(selectedRange())
    }

    /// While the list is open: Up and Down choose, Return or Tab accepts,
    /// Esc closes it. Everything else is typing.
    private func handleCompletionKey(_ event: NSEvent) -> Bool {
        guard let completion else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 125: completion.move(by: 1)                              // Down
        case 126: completion.move(by: -1)                             // Up
        case 121: completion.move(by: 10)                             // Page Down
        case 116: completion.move(by: -10)                            // Page Up
        case 36, 76, 48: if let item = completion.selected { accept(item) }   // Return, Enter, Tab
        case 53: closeCompletion()                                    // Esc
        default: return false
        }
        return true
    }

    /// Tab selects the next `<argument>` of a template, Shift+Tab the one
    /// before (wxMaxima's FindNextTemplate). Without one, Tab is a tab.
    override func insertTab(_ sender: Any?) {
        if highlightsSyntax, let next = MaximaCompletion.nextPlaceholder(in: string, after: selectedRange()) {
            setSelectedRange(next)
            scrollRangeToVisible(next)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if highlightsSyntax, let next = MaximaCompletion.nextPlaceholder(in: string, after: selectedRange(), backwards: true) {
            setSelectedRange(next)
            scrollRangeToVisible(next)
        } else {
            super.insertBacktab(sender)
        }
    }
}

/// Hosts a cell's CellTextView in SwiftUI. The view itself comes from the
/// controller, which keeps one per cell for the document's lifetime (see
/// `WorksheetController.editor(for:)`), and writes typing into the model.
struct CellEditor: NSViewRepresentable {
    /// The cell's input in the model, to catch changes made elsewhere.
    let text: String
    let kind: CellKind
    /// The worksheet's zoom.
    let scale: CGFloat
    let accessibilityID: String
    /// Changes when Settings' fonts change, so the view takes the new font.
    var fontSettings = ""
    /// Bold, italic, ... of a text cell's text.
    var formats: TextFormats = []
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
        let font = Self.font(for: kind, scale: scale)
        view.formatsText = kind == .text
        if kind == .text {
            // Fonts come with the formats; setting the view's font would undo them.
            view.baseFont = font
            view.applyFormats(formats, base: font)
            if view.string.isEmpty { view.typingAttributes = CellTextView.attributes([], base: font) }
        } else if view.font != font {
            view.font = font
            view.invalidateIntrinsicContentSize()
        }
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

    /// The cell's font: Settings' code font and sizes, at the worksheet's
    /// zoom. Headings keep their proportion to the text size.
    static func font(for kind: CellKind, scale: CGFloat = 1) -> NSFont {
        let text = CGFloat(AppSettings.textSize) * scale
        switch kind {
        case .code:
            let size = CGFloat(AppSettings.codeSize) * scale
            let family = AppSettings.codeFont
            return (family.isEmpty ? nil : NSFont(name: family, size: size)) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .title: return .systemFont(ofSize: text * 26 / 14, weight: .bold)
        case .section: return .systemFont(ofSize: text * 21 / 14, weight: .semibold)
        case .subsection: return .systemFont(ofSize: text * 17 / 14, weight: .semibold)
        case .subsubsection, .heading5, .heading6: return .systemFont(ofSize: text * 15 / 14, weight: .semibold)
        case .text, .image, .pageBreak, .raw: return .systemFont(ofSize: text)
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
