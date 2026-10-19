// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import UniformTypeIdentifiers
import MaximaKit
import SwiftUI
import WorksheetKit
import WXMLKit

/// Per-window state and actions: which cell has focus, and the Maxima
/// session that evaluates the worksheet. One session per window, started
/// when the window opens and shut down when it closes.
@MainActor
@Observable
public final class WorksheetController {
    public let document: WorksheetDocument
    /// The cell with the keyboard focus. Setting it to another cell moves
    /// the focus there (see `focusRequest`).
    public var focusedCell: UUID? {
        didSet {
            if focusedCell != oldValue, !notingFocus { focusRequest &+= 1 }
            followsFocus = true
        }
    }
    @ObservationIgnored private var notingFocus = false
    /// Keep the focused cell in view while outputs above it grow; off once
    /// the user scrolls (WorksheetWindow watches live scrolling).
    @ObservationIgnored var followsFocus = true
    /// Whole cells selected (CellSelection.swift), in document order; empty
    /// while editing.
    public internal(set) var selectedCells: [UUID] = []
    @ObservationIgnored var selectionAnchor: UUID?
    @ObservationIgnored var selectionHead: UUID?
    /// First responder while cells are selected; the window installs it.
    @ObservationIgnored var selectionResponder: CellSelectionResponder?
    /// Bumped by every request to move the focus; an editor takes the focus
    /// when it sees a new value and its cell is `focusedCell`.
    public private(set) var focusRequest = 0
    public var undoManager: UndoManager?
    /// Marks the document edited. Evaluation output changes the document
    /// without the undo manager, which is all SwiftUI watches; the window
    /// sets this to reach its NSDocument.
    var markEdited: () -> Void = {}

    /// The session's state, for the toolbar.
    public private(set) var sessionState: SessionState = .dead
    /// Why Maxima is not running, or other news for the status line.
    public private(set) var statusMessage: String?
    /// The status message came from Maxima's `statusbar` tag.
    @ObservationIgnored private var statusFromMaxima = false
    /// Cells sent to Maxima and not finished yet.
    public private(set) var running: Set<UUID> = []
    /// The cell whose question is waiting for an answer.
    public private(set) var asking: UUID?

    /// Where the last evaluation of a cell failed, for its editor.
    public private(set) var errorMarks: [UUID: ErrorMarks] = [:]
    /// The text each running cell was sent with, and its statements' ranges.
    @ObservationIgnored private var sentStatements: [UUID: (text: String, ranges: [Range<Int>])] = [:]
    /// The statement each running cell is at.
    @ObservationIgnored private var currentStatement: [UUID: Int] = [:]

    private var session: MaximaSession?
    private var sessionWatcher: Task<Void, Never>?
    /// The input label the next statement gets.
    private var nextLabel = 1
    /// Output waiting for the next 100 ms flush, per cell.
    private var pending: [UUID: [Change]] = [:]
    private var flushTask: Task<Void, Never>?
    /// Cell streams waiting to be read, in the order the cells were sent.
    private var streams: [(id: UUID, stream: AsyncStream<CellEvent>)] = []
    private var reader: Task<Void, Never>?
    /// Session factory, replaceable in tests.
    var makeSession: (MaximaConfiguration) -> MaximaSession = { MaximaSession(configuration: $0) }

    /// Find and Replace for this window.
    public let find = FindController()

    public init(document: WorksheetDocument) {
        self.document = document
        find.controller = self
    }

    // MARK: - Window registry

    /// Controllers of open windows, most recently focused last.
    private static var live: [WeakController] = []
    private struct WeakController { weak var controller: WorksheetController? }

    /// Records this controller as the one of the key window.
    func becameKey() {
        Self.live.removeAll { $0.controller == nil || $0.controller === self }
        Self.live.append(WeakController(controller: self))
    }

    /// The window showing this worksheet, once it is on screen.
    @ObservationIgnored weak var window: NSWindow?

