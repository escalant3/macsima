// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Reads a whole cell stream (answering nothing).
func drain(_ stream: AsyncStream<CellEvent>) async -> [CellEvent] {
    var events: [CellEvent] = []
    for await e in stream { events.append(e) }
    return events
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct SessionIntegrationTests {
    @Test func realSessionSmoke() async throws {
        let session = MaximaSession()
        try await session.start()
        #expect(await session.state == .idle)
        let group = try #require(await session.processGroup)
        let dir = try #require(await session.tempDirectory)

        let ok = await drain(try await session.evaluate(cellID: "a", text: "2+2; x: 5$ x^2;"))
        #expect(ok.last == .finished(.completed))
        #expect(ok.contains { if case .math(let m) = $0 { m.contains("<mn>25</mn>") } else { false } })

        let failing = await drain(try await session.evaluate(cellID: "b", text: "1/0; 7;"))
        #expect(failing.contains(.error(.maxima, message: "expt: undefined: 0 to a negative exponent.")))
        #expect(failing.contains(.skipped(Statement(text: "7;", terminator: .show))))

        let lisp = await drain(try await session.evaluate(cellID: "c", text: ":lisp (+ 1 2)"))
        #expect(lisp.contains { if case .text(let t) = $0 { t.contains("3") } else { false } })
        #expect(lisp.last == .finished(.completed))

        var it = try await session.evaluate(cellID: "d", text: "asksign(y);").makeAsyncIterator()
        var asked: [CellEvent] = []
        await collect(&it, into: &asked)
        #expect(await session.state == .question)
        try await session.answer("pos")
        await collect(&it, into: &asked)
        #expect(asked.last == .finished(.completed))

        await session.shutdown()
        #expect(await session.state == .dead)
        #expect(!Integration.groupAlive(group))
        #expect(!FileManager.default.fileExists(atPath: dir))
    }

    @Test func pngcairoThroughAdditionalSetupLines() async throws {
        var config = MaximaConfiguration()
        config.additionalSetupLines = [":lisp-quiet (setq $wxplot_pngcairo t)\n"]
        let session = MaximaSession(configuration: config)
        try await session.start()
        let flag = await drain(try await session.evaluate(cellID: "a", text: "wxplot_pngcairo;"))
        #expect(flag.contains { if case .math(let m) = $0 { m.contains(">true<") } else { false } })
        let plot = await drain(try await session.evaluate(cellID: "b", text: "wxplot2d(sin(x), [x, 0, %pi]);"))
        #expect(plot.last == .finished(.completed))
        #expect(plot.contains { if case .math(let m) = $0 { m.contains(".png</img>") } else { false } })
        await session.shutdown()
    }

    @Test func lispQuietLineInACell() async throws {
        let session = MaximaSession()
        try await session.start()
        let events = await drain(try await session.evaluate(cellID: "a", text: ":lisp-quiet (setq $zz 5)\nzz;"))
        #expect(events.last == .finished(.completed))
        #expect(events.contains { if case .math(let m) = $0 { m.contains("<mn>5</mn>") } else { false } })
        await session.shutdown()
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct ProcessCPUTests {
    @Test func busyMaximaUsesACore() async throws {
        let session = MaximaSession()
        try await session.start()
        let group = try #require(await session.processGroup)
        let idle = try #require(ProcessCPU.time(ofGroup: group))
        // About two seconds of work.
        _ = idle
        let stream = try await session.evaluate(cellID: "a", text: "for i thru 3000000 do x: i^2$")
        // Measured from when Maxima is at work, over a second.
        while await session.state != .busy { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        let before = try #require(ProcessCPU.time(ofGroup: group))
        try await Task.sleep(for: .seconds(1))
        let busy = try #require(ProcessCPU.time(ofGroup: group))
        let percent = ProcessCPU.percent(from: before, to: busy, over: clock.now - start)
        // One busy SBCL thread: about 100%, less when the full suite loads
        // every core (it measured 40% then).
        #expect(percent > 20 && percent < 200, "one busy SBCL thread: \(percent)%")
        _ = await drain(stream)
        await session.shutdown()
        #expect(ProcessCPU.time(ofGroup: group) == nil, "nothing left to read after shutdown")
    }
}
