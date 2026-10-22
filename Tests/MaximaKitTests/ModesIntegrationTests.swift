// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Questions, the debugger and Lisp mode against a real Maxima (Phase 3 step 12).
@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct ModesIntegrationTests {
    @Test(arguments: [InterruptMethod.channel, .signal])
    func interruptWhileAQuestionWaits(_ method: InterruptMethod) async throws {
        let session = MaximaSession()
        try await session.start()
        var it = try await session.evaluate(cellID: "q", text: "asksign(y); 3;").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(await session.state == .question)
        let result = await session.interrupt(via: method)
        await collect(&it, into: &events)
        // SIGINT sometimes reaches Maxima while it prints the question, and
        // it asks again (seen under load); interrupting again stops it, as
        // a second press of Interrupt does in the app.
        var again = 0
        while case .question? = events.last, again < 3 {
            again += 1
            _ = await session.interrupt(via: method)
            await collect(&it, into: &events)
        }
        print("interrupt via \(method): \(result); events after the question:", events.drop { if case .question = $0 { false } else { true } })
        #expect(events.last == .finished(.interrupted))
        #expect(await session.state == .idle)
        let next = await drain(try await session.evaluate(cellID: "n", text: "2+2;"))
        #expect(next.contains { if case .math(let m) = $0 { m.contains("<mn>4</mn>") } else { false } }, "Maxima still works")
        await session.shutdown()
    }

    @Test func debuggerFromDebugOnError() async throws {
        let session = MaximaSession()
        try await session.start()
        await session.setOption("debugmode", true)
        _ = await drain(try await session.evaluate(cellID: "d", text: "debugmode;"))
        var it = try await session.evaluate(cellID: "e", text: "h(x) := 1/x$ h(0); 5;").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.last == .debugger(level: 1), "the error enters the debugger")
        #expect(await session.state == .debugger)
        // An expression without a terminator is evaluated in the frame (the session adds ;).
        try await session.answer("x")
        await collect(&it, into: &events)
        #expect(events.contains(.text("0")) || events.contains { if case .math(let m) = $0 { m.contains("<mn>0</mn>") } else { false } },
                "x is 0 in h's frame: \(events)")
        try await session.answer(":bt")
        await collect(&it, into: &events)
        #expect(events.contains { if case .text(let t) = $0 { t.contains("#0: h(x=0)") } else { false } })
        try await session.answer(":top")
        await collect(&it, into: &events)
        #expect(events.last == .finished(.failed(.maxima)) || events.last == .finished(.completed) || events.last == .finished(.interrupted),
                "leaving the debugger ends the cell: \(String(describing: events.last))")
        #expect(await session.state == .idle)
        let next = await drain(try await session.evaluate(cellID: "n", text: "2+2;"))
        #expect(next.contains { if case .math(let m) = $0 { m.contains("<mn>4</mn>") } else { false } })
        await session.shutdown()
    }

    @Test func breakpointsInALoadedFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "macsima-dbm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "f.mac")
        try "f(x) := block([y],\n  y: x^2,\n  y: y + 1,\n  y * 10)$\n".write(to: file, atomically: true, encoding: .utf8)
        let session = MaximaSession()
        try await session.start()
        _ = await drain(try await session.evaluate(cellID: "l", text: "batchload(\"\(file.path)\")$"))
        // ":break" is a line of its own. It runs after :lisp-quiet lines
        // (the line width), which used to swallow its prompt.
        await session.setOption("debugmode", false)
        var it = try await session.evaluate(cellID: "b", text: ":break f 1\n:info :bkpt\nf(3);").makeAsyncIterator()
        var events: [CellEvent] = []
        await collect(&it, into: &events)
        #expect(events.contains { if case .text(let t) = $0 { t.hasPrefix("Bkpt 0 for f") } else { false } })
        #expect(events.last == .debugger(level: 1))
        // Emacs-style: two Ctrl-Z, then file:line::.
        #expect(events.contains(.text("\u{1A}\u{1A}\(file.path):2::")), "the stop's location")
        try await session.answer(":next")
        await collect(&it, into: &events)
        #expect(events.contains(.text("\u{1A}\u{1A}\(file.path):3::")))
        try await session.answer(":resume")
        await collect(&it, into: &events)
        #expect(events.contains { if case .math(let m) = $0 { m.contains("<mn>100</mn>") } else { false } })
        #expect(events.last == .finished(.completed))
        await session.shutdown()
    }

    @Test func lispMode() async throws {
        let session = MaximaSession()
        try await session.start()
        _ = await drain(try await session.evaluate(cellID: "a", text: "to_lisp();"))
        #expect(await session.state == .lisp)
        let lisp = await drain(try await session.evaluate(cellID: "b", text: "(+ 1\n   2)"))
        #expect(lisp.contains(.text("3")), "a form over two lines: \(lisp)")
        // Queries wait while in Lisp mode, and go out when Maxima is back.
        await session.setOption("debugmode", true)
        _ = await drain(try await session.evaluate(cellID: "c", text: "(to-maxima)"))
        #expect(await session.state == .idle)
        let check = await drain(try await session.evaluate(cellID: "d", text: "debugmode;"))
        #expect(check.contains { if case .math(let m) = $0 { m.contains("true") } else { false } })
        await session.shutdown()
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct AbortOnErrorTests {
    /// Three cells queued at once; the middle one fails. With `restartedWith`,
    /// after a restart with that configuration instead of `setAbortOnError`.
    private func run(abort: Bool, restartedWith restart: MaximaConfiguration? = nil) async throws -> [[CellEvent]] {
        let session = MaximaSession()
        try await session.start()
        if let restart { try await session.restart(configuration: restart) } else { await session.setAbortOnError(abort) }
        let streams = [
            try await session.evaluate(cellID: "a", text: "1+1;"),
            try await session.evaluate(cellID: "b", text: "1/0; 3;"),
            try await session.evaluate(cellID: "c", text: "4;"),
        ]
        var all: [[CellEvent]] = []
        for stream in streams { all.append(await drain(stream)) }
        await session.shutdown()
        return all
    }

    @Test func onStopsTheQueue() async throws {
        let cells = try await run(abort: true)
        #expect(cells[0].last == .finished(.completed))
        #expect(cells[1].last == .finished(.failed(.maxima)))
        #expect(cells[1].contains(.skipped(Statement(text: "3;", terminator: .show))))
        #expect(cells[2].last == .finished(.cancelled), "the cell after the error is not run")
        #expect(!cells[2].contains { if case .started = $0 { true } else { false } })
    }

    @Test func restartTakesTheNewConfiguration() async throws {
        var config = MaximaConfiguration()
        config.abortCellOnError = false
        let cells = try await run(abort: false, restartedWith: config)
        #expect(cells[2].last == .finished(.completed), "abort on error is off after the restart")
    }

    @Test func offGoesOn() async throws {
        let cells = try await run(abort: false)
        #expect(cells[1].contains { if case .math(let m) = $0 { m.contains("<mn>3</mn>") } else { false } },
                "the rest of the failing cell runs")
        #expect(cells[1].last == .finished(.failed(.maxima)))
        #expect(cells[2].last == .finished(.completed))
    }
}
