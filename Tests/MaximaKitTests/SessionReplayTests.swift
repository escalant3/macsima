// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Drives a session through a recorded scenario, the way the recorder did.
struct ScenarioRun {
    var cells: [[CellEvent]] = []
    var sessionEvents: [SessionEvent] = []
    var transport: ReplayTransport
    var finalState: SessionState

    var states: [SessionState] {
        sessionEvents.compactMap { if case .state(let s) = $0 { s } else { nil } }
    }
}

func makeSession(_ transport: ReplayTransport, token: String = Fixtures.token,
                 configure: (inout MaximaConfiguration) -> Void = { _ in }) -> MaximaSession {
    var config = MaximaConfiguration()
    config.glueSource = "(glue)"
    config.authenticationTimeout = .seconds(5)
    configure(&config)
    return MaximaSession(configuration: config, transport: { _ in transport }, token: { token })
}

/// Reads a cell stream until it finishes or stops at a question or the debugger.
func collect(_ iterator: inout AsyncStream<CellEvent>.Iterator, into events: inout [CellEvent]) async {
    while let e = await iterator.next() {
        events.append(e)
        switch e {
        case .finished, .question, .debugger: return
        default: continue
        }
    }
}

func runScenario(_ name: String, seed: UInt64 = 7, hasChannel: Bool = true) async throws -> ScenarioRun {
    let transport = try ReplayTransport.fixture(name, hasChannel: hasChannel, seed: seed)
    let session = makeSession(transport)
    let sessionEvents = Collector<SessionEvent>()
    let watcher = Task { for await e in session.events { await sessionEvents.append(e) } }
    try await session.start()

    var cells: [[CellEvent]] = []
    var open: (iterator: AsyncStream<CellEvent>.Iterator, index: Int)?
    for line in try ReplayTransport.scenarioLines(name) {
        if line.hasPrefix("!send :lisp-quiet") || line.hasPrefix("!sleep") || line.hasPrefix("!wait") { continue }
        if line.hasPrefix("!interrupt") || line.hasPrefix("!sigint") {
            let result = await session.interrupt(via: line.hasPrefix("!sigint") ? .signal : .channel)
            #expect(result == (line.hasPrefix("!sigint") ? .signal : .channel))
        } else if line.hasPrefix("!send ") {
            let stream = try await session.evaluate(cellID: "c\(cells.count)", text: String(line.dropFirst(6)))
            cells.append([])
            open = (stream.makeAsyncIterator(), cells.count - 1)
            continue
        } else if [.question, .debugger].contains(await session.state) {
            try await session.answer(line)
        } else {
            let stream = try await session.evaluate(cellID: "c\(cells.count)", text: line)
            cells.append([])
            open = (stream.makeAsyncIterator(), cells.count - 1)
        }
        if case (var iterator, let index)? = open {
            await collect(&iterator, into: &cells[index])
            open = (iterator, index)
        }
    }
    let finalState = await session.state
    await session.shutdown()
    _ = await watcher.value
    return ScenarioRun(cells: cells, sessionEvents: await sessionEvents.items, transport: transport, finalState: finalState)
}

struct SessionReplayTests {
    @Test(arguments: Fixtures.names(.glue))
    func everyScenarioReplays(_ name: String) async throws {
        for seed in [1, 7] as [UInt64] {
            let run = try await runScenario(name, seed: seed)
            #expect(run.transport.mismatches.isEmpty, "\(run.transport.mismatches)")
            for (i, cell) in run.cells.enumerated() {
                guard case .finished = cell.last else { Issue.record("\(name): cell \(i) unfinished: \(cell)"); continue }
            }
            let expected: SessionState = name.hasPrefix("25-") ? .dead : .idle
            #expect(run.finalState == expected, "\(name)")
            #expect(Array(run.states.prefix(4)) == [.starting, .authenticating, .configuring, .idle])
        }
    }