    /// The controller of the key window, else of the window used last.
    static var keyController: WorksheetController? {
        let controllers = all
        return controllers.first { $0.window != nil && $0.window === NSApp.keyWindow } ?? controllers.last
    }

    /// Every open window's controller.
    static var all: [WorksheetController] { live.compactMap(\.controller) }

    // MARK: - Cells

    /// Where the caret goes in the cell that gets the focus next.
    public private(set) var caretRequest: CaretRequest?

    /// Moves the focus to `id` with the caret at `place`. An editor already
    /// in the window takes it at once, so the next keystroke lands there; a
    /// lazy cell not created yet takes it when it arrives.
    public func focus(_ id: UUID, caret place: CaretPlace) {
        reveal(id)
        caretRequest = CaretRequest(cell: id, place: place, serial: (caretRequest?.serial ?? 0) + 1)
        if let editor = editors[id], let window = editor.window {
            editor.pendingCaret = place
            window.makeFirstResponder(editor)   // records the focus through noteFocus
            editor.applyPendingCaret()
        }
        if focusedCell == id { requestFocus() } else { focusedCell = id }
    }

    /// Each cell's editor, kept for the document's lifetime. The lazy stack
    /// drops views that scroll away; a text view made anew would lose its
    /// undo actions, and undoing them would edit an orphaned text storage
    /// (Phase 3: undo after scrolling did nothing). Callbacks hold the
    /// controller weakly; the controller owns the views.
    @ObservationIgnored private var editors: [UUID: CellTextView] = [:]

    func forEachEditor(_ body: (UUID, CellTextView) -> Void) {
        for (id, editor) in editors { body(id, editor) }
    }

    /// A request to scroll a cell into view, then run `then` (the window acts on it).
    public private(set) var scrollRequest: (cell: UUID, serial: Int)?
    @ObservationIgnored var afterScroll: (() -> Void)?

    func scroll(to id: UUID, then: @escaping () -> Void) {
        afterScroll = then
        scrollRequest = (id, (scrollRequest?.serial ?? 0) + 1)
    }

    /// The cell's editor if one was made (for the key-script dumps).
    func existingEditor(for id: UUID) -> CellTextView? { editors[id] }

    /// The cell's editor, made on first use.
    func editor(for id: UUID) -> CellTextView {
        if let editor = editors[id] { return editor }
        let editor = CellTextView()
        editor.string = document.worksheet[id]?.input ?? ""
        editor.onTextChange = { [weak self] text in
            self?.document.setInput(id, text)
            self?.find.documentChanged()
        }
        editor.findMarks = find.marks(for: id)
        editor.errorMarks = errorMarks[id]
        editor.undoSource = { [weak self] in self?.undoManager }
        editor.onFocus = { [weak self] in self?.noteFocus(id) }
        editor.onEvaluate = { [weak self] in self?.evaluateAndAdvance(id) }
        editor.onLeave = { [weak self] up, x in self?.leave(id, up: up, x: x) ?? false }
        editor.onSelectCells = { [weak self] up in self?.startCellSelection(from: id, up: up) }
        editor.onPasteCells = { [weak self] in self?.pasteCells(after: id) ?? false }
        editor.isFocusedCell = { [weak self] in self?.focusedCell == id && self?.selectedCells.isEmpty == true }
        editor.onRemovedWhileFocused = { [weak self] in
            // Output above pushed the cell out of view: follow it, as
            // wxMaxima does, unless the user scrolled away.
            guard let self, self.followsFocus, self.focusedCell == id else { return }
            DispatchQueue.main.async { self.requestFocus() }
        }
        editors[id] = editor
        return editor
    }

