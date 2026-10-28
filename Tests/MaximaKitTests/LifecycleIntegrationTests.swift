// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// A computation that runs well over ten seconds on this machine (Phase 0).
let longComputation = "integrate(x^30*exp(-x^2)*sin(x)^20,x);"

struct OrphanGuardTests {
    @Test func registerAndUnregister() {
        let fake: pid_t = 999_999
        OrphanGuard.register(fake)
        #expect(OrphanGuard.registered.contains(fake))
        OrphanGuard.unregister(fake)
        #expect(!OrphanGuard.registered.contains(fake))
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct LifecycleIntegrationTests {
    @Test(arguments: [InterruptMethod.channel, .signal])
    func interruptLongComputation(_ method: InterruptMethod) async throws {
        let session = MaximaSession()
        try await session.start()
        #expect(await session.interruptChannelReady || method == .signal)
        let stream = try await session.evaluate(cellID: "a", text: longComputation + " 2+2;")
        try await Task.sleep(for: .seconds(2))
        #expect(await session.state == .busy)
        let result = await session.interrupt(via: method)
        #expect(result == (method == .channel ? .channel : .signal))
        let events = await drain(stream)
        #expect(events.contains(.interrupted))
        #expect(events.contains(.skipped(Statement(text: "2+2;", terminator: .show))))
        #expect(events.last == .finished(.interrupted))
        #expect(await session.state == .idle)
        let after = await drain(try await session.evaluate(cellID: "b", text: "2+2;"))
        #expect(after.last == .finished(.completed))
        await session.shutdown()
    }

    @Test func restartWhileBusyLeavesNothingBehind() async throws {
        let session = MaximaSession()
        try await session.start()
        let firstGroup = try #require(await session.processGroup)
        let firstDir = try #require(await session.tempDirectory)
        #expect(OrphanGuard.registered.contains(firstGroup))

        let busy = try await session.evaluate(cellID: "a", text: longComputation)
        try await Task.sleep(for: .seconds(1))
        let clock = ContinuousClock()
        let took = try await clock.measure { try await session.restart() }
        print("restart while busy took \(took)")
        let events = await drain(busy)
        #expect(events.last == .finished(.sessionDied(MaximaSession.restartReason)))
        #expect(!Integration.groupAlive(firstGroup), "the busy Maxima is gone")
        #expect(!FileManager.default.fileExists(atPath: firstDir))
        #expect(!OrphanGuard.registered.contains(firstGroup))

        let secondGroup = try #require(await session.processGroup)
        #expect(secondGroup != firstGroup)
        let after = await drain(try await session.evaluate(cellID: "b", text: "2+2;"))
        #expect(after.contains { if case .math(let m) = $0 { m.contains("<mn>4</mn>") } else { false } })

        await session.shutdown()
        #expect(!Integration.groupAlive(secondGroup))
        #expect(await session.processGroups == [firstGroup, secondGroup])
        #expect(Set(OrphanGuard.registered).isDisjoint(with: [firstGroup, secondGroup]))
    }

    @Test func killWhileBusy() async throws {
        let session = MaximaSession()
        try await session.start()
        let group = try #require(await session.processGroup)
        let busy = try await session.evaluate(cellID: "a", text: longComputation)
        try await Task.sleep(for: .seconds(1))
        await session.kill()
        #expect(await drain(busy).last == .finished(.sessionDied("Maxima was stopped")))
        #expect(await session.state == .dead)
        #expect(!Integration.groupAlive(group))
        await #expect(throws: MaximaError.notRunning) { try await session.evaluate(cellID: "b", text: "1;") }
        try await session.start()
        #expect(await drain(try await session.evaluate(cellID: "c", text: "1+1;")).last == .finished(.completed))
        await session.shutdown()
    }

    @Test func plotFilesAreRemovedOnShutdown() async throws {
        let session = MaximaSession()
        try await session.start()
        let dir = try #require(await session.tempDirectory)
        let events = await drain(try await session.evaluate(cellID: "p", text: "wxplot2d(sin(x), [x, 0, %pi]);"))
        #expect(events.last == .finished(.completed))
        let image = events.compactMap { e -> String? in
            guard case .math(let m) = e, let a = m.range(of: "<img"), let gt = m.range(of: ">", range: a.upperBound..<m.endIndex),
                  let end = m.range(of: "</img>") else { return nil }
            return String(m[gt.upperBound..<end.lowerBound])
        }.first
        let path = try #require(image)
        #expect(path.hasPrefix(dir + "/maxout_"), "the plot lands in the private temp folder")
        #expect(FileManager.default.fileExists(atPath: path))
        let pids = try FileManager.default.contentsOfDirectory(atPath: dir)
        print("temp folder before shutdown: \(pids)")
        await session.shutdown()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!FileManager.default.fileExists(atPath: dir))
    }
}
