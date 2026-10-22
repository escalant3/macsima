// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin
import Foundation

/// Runs a session script (`.mxs`) and logs what happens. Used by the
/// `maxima-session` tool and the Phase 1 exit test.
///
/// Script lines:
/// - a plain line is one cell; `!cell` … `!end` makes one cell of several lines;
/// - `!async <text>` starts a cell without waiting for it;
/// - `!answer <text>` answers the question the last cell is asking;
/// - `!interrupt` (channel), `!sigint` (SIGINT), `!kill`, `!restart` act on
///   the running cell, then wait for it to finish;
/// - `!sleep <seconds>`;
/// - `!expect completed|failed|failed:<kind>|interrupted|died|question|skipped`
///   and `!expect-text <substring>` check the last cell; `!expect-plot` checks
///   that it named an image file that exists; `!expect-state <state>` checks the session;
/// - `#` starts a comment.
public struct ScriptRunner: Sendable {
    public struct Report: Sendable {
        /// Statements sent to Maxima (started), answers given.
        public var statements = 0
        public var answers = 0
        public var cells = 0
        /// Failed `!expect` lines; empty when the run passed.
        public var failures: [String] = []
        /// Image files the run produced.
        public var plotFiles: [String] = []
        /// Every private temp folder the session used.
        public var tempDirectories: [String] = []
        /// Every Maxima process group.
        public var processGroups: [pid_t] = []
    }

    public let session: MaximaSession
    private let log: @Sendable (String) -> Void

    public init(session: MaximaSession, log: @escaping @Sendable (String) -> Void) {
        self.session = session
        self.log = log
    }

    private struct Cell {
        let id: String
        var iterator: AsyncStream<CellEvent>.Iterator
        var events: [CellEvent] = []
        var done = false
    }

    public func run(_ script: String) async -> Report {
        var report = Report()
        var last: Cell?
        var lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...]

        func note(_ dir: String?) {
            if let dir, !report.tempDirectories.contains(dir) { report.tempDirectories.append(dir) }
        }
        note(await session.tempDirectory)

