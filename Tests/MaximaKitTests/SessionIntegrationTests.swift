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
}