    /// Up from a cell's first line, or Down from its last: the previous or
    /// next cell with an editor, at the same x. False when there is none.
    @discardableResult
    public func leave(_ id: UUID, up: Bool, x: CGFloat) -> Bool {
        let cells = document.worksheet.cells
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return false }
        let range = up ? Array(cells[..<index].reversed()) : Array(cells[(index + 1)...])
        guard let target = range.first(where: { $0.hasEditor && isVisible($0.id) }) else { return false }
        focus(target.id, caret: up ? .lastLine(x: x) : .firstLine(x: x))
        return true
    }

    /// Gives the focus back to `focusedCell` (after the answer field had it).
    public func requestFocus() { focusRequest &+= 1 }

    /// The user scrolled the worksheet: stop following the focused cell
    /// until it gets the focus again.
    func userScrolled() { followsFocus = false }

    /// An editor took the focus by itself (a click, Tab): record it without
    /// a focus request, so the worksheet doesn't scroll.
    func noteFocus(_ id: UUID) {
        clearCellSelection()
        notingFocus = true
        focusedCell = id
        notingFocus = false
        becameKey()
    }

    public func insertCell(_ kind: CellKind) {
        let id = document.insertCell(kind, after: focusedCell ?? document.worksheet.cells.last?.id,
                                     undo: undoManager)
        focusedCell = id
    }

    /// Cell › Insert Image…: an image cell after the focused cell, its
    /// caption the file's name (as wxMaxima's).
    public func insertImage(from url: URL) {
        guard let data = try? Data(contentsOf: url), ImageDecoding.image(data, format: url.pathExtension) != nil else {
            statusMessage = "\(url.lastPathComponent) is not an image Macsima can show."
            return
        }
        let format = url.pathExtension.lowercased()
        let cell = Cell(kind: .image, input: url.lastPathComponent,
                        outputs: [.image(data: data, format: format.isEmpty ? "png" : format, label: nil)])
        let after = focusedCell.flatMap { document.worksheet.index(of: $0) }.map { $0 + 1 } ?? document.worksheet.cells.count
        document.insertCells([cell], at: after, undo: undoManager, name: "Insert Image")
        focusedCell = cell.id
    }

    public func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .svg, .tiff]
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.insertImage(from: url) }
        }
    }

    public func deleteFocusedCell() {
        guard let id = focusedCell, let index = document.worksheet.index(of: id) else { return }
        document.deleteCell(id, undo: undoManager)
        let cells = document.worksheet.cells
        focusedCell = cells.isEmpty ? nil : cells[min(index, cells.count - 1)].id
    }

    // MARK: - Folding and hiding

    /// Folds or unfolds the heading `id`'s section (wxMaxima's triangle on
    /// a heading's bracket). Not undoable, as in wxMaxima; marks the document edited.
    public func toggleFold(_ id: UUID) {
        guard let i = document.worksheet.index(of: id), document.worksheet.cells[i].kind.isHeading,
              !document.worksheet.foldRange(of: i).isEmpty else { return }
        document.worksheet.cells[i].isFolded.toggle()
        markEdited()
    }

    /// Folds every heading with something under it, or unfolds all.
    public func setAllFolded(_ folded: Bool) {
        var changed = false
        for i in document.worksheet.cells.indices where document.worksheet.cells[i].kind.isHeading
            && document.worksheet.cells[i].isFolded != folded && (!folded || !document.worksheet.foldRange(of: i).isEmpty) {
            document.worksheet.cells[i].isFolded = folded
            changed = true
        }
        if changed {
            if folded, let focused = focusedCell, let i = document.worksheet.index(of: focused),
               !document.worksheet.visibleIndices.contains(i) {
                // The focused cell went out of sight: focus its outermost heading.
                focusedCell = document.worksheet.foldedAncestors(of: i).first.map { document.worksheet.cells[$0].id }
            }
            markEdited()
        }
    }

    /// Shows a code or text cell as its first line only, outputs hidden (wxMaxima's hide).
    public func toggleHidden(_ id: UUID) {
        guard let i = document.worksheet.index(of: id), [.code, .text].contains(document.worksheet.cells[i].kind) else { return }
        document.worksheet.cells[i].isHidden.toggle()
        markEdited()
    }

    /// Unfolds the headings that hide `id`, and shows the cell whole if it
    /// was hidden, so it can be seen and edited.
    func reveal(_ id: UUID) {
        guard let i = document.worksheet.index(of: id) else { return }
        let ancestors = document.worksheet.foldedAncestors(of: i)
        guard !ancestors.isEmpty || document.worksheet.cells[i].isHidden else { return }
        for a in ancestors { document.worksheet.cells[a].isFolded = false }
        document.worksheet.cells[i].isHidden = false
        markEdited()
    }

    var focusedCellIsHeading: Bool {
        focusedCell.flatMap { document.worksheet[$0] }?.kind.isHeading ?? false
    }

    func isVisible(_ id: UUID) -> Bool {
        guard let i = document.worksheet.index(of: id) else { return false }
        return document.worksheet.foldedAncestors(of: i).isEmpty
    }

    // MARK: - Zoom

    /// wxMaxima's limits and step (Configuration.h, MaximaCommandMenus.cpp):
    /// 10% to 3200%, 10 points at a time. Saved in the file as `zoom`.
    static let zoomRange = 10...3200
    static let zoomStep = 10

    /// The zoom as a factor (1 = 100%).
    public var scale: CGFloat { CGFloat(document.worksheet.zoom) / 100 }

    public func zoomIn() { setZoom(document.worksheet.zoom + Self.zoomStep) }
    public func zoomOut() { setZoom(document.worksheet.zoom - Self.zoomStep) }
    public func actualSize() { setZoom(100) }

    /// Sets the zoom in percent, clamped; it goes into the file, so it marks
    /// the worksheet edited (without an undo step).
    public func setZoom(_ percent: Int) {
        let zoom = min(max(percent, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard zoom != document.worksheet.zoom else { return }
        document.worksheet.zoom = zoom
        markEdited()
    }

    /// Cmd+/ in the focused code cell.
    public func toggleComment() {
        guard let id = focusedCell, document.worksheet[id]?.kind == .code else { return }
        editor(for: id).toggleComment()
    }

    public func setFocusedKind(_ kind: CellKind) {
        guard let id = focusedCell else { return }
        document.setKind(id, kind, undo: undoManager)
    }

    // MARK: - Session lifecycle

    /// Starts Maxima for this window.
    public func start() async {
        guard session == nil else { return }
        let session = makeSession(await AppSettings.configuration())
        self.session = session
        nextLabel = 1
        sessionWatcher = Task { [weak self] in
            for await event in session.events { self?.handle(event) }
        }
        do {
            statusMessage = nil
            try await session.start()
        } catch {
            statusMessage = "Maxima did not start: \(error)"
        }
    }

    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    /// Shuts Maxima down when `window` closes. A window closes after its
    /// document agreed (the save sheet); SwiftUI's onDisappear also fires for
    /// windows that only hide, a background tab for one.
    @ObservationIgnored private var scrollObserver: NSObjectProtocol?

    func watchClose(of window: NSWindow) {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.shutdown() }
            }
        }
    }

    /// A user scroll (trackpad, wheel, scroller) in this window's worksheet
    /// stops the following of the focused cell. Programmatic scrolls don't
    /// send this notification.
    func watchScrolling(in window: NSWindow) {
        guard scrollObserver == nil else { return }
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: .main) { [weak self, weak window] note in
            let scrollView = note.object as? NSScrollView
            MainActor.assumeIsolated {
                guard let window, scrollView?.window === window else { return }
                self?.userScrolled()
            }
        }
    }

    /// Shuts Maxima down (window closing or app quitting).
    public func shutdown() async {
        guard let session else { return }
        self.session = nil
        await session.shutdown()
        sessionWatcher?.cancel()
        sessionState = .dead
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .state(let state):
            sessionState = state
        case .died(let reason):
            // A restart the user asked for is not news.
            if reason != "restarted" { statusMessage = "Maxima stopped: \(reason)" }
        case .slowStart:
            statusMessage = "Maxima is slow to start…"
        case .async(let cellID, let content):
            if let id = UUID(uuidString: cellID) { enqueue(id, .append(.math(xml: Self.storedMath(content)))) }
        case .tag("statusbar", let content):
            statusMessage = content
            statusFromMaxima = true
        case .tag("wxxml-symbols", let content):
            MaximaSymbols.shared.ingestInBackground(content)
        case .interruptChannelReady, .tag, .output:
            break
        }
    }

    // MARK: - Evaluation

    /// Shift+Return: evaluates the cell, then moves on as wxMaxima does: to
    /// the next cell that has an editor, or to a new code cell at the end.
    public func evaluateAndAdvance(_ id: UUID) {
        evaluate(id)
        let cells = document.worksheet.cells
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        if let next = cells[(index + 1)...].first(where: { $0.hasEditor && isVisible($0.id) }) {
            focusedCell = next.id
        } else {
            focusedCell = document.insertCell(.code, after: cells.last?.id, undo: undoManager)
        }
    }

    public func evaluate(_ id: UUID) {
        guard let cell = document.worksheet[id], cell.kind == .code, let session else { return }
        let text = cell.input
        document.worksheet.clearOutputs(id)
        pending[id] = nil
        running.insert(id)
        setErrorMarks(nil, for: id)
        sentStatements[id] = (text, (try? StatementSplitter.ranges(text)) ?? [])
        currentStatement[id] = nil
        Task {
            do {
                let stream = try await session.evaluate(cellID: id.uuidString, text: text)
                streams.append((id, stream))
                startReader()
            } catch {
                enqueue(id, .append(.error(kind: nil, message: "\(error)")))
                // Unbalanced brackets: nothing was sent; mark the bracket.
                if case .split(let split)? = error as? MaximaError, let at = split.position.utf16Offset(in: text) {
                    let length = at < (text as NSString).length ? 1 : 0
                    setErrorMarks(ErrorMarks(text: text, statements: [], spots: [NSRange(location: at, length: length)]), for: id)
                }
                running.remove(id)
            }
        }
    }

    /// Reads the cell streams one after the other. Maxima runs cells in
    /// order, so this keeps every event (and so every input label) in the
    /// order Maxima produced it; one task per stream would interleave them.
    private func startReader() {
        guard reader == nil else { return }
        reader = Task { [weak self] in
            while let self, !self.streams.isEmpty {
                let (id, stream) = self.streams.removeFirst()
                for await event in stream { self.receive(event, for: id) }
            }
            self?.reader = nil
        }
    }

    public func evaluateAll() {
        for cell in document.worksheet.codeCells { evaluate(cell.id) }
    }

    public func interrupt() {
        guard let session else { return }
        Task { await session.interrupt() }
    }

    public func restart() {
        Task {
            guard let session else { await start(); return }
            statusMessage = nil
            nextLabel = 1
            do { try await session.restart() } catch { statusMessage = "Maxima did not restart: \(error)" }
        }
    }

    /// Answers the question the cell `id` is showing.
    public func answer(_ text: String, for id: UUID) {
        guard asking == id, let session else { return }
        asking = nil
        // Keep what Maxima gets (the session adds a missing ";"), as wxMaxima stores it.
        var sent = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sent.hasSuffix(";") && !sent.hasSuffix("$") { sent += ";" }
        enqueue(id, .answered(sent))
        Task {
            do { try await session.answer(text) } catch { statusMessage = "\(error)" }
        }
    }

    // MARK: - Events to model, batched

    enum Change {
        case append(Output)
        case appendText(String)
        case label(Int)
        /// The statement failed: the text since it started becomes the error.
        case error(kind: String?, message: String)
        case answered(String)
        /// Drops the empty text runs statement marks left behind.
        case cleanUp
    }

    /// Maps one cell event. Image bytes are read right away: Maxima's temp
    /// file disappears on kill and restart.
    func receive(_ event: CellEvent, for id: UUID) {
        switch event {
        case .started(let index, _):
            currentStatement[id] = index
            if index == 0 { enqueue(id, .label(nextLabel)) }
            enqueue(id, .appendText(Self.statementMark))
        case .math(let xml):
            let out = TranslationCache.shared.translate(xml)
            for path in out.imagePaths {
                if let data = FileManager.default.contents(atPath: path) {
                    let format = URL(filePath: path).pathExtension.lowercased()
                    enqueue(id, .append(.image(data: data, format: format.isEmpty ? "png" : format, label: out.label)))
                } else {
                    enqueue(id, .append(.error(kind: nil, message: "The plot file \(path) was gone before it could be read.")))
                }
            }
            if let animation = out.animation {
                let frames = animation.frames.compactMap { FileManager.default.contents(atPath: $0) }
                if frames.count == animation.frames.count, !frames.isEmpty {
                    let format = URL(filePath: animation.frames[0]).pathExtension.lowercased()
                    var attributes = animation.attributes
                    attributes["del"] = nil
                    enqueue(id, .append(.animation(frames: frames, format: format, label: out.label, attributes: attributes)))
                } else {
                    enqueue(id, .append(.error(kind: nil, message: "The animation's frames were gone before they could be read.")))
                }
                return
            }
            // The empty line Maxima prints after an animation (ldisp's newline).
            if out.label?.hasPrefix("%t") == true, out.imagePaths.isEmpty, Self.isBlank(xml) { return }
            // A label with nothing after it (the empty result of a plot) is kept, as wxMaxima keeps it.
            if !out.mathML.isEmpty || (out.imagePaths.isEmpty && out.label != nil) {
                enqueue(id, .append(.math(xml: Self.storedMath(xml))))
            }
        case .text(let line):
            enqueue(id, .appendText(line))
        case .question(let prompt):
            enqueue(id, .append(.question(prompt: Self.storedMath(prompt), answer: nil)))
            asking = id
        case .debugger(let level):
            // Debugger UI beyond answering prompts is Phase 3.
            enqueue(id, .append(.question(prompt: "<math><st>Maxima debugger (dbm:\(level))</st></math>", answer: nil)))
            asking = id
        case .error(let kind, let message):
            enqueue(id, .error(kind: kind.rawValue, message: message))
            markError(in: id, syntax: kind == .syntax, message: message)
        case .interrupted:
            enqueue(id, .error(kind: "interrupted", message: "Interrupted"))
        case .skipped:
            break
        case .prompt(let label):
            nextLabel = label
        case .async(let xml):
            enqueue(id, .append(.math(xml: Self.storedMath(xml))))
        case .tag("wxxml-asciimath", let content):
            enqueue(id, .appendText(content))
        case .tag("statusbar", let content):
            statusMessage = content
            statusFromMaxima = true
        case .tag:
            break
        case .finished(let outcome):
            if case .sessionDied(let reason) = outcome {
                enqueue(id, .append(.error(kind: nil, message: "Not finished: Maxima \(reason).")))
            }
            if asking == id { asking = nil }
            enqueue(id, .cleanUp)
            flush()
            running.remove(id)
            // Maxima's progress text ("Preparing Frame #3") is done once
            // nothing runs; wxMaxima shows "Ready" there.
            if running.isEmpty, statusFromMaxima {
                statusMessage = nil
                statusFromMaxima = false
            }
        }
    }

    /// Marks the statement that failed in the cell's input, and for a
    /// syntax error the spot Maxima's parser stopped at (as wxMaxima does
    /// since GH #289).
    private func markError(in id: UUID, syntax: Bool, message: String) {
        guard let sent = sentStatements[id], let index = currentStatement[id], index < sent.ranges.count else { return }
        let statement = sent.ranges[index]
        var marks = errorMarks[id].flatMap { $0.text == sent.text ? $0 : nil }
            ?? ErrorMarks(text: sent.text, statements: [], spots: [])
        marks.statements.append(NSRange(location: statement.lowerBound, length: statement.count))
        if syntax, let spot = SyntaxErrorLocation.locate(output: message, cellText: sent.text, statement: statement) {
            marks.spots.append(NSRange(location: spot.lowerBound, length: spot.count))
        }
        setErrorMarks(marks, for: id)
    }

    private func setErrorMarks(_ marks: ErrorMarks?, for id: UUID) {
        errorMarks[id] = marks
        existingEditor(for: id)?.errorMarks = marks
    }

    /// Math as the model keeps it: one `<math>` element in canonical XML,
    /// so it comes back byte for byte from a saved .wxmx. Background output
    /// arrives as `<mth>`, prompts may hold several nodes.
    /// Math holding nothing but its label and blank text.
    static func isBlank(_ xml: String) -> Bool {
        let withoutLabel = xml.replacingOccurrences(of: #"<lbl[^>]*>.*?</lbl>"#, with: "", options: .regularExpression)
        let text = withoutLabel.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func storedMath(_ xml: String) -> String {
        guard let nodes = try? XMLTree.parseFragment(xml) else { return xml }
        let content: [XMLTreeNode]
        if nodes.count == 1, let name = nodes[0].name, name == "math" || name == "mth" {
            content = nodes[0].children
        } else {
            content = nodes
        }
        return XMLTreeNode.element(name: "math", attributes: [:], children: content).xml
    }

    /// Marks where a statement's text starts, so an error can take just that text.
    static let statementMark = "\u{1}"

    private func enqueue(_ id: UUID, _ change: Change) {
        pending[id, default: []].append(change)
        if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.flush()
            }
        }
    }

    /// Applies pending output to the document (at most every 100 ms).
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        let batch = pending
        pending = [:]
        if !batch.isEmpty { markEdited() }
        for (id, changes) in batch {
            document.worksheet.update(id) { cell in
                for change in changes { Self.apply(change, to: &cell) }
            }
        }
    }

    static func apply(_ change: Change, to cell: inout Cell) {
        switch change {
        case .label(let n):
            cell.inputLabel = n
        case .append(let output):
            cell.outputs.append(output)
        case .appendText(let line):
            if line == statementMark {
                cell.outputs.append(.text(""))   // a fresh text run for the statement
            } else if case .text(let previous)? = cell.outputs.last {
                cell.outputs[cell.outputs.count - 1] = .text(previous.isEmpty ? line : previous + "\n" + line)
            } else {
                cell.outputs.append(.text(line))
            }
        case .error(let kind, let message):
            // The error's lines already arrived as text: show that text as the error.
            if case .text(let text)? = cell.outputs.last, !text.isEmpty {
                cell.outputs[cell.outputs.count - 1] = .error(kind: kind, message: kind == "interrupted" ? message : text)
            } else {
                cell.outputs.append(.error(kind: kind, message: message))
            }
        case .cleanUp:
            cell.outputs.removeAll { if case .text(let t) = $0 { t.isEmpty } else { false } }
        case .answered(let answer):
            if let i = cell.outputs.lastIndex(where: { if case .question(_, nil) = $0 { true } else { false } }),
               case .question(let prompt, _) = cell.outputs[i] {
                cell.outputs[i] = .question(prompt: prompt, answer: answer)
            }
        }
    }
}

extension Cell {
    /// The cell shows a text editor (page breaks, image and unknown cells don't).
    var hasEditor: Bool { ![.raw, .pageBreak].contains(kind) }
}

/// Where a cell's last evaluation failed: the statements Maxima reported an
/// error for and the places a syntax error points at, as UTF-16 ranges in
/// `text`. Shown only while the cell still holds that text.
public struct ErrorMarks: Equatable, Sendable {
    public var text: String
    public var statements: [NSRange]
    public var spots: [NSRange]
}