        while let raw = lines.popFirst() {
            let line = raw.trimmingWhitespace
            if line.isEmpty || line.hasPrefix("#") { continue }
            let (word, arg) = Self.directive(line)
            switch word {
            case "!cell":
                var body: [String] = []
                while let next = lines.popFirst(), next.trimmingWhitespace != "!end" { body.append(next) }
                last = await startCell(body.joined(separator: "\n"), wait: true, report: &report)
            case "!async":
                last = await startCell(arg, wait: false, report: &report)
            case "!answer":
                guard var cell = last, !cell.done else { fail("!answer with no cell asking", &report); continue }
                log("[\(cell.id)] answer: \(arg)")
                do { try await session.answer(arg); report.answers += 1 } catch {
                    fail("answer failed: \(error)", &report)
                    continue
                }
                await collect(&cell, report: &report)
                last = cell
            case "!interrupt", "!sigint":
                let result = await session.interrupt(via: word == "!sigint" ? .signal : .channel)
                log("-- interrupt: \(result)")
                if var cell = last, !cell.done { await collect(&cell, report: &report); last = cell }
            case "!kill":
                log("-- kill")
                await session.kill()
                if var cell = last, !cell.done { await collect(&cell, report: &report); last = cell }
            case "!restart":
                log("-- restart")
                do {
                    if await session.state == .dead { try await session.start() } else { try await session.restart() }
                    note(await session.tempDirectory)
                    log("-- Maxima running, process group \(await session.processGroup.map(String.init) ?? "?")")
                } catch { fail("restart failed: \(error)", &report) }
                if var cell = last, !cell.done { await collect(&cell, report: &report); last = cell }
            case "!sleep":
                try? await Task.sleep(for: .milliseconds(Int((Double(arg) ?? 1) * 1000)))
            case "!expect":
                check(arg, last, &report)
            case "!expect-text":
                let found = last?.events.contains { e in
                    switch e {
                    case .text(let t): t.contains(arg)
                    case .math(let m): m.contains(arg) || MathText.plain(m).contains(arg)
                    default: false
                    }
                } ?? false
                if !found { fail("expected output containing \"\(arg)\" in \(last?.id ?? "no cell")", &report) }
            case "!expect-plot":
                let files = (last?.events ?? []).compactMap { e -> String? in
                    if case .math(let m) = e { MathText.imageFile(in: m) } else { nil }
                }
                if let file = files.first, FileManager.default.fileExists(atPath: file) {
                    report.plotFiles.append(file)
                    log("[\(last?.id ?? "?")] plot file exists: \(file)")
                } else {
                    fail("expected an existing plot file in \(last?.id ?? "no cell")", &report)
                }
            case "!expect-state":
                let state = await session.state
                if state.rawValue != arg { fail("expected state \(arg), got \(state.rawValue)", &report) }
            default:
                last = await startCell(line, wait: true, report: &report)
            }
        }
        report.processGroups = await session.processGroups
        return report
    }

    private static func directive(_ line: String) -> (String, String) {
        guard line.hasPrefix("!") else { return ("", line) }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1].trimmingWhitespace : "")
    }

    private func startCell(_ text: String, wait: Bool, report: inout Report) async -> Cell? {
        report.cells += 1
        let id = "c\(report.cells)"
        do {
            let stream = try await session.evaluate(cellID: id, text: text)
            var cell = Cell(id: id, iterator: stream.makeAsyncIterator())
            if wait {
                await collect(&cell, report: &report)
            } else if let first = await cell.iterator.next() {   // the .started event
                cell.events.append(first)
                logEvent(first, id: id, report: &report)
                log("[\(id)]   (running in the background)")
            }
            return cell
        } catch {
            log("[\(id)] refused: \(error)")
            var cell = Cell(id: id, iterator: AsyncStream<CellEvent> { $0.finish() }.makeAsyncIterator())
            cell.done = true
            return cell
        }
    }

    /// Reads events until the cell finishes or asks something.
    private func collect(_ cell: inout Cell, report: inout Report) async {
        while let e = await cell.iterator.next() {
            cell.events.append(e)
            logEvent(e, id: cell.id, report: &report)
            switch e {
            case .finished: cell.done = true; return
            case .question, .debugger: return
            default: continue
            }
        }
        cell.done = true
    }

    private func logEvent(_ e: CellEvent, id: String, report: inout Report) {
        switch e {
        case .started(_, let s):
            report.statements += 1
            log("[\(id)] > \(s.text)")
        case .math(let m): log("[\(id)]   \(MathText.plain(m))")
        case .text(let t): log("[\(id)]   | \(t)")
        case .question(let q): log("[\(id)]   ? \(MathText.plain(q))")
        case .debugger(let level): log("[\(id)]   debugger level \(level)")
        case .error(let kind, let message):
            log("[\(id)]   error(\(kind.rawValue)): \(message.replacingOccurrences(of: "\n", with: " / "))")
        case .interrupted: log("[\(id)]   interrupted")
        case .skipped(let s): log("[\(id)]   skipped: \(s.text)")
        case .prompt: break
        case .async(let a): log("[\(id)]   async: \(MathText.plain(a))")
        case .tag(let name, _): log("[\(id)]   <\(name)>")
        case .finished(let outcome): log("[\(id)] = \(outcome)")
        }
    }

    private func check(_ what: String, _ cell: Cell?, _ report: inout Report) {
        guard let cell else { fail("!expect \(what) with no cell", &report); return }
        let outcome: CellOutcome? = cell.events.last.flatMap { if case .finished(let o) = $0 { o } else { nil } }
        let ok: Bool
        switch what {
        case "completed": ok = outcome == .completed
        case "failed": ok = { if case .failed = outcome { true } else { false } }()
        case "failed:maxima": ok = outcome == .failed(.maxima)
        case "failed:syntax": ok = outcome == .failed(.syntax)
        case "failed:lisp": ok = outcome == .failed(.lisp)
        case "interrupted": ok = outcome == .interrupted
        case "died": ok = { if case .sessionDied = outcome { true } else { false } }()
        case "question": ok = cell.events.last.map { if case .question = $0 { true } else { false } } ?? false
        case "skipped": ok = cell.events.contains { if case .skipped = $0 { true } else { false } }
        default: ok = false
        }
        if !ok { fail("[\(cell.id)] expected \(what), got \(cell.events.last.map { "\($0)" } ?? "nothing")", &report) }
    }

    private func fail(_ message: String, _ report: inout Report) {
        report.failures.append(message)
        log("!! \(message)")
    }
}

/// Rough plain text for math XML: tags stripped, entities decoded. For the
/// script runner's logs and `!expect-text`; WXMLKit's `MaximaInputText`
/// gives proper Maxima input, but MaximaKit does not depend on WXMLKit.
public enum MathText {
    public static func plain(_ xml: String) -> String {
        var out = ""
        var inTag = false
        for c in xml {
            if c == "<" { inTag = true; continue }
            if c == ">" { inTag = false; continue }
            if !inTag { out.append(c) }
        }
        return out.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The file named by an `<img>` tag, if any.
    public static func imageFile(in xml: String) -> String? {
        guard let a = xml.range(of: "<img"), let gt = xml.range(of: ">", range: a.upperBound..<xml.endIndex),
              let end = xml.range(of: "</img>", range: gt.upperBound..<xml.endIndex) else { return nil }
        return String(xml[gt.upperBound..<end.lowerBound])
    }
}
