// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
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
    public var focusedCell: UUID?
    public var undoManager: UndoManager?
    /// Marks the document edited. Evaluation output changes the document
    /// without the undo manager, which is all SwiftUI watches; the window
    /// sets this to reach its NSDocument.
    var markEdited: () -> Void = {}

    /// The session's state, for the toolbar.
    public private(set) var sessionState: SessionState = .dead
    /// Why Maxima is not running, or other news for the status line.
    public private(set) var statusMessage: String?
    /// Cells sent to Maxima and not finished yet.
    public private(set) var running: Set<UUID> = []
    /// The cell whose question is waiting for an answer.
    public private(set) var asking: UUID?

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

    public init(document: WorksheetDocument) {
        self.document = document
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

    /// The controller of the window used last.
    static var keyController: WorksheetController? { live.last(where: { $0.controller != nil })?.controller }

    /// Every open window's controller.
    static var all: [WorksheetController] { live.compactMap(\.controller) }

    // MARK: - Cells

    public func insertCell(_ kind: CellKind) {
        let id = document.insertCell(kind, after: focusedCell ?? document.worksheet.cells.last?.id,
                                     undo: undoManager)
        focusedCell = id
    }

    public func deleteFocusedCell() {
        guard let id = focusedCell, let index = document.worksheet.index(of: id) else { return }
        document.deleteCell(id, undo: undoManager)
        let cells = document.worksheet.cells
        focusedCell = cells.isEmpty ? nil : cells[min(index, cells.count - 1)].id
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
        case .interruptChannelReady, .tag, .output:
            break
        }
    }

    // MARK: - Evaluation

    public func evaluate(_ id: UUID) {
        guard let cell = document.worksheet[id], cell.kind == .code, let session else { return }
        let text = cell.input
        document.worksheet.clearOutputs(id)
        pending[id] = nil
        running.insert(id)
        Task {
            do {
                let stream = try await session.evaluate(cellID: id.uuidString, text: text)
                streams.append((id, stream))
                startReader()
            } catch {
                enqueue(id, .append(.error(kind: nil, message: "\(error)")))
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
        enqueue(id, .answered(text))
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
            if !out.mathML.isEmpty { enqueue(id, .append(.math(xml: Self.storedMath(xml)))) }
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
        }
    }

    /// Math as the model keeps it: one `<math>` element in canonical XML,
    /// so it comes back byte for byte from a saved .wxmx. Background output
    /// arrives as `<mth>`, prompts may hold several nodes.
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
