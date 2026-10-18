// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

@Suite(.serialized)
struct ProcessTransportTests {
    /// Gathers scanner events from a transport's data.
    func collect(_ transport: ProcessTransport) -> (Collector<TransportEvent>, Collector<ScannerEvent>) {
        let raw = Collector<TransportEvent>()
        let scanned = Collector<ScannerEvent>()
        Task {
            var scanner = TagScanner()
            for await event in transport.events {
                await raw.append(event)
                if case .data(let d) = event {
                    for e in scanner.feed(d) { await scanned.append(e) }
                }
            }
        }
        return (raw, scanned)
    }

    @Test func missingExecutable() async throws {
        var config = MaximaConfiguration()
        config.maximaPath = "/nonexistent/maxima"
        let transport = try ProcessTransport(configuration: config)
        await #expect(throws: MaximaError.maximaNotFound("/nonexistent/maxima")) {
            try await transport.launch(token: "t")
        }
        await transport.terminate()
        #expect(!FileManager.default.fileExists(atPath: transport.tempDirectory))
    }

    @Test func exitsBeforeConnectingIsRetriedThenFails() async throws {
        let counter = FileManager.default.temporaryDirectory.appending(path: "macsima-count-\(UUID().uuidString)").path
        var config = MaximaConfiguration()
        config.maximaPath = try Integration.script("echo started >> '\(counter)'; echo 'no Lisp here' >&2; exit 3")
        let transport = try ProcessTransport(configuration: config)
        do {
            try await transport.launch(token: "t")
            Issue.record("launch succeeded")
        } catch {
            guard case .failedToStart(let attempts, let tail) = error else { Issue.record("\(error)"); return }
            #expect(attempts == 3)
            #expect(tail.contains("no Lisp here"))
        }
        let runs = (try? String(contentsOfFile: counter, encoding: .utf8))?.split(separator: "\n").count
        #expect(runs == 3)
        #expect(!FileManager.default.fileExists(atPath: transport.tempDirectory))
        try? FileManager.default.removeItem(atPath: counter)
    }

    @Test func slowStartThenTimeoutKillsTheGroup() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "macsima-pid-\(UUID().uuidString)").path
        var config = MaximaConfiguration()
        config.maximaPath = try Integration.script("echo $$ > '\(pidFile)'; sleep 60")
        config.slowStartWarning = .milliseconds(300)
        config.connectTimeout = .seconds(1)
        let transport = try ProcessTransport(configuration: config)
        let (raw, _) = collect(transport)
        await #expect(throws: MaximaError.connectTimeout(.seconds(1))) {
            try await transport.launch(token: "t")
        }
        #expect(await raw.wait(timeout: .seconds(1)) { $0.contains(.slowStart) })
        let pid = pid_t((try? String(contentsOfFile: pidFile, encoding: .utf8))?.trimmingWhitespace ?? "") ?? 0
        #expect(pid > 0)
        #expect(!Integration.groupAlive(pid), "the fake Maxima and its sleep are gone")
        try? FileManager.default.removeItem(atPath: pidFile)
    }

    @Test(.enabled(if: Integration.maximaAvailable))
    func realMaximaHandshake() async throws {
        let token = Integration.randomToken()
        let transport = try ProcessTransport(configuration: MaximaConfiguration())
        let (raw, scanned) = collect(transport)
        try await transport.launch(token: token)
        let group = try #require(transport.processGroup)

        transport.send(GlueLisp.command(from: try GlueLisp.bundledSource()))
        let keyed = await scanned.wait {
            $0.contains { if case .tag("suppressOutput", let c) = $0 { c.contains("<wxxml-key>\(token)</wxxml-key>") } else { false } }
        }
        #expect(keyed, "the glue echoed our token")
        transport.controlAuthenticated()
        for line in GlueLisp.setupLines(gnuplotPath: "/opt/homebrew/bin/gnuplot", port: transport.port,
                                        token: token, tempDirectory: transport.tempDirectory) {
            transport.send(line)
        }
        #expect(await raw.wait(timeout: .seconds(10)) { $0.contains(.interruptChannelReady) })

        transport.send("2+2;\n")
        #expect(await scanned.wait { $0.contains(.prompt("(%i2) ")) })
        let math = await scanned.items.compactMap { if case .math(let m) = $0 { m } else { nil } }
        #expect(math.last?.contains("<mn>4</mn>") == true)

        // maxima_tempdir points into the private folder.
        transport.send("maxima_tempdir;\n")
        #expect(await scanned.wait { $0.contains(.prompt("(%i3) ")) })
        let shown = await scanned.items.compactMap { if case .math(let m) = $0 { m } else { nil } }.last ?? ""
        #expect(shown.contains(transport.tempDirectory))

        let dir = transport.tempDirectory
        #expect(FileManager.default.fileExists(atPath: dir + "/maxima.log"))
        await transport.terminate()
        #expect(!Integration.groupAlive(group))
        #expect(!FileManager.default.fileExists(atPath: dir))
        #expect(await raw.wait(timeout: .seconds(2)) { $0.contains(.closed) || $0.contains { if case .exited = $0 { true } else { false } } })
    }
}