    @Test func plainResult() async throws {
        let run = try await runScenario("01-integrate")
        let cell = try #require(run.cells.first)
        #expect(cell.count == 4)
        #expect(cell[0] == .started(index: 0, Statement(text: "integrate(sin(x), x);", terminator: .show)))
        if case .math(let m) = cell[1] { #expect(m.contains("cos")) } else { Issue.record("\(cell[1])") }
        #expect(Array(cell.suffix(2)) == [.prompt(label: 2), .finished(.completed)])
        #expect(run.states == [.starting, .authenticating, .configuring, .idle, .busy, .idle, .dead])
    }

    @Test func startupOutputIsDroppedUntilTheKeyThenTagsGoToEvents() async throws {
        let run = try await runScenario("01-integrate")
        let idle = run.sessionEvents.firstIndex(of: .state(.idle)) ?? 0
        let early = run.sessionEvents[..<idle].filter { if case .output = $0 { true } else { false } }
        #expect(early.isEmpty, "no banner text leaks out before authentication")
        let tags = run.sessionEvents.compactMap { if case .tag(let n, _) = $0 { n } else { nil } }
        #expect(tags == ["wxxml-symbols", "variables", "variables"])
        #expect(run.sessionEvents.contains(.interruptChannelReady))
    }

    @Test func errors() async throws {
        let division = try await runScenario("04-error-division")
        #expect(division.cells[0].contains(.error(.maxima, message: "expt: undefined: 0 to a negative exponent.")))
        #expect(division.cells[0].last == .finished(.failed(.maxima)))
        #expect(division.cells[1].last == .finished(.completed))

        let syntax = try await runScenario("05-error-syntax")
        guard case .error(.syntax, let message) = syntax.cells[0].first(where: { if case .error = $0 { true } else { false } }) else {
            Issue.record("no syntax error"); return
        }
        #expect(message == "incorrect syntax: Premature termination of input at ;.\nx+;\n ^")
        #expect(syntax.cells[0].contains(.prompt(label: 1)), "the label does not advance")

        let user = try await runScenario("06-error-user")
        #expect(user.cells[0].contains(.error(.maxima, message: "custom failure")))

        let more = try await runScenario("28-errors-more")
        #expect(more.cells[0].contains(.error(.lisp, message: "The value\n1\nis not of type\nLIST\nwhen binding LIST")))
        #expect(more.cells[0].last == .finished(.failed(.lisp)))
        #expect(more.cells[1].contains(.error(.maxima, message: "")), "the message is in the math chunk")
        #expect(more.cells[1].contains { if case .math(let m) = $0 { m.contains("value is") } else { false } })
        #expect(more.cells[2].last == .finished(.completed))
    }

    @Test func questions() async throws {
        let run = try await runScenario("08-asksign")
        #expect(run.cells.count == 2)
        let cell = run.cells[0]
        #expect(cell.contains { if case .question(let q) = $0 { q.contains("positive, negative or zero") } else { false } })
        #expect(Array(cell.suffix(2)) == [.prompt(label: 2), .finished(.completed)])
        #expect(run.states.contains(.question))
        #expect(run.transport.sent.contains("pos;\n"))
    }

    @Test func answerAddsTheTerminator() async throws {
        let transport = try ReplayTransport.fixture("08-asksign")
        let session = makeSession(transport)
        try await session.start()
        var it = try await session.evaluate(cellID: "a", text: "asksign(y)").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        try await session.answer("pos")
        await collect(&it, into: &events)
        #expect(transport.sent.contains("pos;\n"))
        #expect(events.last == .finished(.completed))
        await #expect(throws: MaximaError.noQuestion) { try await session.answer("pos") }
        await session.shutdown()
    }

    @Test func interrupts() async throws {
        let signal = try await runScenario("21-interrupt-sigint")
        #expect(signal.cells[0].contains(.interrupted))
        #expect(signal.cells[0].last == .finished(.interrupted))
        #expect(signal.transport.interruptPaths == [.signal])
        #expect(signal.cells[1].last == .finished(.completed))

        let channel = try await runScenario("22-interrupt-channel")
        #expect(channel.cells[0].last == .finished(.interrupted))
        #expect(channel.transport.interruptPaths == [.interrupt])
    }

    @Test func automaticInterruptFallsBackToSignalWithoutAChannel() async throws {
        let transport = try ReplayTransport.fixture("21-interrupt-sigint", hasChannel: false)
        let session = makeSession(transport)
        try await session.start()
        #expect(await session.interruptChannelReady == false)
        var it = try await session.evaluate(cellID: "a", text: "integrate(x^30*exp(-x^2)*sin(x)^20,x);").makeAsyncIterator()
        #expect(await session.interrupt() == .signal)
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.last == .finished(.interrupted))
        await session.shutdown()
    }

