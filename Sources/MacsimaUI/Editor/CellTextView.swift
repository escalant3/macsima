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
    }

    @objc private func symbolsChanged() { rehighlight() }

    func rehighlight() {
        SyntaxHighlighter.apply(to: self, enabled: highlightsSyntax)
        updateBracketMatch()
    }

    /// The bracket pair shown at the caret, as text ranges, to remove later.
    private var bracketMarks: [NSTextRange] = []

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateBracketMatch()
    }

    /// Marks the bracket next to the caret and its partner (code cells, no selection).
    private func updateBracketMatch() {
        guard let layout = textLayoutManager else { return }
        for range in bracketMarks { layout.removeRenderingAttribute(.backgroundColor, for: range) }
        bracketMarks = []
        let selection = selectedRange()
        guard highlightsSyntax, selection.length == 0,
              let (a, b) = MaximaTokenizer.matchingBracket(in: string, caret: selection.location) else { return }
        for offset in [a, b] {
            if let range = textRange(NSRange(location: offset, length: 1)) {
                layout.addRenderingAttribute(.backgroundColor, value: Self.bracketColor, for: range)
                bracketMarks.append(range)
            }
        }
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

/// Hosts a CellTextView in SwiftUI, bound to the cell's input.
struct CellEditor: NSViewRepresentable {
    @Binding var text: String
    let kind: CellKind
    let accessibilityID: String
    /// This cell is the controller's focused cell.
    let isFocused: Bool
    /// Changes with every focus request (`WorksheetController.focusRequest`).
    let focusRequest: Int
    let onFocus: () -> Void
    let onEvaluate: () -> Void

    func makeNSView(context: Context) -> CellTextView {
        let view = CellTextView()
        view.delegate = context.coordinator
        view.string = text
        apply(to: view, context: context)
        view.rehighlight()
        return view
    }

    func updateNSView(_ view: CellTextView, context: Context) {
        context.coordinator.parent = self
        // Only when the model changed underneath (undo of a structural edit,
        // Replace): typing already wrote the same text into the model.
        if view.string != text, !view.hasMarkedText() {
            view.string = text
            view.rehighlight()
            view.invalidateIntrinsicContentSize()
        }
        apply(to: view, context: context)
    }

    private func apply(to view: CellTextView, context: Context) {
        let font = Self.font(for: kind)
        if view.font != font { view.font = font }
        view.highlightsSyntax = kind == .code
        view.setAccessibilityIdentifier(accessibilityID)
        view.onFocus = onFocus
        view.onEvaluate = onEvaluate
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CellEditor
        /// The focus request this editor has seen; nil before the first update.
        var focusRequest: Int?

        init(parent: CellEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? CellTextView else { return }
            if parent.text != view.string { parent.text = view.string }
            view.invalidateIntrinsicContentSize()
        }
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