    @Test func interruptDropsQueuedCells() async throws {
        let transport = try ReplayTransport.fixture("22-interrupt-channel")
        let session = makeSession(transport)
        try await session.start()
        var first = try await session.evaluate(cellID: "a", text: "integrate(x^30*exp(-x^2)*sin(x)^20,x);").makeAsyncIterator()
        var second = try await session.evaluate(cellID: "b", text: "2+2; 3+3;").makeAsyncIterator()
        #expect(await session.interrupt() == .channel)
        var a: [CellEvent] = [], b: [CellEvent] = []
        await collect(&first, into: &a)
        await collect(&second, into: &b)
        #expect(a.last == .finished(.interrupted))
        #expect(b == [.skipped(Statement(text: "2+2;", terminator: .show)),
                      .skipped(Statement(text: "3+3;", terminator: .show)), .finished(.interrupted)])
        #expect(!transport.sent.contains("2+2;\n"))
        #expect(await session.state == .idle)
        #expect(await session.interrupt() == .nothingToInterrupt)
        await session.shutdown()
    }

    @Test func errorAbortsTheRestOfTheCell() async throws {
        let transport = try ReplayTransport.fixture("04-error-division")
        let session = makeSession(transport)
        try await session.start()
        var it = try await session.evaluate(cellID: "a", text: "1/0; 2+2;").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.suffix(3) == [.prompt(label: 2), .skipped(Statement(text: "2+2;", terminator: .show)),
                                     .finished(.failed(.maxima))])
        #expect(!transport.sent.contains("2+2;\n"))
        await session.shutdown()
    }

    @Test func errorCanContinueTheCell() async throws {
        let transport = try ReplayTransport.fixture("04-error-division")
        let session = makeSession(transport) { $0.abortCellOnError = false }
        try await session.start()
        var it = try await session.evaluate(cellID: "a", text: "1/0; 2+2;").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.contains(.started(index: 1, Statement(text: "2+2;", terminator: .show))))
        #expect(events.last == .finished(.failed(.maxima)))
        await session.shutdown()
    }

    @Test func preludeLines() async throws {
        let transport = try ReplayTransport.fixture("26-prelude")
        let session = makeSession(transport) { $0.lineWidth = 72 }
        try await session.start()
        var it = try await session.evaluate(cellID: "cell-1", text: "2+2; 3+3;").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.last == .finished(.completed))
        #expect(transport.sent[6] == GlueLisp.macsimaCommand(), "Macsima's own Lisp after the setup lines")
        let afterSetup = Array(transport.sent.dropFirst(7))
        #expect(afterSetup == [
            ":lisp-quiet (setq $linel 72)\n", ":lisp-quiet (setq *wx-cell-id* \"cell-1\")\n", "2+2;\n",
            ":lisp-quiet (setq $linel 72)\n", "3+3;\n",
        ])
        let setup = transport.sent[1...5]
        #expect(setup.contains { $0.contains("wx-open-interrupt-channel \"127.0.0.1\" 4242 \"PHASE0-TEST-TOKEN\"") })
        #expect(setup.contains { $0.contains("$maxima_tempdir \"/tmp/replay-not-real\"") })
        await session.shutdown()
    }

    @Test func additionalSetupLinesFollowTheStandardOnes() async throws {
        let transport = try ReplayTransport.fixture("01-integrate")
        let line = ":lisp-quiet (setq $wxplot_pngcairo t)\n"
        let session = makeSession(transport) { $0.additionalSetupLines = [line] }
        try await session.start()
        #expect(transport.sent.count == 8)
        #expect(transport.sent[7] == line, "after the glue, the five standard lines and macsima.lisp")
        var it = try await session.evaluate(cellID: "a", text: "integrate(sin(x), x);").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.last == .finished(.completed))
        await session.shutdown()
    }

    /// A :lisp-quiet line gets no prompt back (fixture 26), so the session
    /// must not wait for one before the next statement.
    @Test func lispQuietLineInACellDoesNotHang() async throws {
        let transport = try ReplayTransport.fixture("26-prelude")
        let session = makeSession(transport)
        try await session.start()
        let stream = try await session.evaluate(cellID: "a", text: ":lisp-quiet (setq a 1)\n2+2;")
        let events = await withTaskGroup(of: [CellEvent]?.self) { group in
            group.addTask { await drain(stream) }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        await session.shutdown()
        let got = try #require(events, "the cell never finished")
        #expect(got.contains(.started(index: 0, Statement(text: ":lisp-quiet (setq a 1)", terminator: .line))))
        #expect(got.contains(.started(index: 1, Statement(text: "2+2;", terminator: .show))))
        #expect(got.last == .finished(.completed))
        #expect(transport.sent.contains(":lisp-quiet (setq a 1)\n"))
    }

    @Test func asyncOutputIsRouted() async throws {
        // cell-A has finished: the output goes to the session's events.
        let run = try await runScenario("27-async")
        #expect(run.sessionEvents.contains(.async(cellID: "cell-A", content: "<mth><t>done</t></mth>")))

        // cell-A is still open: the output goes to its stream.
        let transport = try ReplayTransport.fixture("27-async")
        let session = makeSession(transport)
        try await session.start()
        var b = try await session.evaluate(cellID: "cell-B", text: "2+2;").makeAsyncIterator()
        var a = try await session.evaluate(cellID: "cell-A", text: "3+3;").makeAsyncIterator()
        var eb: [CellEvent] = [], ea: [CellEvent] = []
        await collect(&b, into: &eb)
        await collect(&a, into: &ea)
        #expect(ea.contains(.async("<mth><t>done</t></mth>")))
        #expect(!eb.contains { if case .async = $0 { true } else { false } })
        await session.shutdown()
    }

    @Test func lispMode() async throws {
        let run = try await runScenario("29-to-lisp")
        #expect(run.cells[0].suffix(2) == [.prompt(label: 0), .finished(.completed)])
        #expect(run.cells[1].contains(.started(index: 0, Statement(text: "(+ 1 2)", terminator: .line))))
        #expect(run.cells[1].contains(.text("3")) || run.cells[1].contains { if case .text(let t) = $0 { t.hasPrefix("3") } else { false } })
        #expect(run.cells[2].contains(.prompt(label: 2)))
        #expect(run.states.contains(.lisp))
        // No prelude lines are sent in Lisp mode.
        let i = try #require(run.transport.sent.firstIndex(of: "(+ 1 2)\n"))
        #expect(!run.transport.sent[i - 1].hasPrefix(":lisp-quiet"))
    }

    @Test func debugger() async throws {
        let run = try await runScenario("30-debugger")
        let cell = run.cells[1]
        #expect(cell.contains(.debugger(level: 1)))
        #expect(cell.contains(.error(.maxima, message: "x")))
        #expect(cell.last == .finished(.failed(.maxima)))
        #expect(run.states.contains(.debugger))
        #expect(run.transport.sent.contains(":top\n"))
    }

    @Test func quitEndsTheSession() async throws {
        let run = try await runScenario("25-quit")
        #expect(run.cells[0].last == .finished(.sessionDied("Maxima closed the connection")))
        #expect(run.sessionEvents.contains(.died("Maxima closed the connection")))
        #expect(run.finalState == .dead)
    }

    @Test func deathFinishesEveryOpenCell() async throws {
        let transport = ReplayTransport(startup: try ReplayTransport.split("01-integrate").startup, segments: [])
        let session = makeSession(transport)
        try await session.start()
        var a = try await session.evaluate(cellID: "a", text: "2+2; 3+3;").makeAsyncIterator()
        var b = try await session.evaluate(cellID: "b", text: "4+4;").makeAsyncIterator()
        var ea: [CellEvent] = [], eb: [CellEvent] = []
        await collect(&a, into: &ea)
        await collect(&b, into: &eb)
        #expect(ea.suffix(2) == [.skipped(Statement(text: "3+3;", terminator: .show)),
                                 .finished(.sessionDied("Maxima closed the connection"))])
        #expect(eb == [.skipped(Statement(text: "4+4;", terminator: .show)),
                       .finished(.sessionDied("Maxima closed the connection"))])
        await #expect(throws: MaximaError.notRunning) { try await session.evaluate(cellID: "c", text: "1;") }
        await session.shutdown()
    }

    @Test func wrongTokenFailsStart() async throws {
        let transport = try ReplayTransport.fixture("01-integrate")
        let session = makeSession(transport, token: "SOMETHING-ELSE")
        await #expect(throws: MaximaError.authenticationFailed("Maxima echoed a different token")) {
            try await session.start()
        }
        #expect(await session.state == .dead)
        #expect(transport.sent.count == 1, "only the glue went out, not the token-bearing setup lines")
    }

    @Test func unbalancedCellIsRefused() async throws {
        let session = makeSession(try ReplayTransport.fixture("01-integrate"))
        try await session.start()
        await #expect(throws: MaximaError.split(.unclosed("(", at: SourcePosition(line: 1, column: 2)))) {
            try await session.evaluate(cellID: "a", text: "f(x;")
        }
        await session.shutdown()
    }
}
